package main

import "base:runtime"
import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"

// Globals needed for debug messenger cleanup.
g_debug_messenger: vk.DebugUtilsMessengerEXT = {}

// Debug level — controls which severities are enabled and printed.
g_debug_level: vk.DebugUtilsMessageSeverityFlagsEXT = {.WARNING, .ERROR}


debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	// "system" callbacks are called from C without an Odin context, we need to specift the default context to compile.
	context = runtime.default_context()
	if .ERROR in messageSeverity && .ERROR in g_debug_level {
		fmt.eprintfln("[validation ERROR] %s", pCallbackData.pMessage)
	} else if .WARNING in messageSeverity && .WARNING in g_debug_level {
		fmt.eprintfln("[validation WARNING] %s", pCallbackData.pMessage)
	} else if .INFO in messageSeverity && .INFO in g_debug_level {
		fmt.println("[validation INFO]", pCallbackData.pMessage)
	} else if .VERBOSE in messageSeverity && .VERBOSE in g_debug_level {
		fmt.printfln("[validation VERBOSE] %s", pCallbackData.pMessage)
	}
	return false
}


createInstance :: proc() -> (vk.Instance, bool) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	if !check_ValidationLayerSupport() {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SFK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		return nil, false
	}

	appInfo: vk.ApplicationInfo
	appInfo.sType = vk.StructureType.APPLICATION_INFO
	appInfo.pApplicationName = "Vulkan initialization"
	appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.pEngineName = "No Engine"
	appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.apiVersion = vk.API_VERSION_1_4


	createInfo: vk.InstanceCreateInfo
	createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO
	createInfo.pApplicationInfo = &appInfo

	extensions := glfw.GetRequiredInstanceExtensions()
	extNames: [dynamic]cstring
	defer delete(extNames)
	append(&extNames, ..extensions)
	append(&extNames, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

	createInfo.enabledExtensionCount = u32(len(extNames))
	createInfo.ppEnabledExtensionNames = raw_data(extNames[:])

	//createInfo.enabledLayerCount = 0

	// Debug messenger create info — chained in pNext to intercept
	// messages DURING instance creation.
	debugCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
	debugCreateInfo.sType = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	debugCreateInfo.messageSeverity = g_debug_level
	debugCreateInfo.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE}
	debugCreateInfo.pfnUserCallback = debug_callback
	debugCreateInfo.pUserData = nil

	createInfo.pNext = &debugCreateInfo

	result: vk.Result
	instance: vk.Instance
	result = vk.CreateInstance(&createInfo, nil, &instance)
	if result != vk.Result.SUCCESS {
		fmt.eprintln("failed to create instance!")
		return nil, false
	}
	vk.load_proc_addresses_instance(instance)

	// Once the instance is created, install the persistent messenger.
	if vk.CreateDebugUtilsMessengerEXT != nil {
		if vk.CreateDebugUtilsMessengerEXT(instance, &debugCreateInfo, nil, &g_debug_messenger) != vk.Result.SUCCESS {
			fmt.eprintln("failed to create debug messenger!")
			return nil, false
		}
	}

	return instance, true
}


check_ValidationLayerSupport :: proc() -> b32 {
	layerCount: u32
	vk.EnumerateInstanceLayerProperties(&layerCount, nil)
	availableLayers := make([]vk.LayerProperties, layerCount)
	defer delete(availableLayers)
	vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))

	for i in 0 ..< len(availableLayers) {
		if cstring(&availableLayers[i].layerName[0]) == "VK_LAYER_KHRONOS_validation" {
			return true
		}
	}
	return false
}

findQueueFamilies :: proc(physicalDevice: vk.PhysicalDevice, queueFlags: vk.QueueFlags) -> (u32, bool) {
	queueFamilyCount: u32 = 0
	vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nil)

	queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyCount)
	queueFamiliesRaw := raw_data(queueFamilies)
	vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, queueFamiliesRaw)

	i: u32 = 0
	for queueFamily in queueFamilies {
		if (queueFlags & queueFamily.queueFlags) == queueFlags {
			return i, true
		}
		i += 1
	}
	return 0, false
}

getDeviceFeatures :: proc(
	device: vk.PhysicalDevice,
) -> (
	vk.PhysicalDeviceVulkan11Features,
	vk.PhysicalDeviceVulkan13Features,
	vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT,
	vk.PhysicalDeviceFeatures,
) {
	vulkan11Features: vk.PhysicalDeviceVulkan11Features
	vulkan11Features.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES

	vulkan13Features: vk.PhysicalDeviceVulkan13Features
	vulkan13Features.sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_3_FEATURES

	extendedDynamicStateFeatures: vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT
	extendedDynamicStateFeatures.sType = vk.StructureType.PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT

	features2: vk.PhysicalDeviceFeatures2
	features2.sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2
	features2.pNext = &vulkan11Features
	vulkan11Features.pNext = &vulkan13Features
	vulkan13Features.pNext = &extendedDynamicStateFeatures

	vk.GetPhysicalDeviceFeatures2(device, &features2)
	return vulkan11Features, vulkan13Features, extendedDynamicStateFeatures, features2.features
}

scoreDevice :: proc(device: vk.PhysicalDevice) -> int {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &props)

	name := string(cstring(&props.deviceName[0]))

	// Require at least Vulkan 1.4.
	if props.apiVersion < vk.API_VERSION_1_4 {
		fmt.printfln(
			"  %q — apiVersion=%d.%d.%d, < 1.4 (skipped)",
			name,
			vk.API_VERSION_MAJOR(props.apiVersion),
			vk.API_VERSION_MINOR(props.apiVersion),
			vk.API_VERSION_PATCH(props.apiVersion),
		)
		return -1
	}

	// Must have at least a graphics queue family.
	if _, ok := findQueueFamilies(device, {.GRAPHICS}); !ok {
		fmt.printfln("  %q — no graphics queue (skipped)", name)
		return -1
	}

	// Must support all required device extensions.
	requiredExtensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	{
		extCount: u32 = 0
		vk.EnumerateDeviceExtensionProperties(device, nil, &extCount, nil)
		availableExts := make([]vk.ExtensionProperties, extCount)
		defer delete(availableExts)
		vk.EnumerateDeviceExtensionProperties(device, nil, &extCount, raw_data(availableExts))

		for reqExt in requiredExtensions {
			found := false
			for i in 0 ..< len(availableExts) {
				extName := string(cstring(&availableExts[i].extensionName[0]))
				if extName == string(reqExt) {
					found = true
					break
				}
			}
			if !found {
				fmt.printfln("  %q — missing required extension %s (skipped)", name, string(reqExt))
				return -1
			}
		}
	}

	vulkan11F, vulkan13F, extDynamicF, baseF := getDeviceFeatures(device)

	if !vulkan11F.shaderDrawParameters {
		fmt.printfln("  %q — missing shaderDrawParameters (skipped)", name)
		return -1
	}
	if !vulkan13F.dynamicRendering {
		fmt.printfln("  %q — missing dynamicRendering (skipped)", name)
		return -1
	}
	if !extDynamicF.extendedDynamicState {
		fmt.printfln("  %q — missing extendedDynamicState (skipped)", name)
		return -1
	}
	if !baseF.geometryShader {
		fmt.printfln("  %q — missing geometryShader (skipped)", name)
		return -1
	}

	score := 0

	// Discrete GPUs have a significant performance advantage.
	if props.deviceType == .DISCRETE_GPU {
		score += 1000
	} else if props.deviceType == .INTEGRATED_GPU {
		score += 500
	}


	// Maximum possible size of textures affects graphics quality.
	score += int(props.limits.maxImageDimension2D)

	fmt.printfln("  %q — type=%v, score=%d", name, props.deviceType, score)
	return score
}

pickPhysicalDevice :: proc(instance: vk.Instance) -> (vk.PhysicalDevice, bool) {
	devCount: u32 = 0
	vk.EnumeratePhysicalDevices(instance, &devCount, nil)
	if devCount == 0 {
		fmt.eprintln("failed to find GPUs with Vulkan support!")
		return nil, false
	}

	physicalDevices := make([]vk.PhysicalDevice, devCount)
	defer delete(physicalDevices)
	vk.EnumeratePhysicalDevices(instance, &devCount, raw_data(physicalDevices))

	bestScore := -1
	bestDevice: vk.PhysicalDevice = nil

	for device in physicalDevices {
		s := scoreDevice(device)
		if s > bestScore {
			bestScore = s
			bestDevice = device
		}
	}

	if bestDevice == nil {
		fmt.eprintln("failed to find a suitable GPU!")
		return nil, false
	}

	fmt.printfln("Selected physical device (score=%d)", bestScore)
	return bestDevice, true
}

main :: proc() {
	fmt.println("Vulkan initialization")
	fmt.println("-------------------------------------------")

	// We need to initialize GLFW so the glfw.GetInstanceProcAddress() method returns a valid callback to load Vulkan function addresses.
	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	if (!glfw.Init()) {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}


	// Create Vulkan instance...
	instance: vk.Instance
	result: bool
	instance, result = createInstance()
	if (!result) {
		fmt.eprintln("Create instance failed.")
		os.exit(1)
	}
	fmt.println("Create instance... OK")


	// Pick physical device
	physical_device: vk.PhysicalDevice
	physical_device, result = pickPhysicalDevice(instance)
	if !result {
		fmt.eprintln("Compatible physical device not found.")
		os.exit(1)
	}
	fmt.println("Physical device... OK")


	fmt.println()
	fmt.println("Vulkan initialization completed with success!")

	// Cleanup
	if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
		vk.DestroyDebugUtilsMessengerEXT(instance, g_debug_messenger, nil)
	}
	if instance != nil {
		vk.DestroyInstance(instance, nil)
	}
}
