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
