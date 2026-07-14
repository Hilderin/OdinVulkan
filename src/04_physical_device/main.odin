package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:reflect"

import "vendor:glfw"
import vk "vendor:vulkan"

// Globals needed for debug messenger cleanup.
g_debug_messenger: vk.DebugUtilsMessengerEXT = {}

// Debug level — controls which severities are enabled and printed.
g_debug_level: vk.DebugUtilsMessageSeverityFlagsEXT = {.WARNING, .ERROR}

// Required validation layers.
g_validation_layers := []cstring{"VK_LAYER_KHRONOS_validation"}


vk_check :: proc(result: vk.Result, operation: string, loc := #caller_location) {
	if result == .SUCCESS {
		return
	}

	p := context.assertion_failure_proc

	when ODIN_DEBUG {
		p(operation, reflect.enum_string(result), loc)
	} else {
		p(operation, "Vulkan operation failed", loc)
	}
}


debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	// "system" callbacks are called from C without an Odin context, we need to specify the default context to compile.
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


create_instance :: proc() -> vk.Instance {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	if !are_layers_supported(g_validation_layers) {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		os.exit(1)
	}

	app_info := vk.ApplicationInfo {
		sType              = vk.StructureType.APPLICATION_INFO,
		pApplicationName   = "Vulkan initialization",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_4,
	}

	extensions := glfw.GetRequiredInstanceExtensions()
	ext_names: [dynamic]cstring
	defer delete(ext_names)
	append(&ext_names, ..extensions)
	append(&ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

	debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = g_debug_level,
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_callback,
		pUserData       = nil,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(ext_names)),
		ppEnabledExtensionNames = raw_data(ext_names[:]),
		enabledLayerCount       = u32(len(g_validation_layers)),
		ppEnabledLayerNames     = raw_data(g_validation_layers),
		pNext                   = &debug_create_info,
	}

	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "failed to create instance!")
	vk.load_proc_addresses_instance(instance)

	if vk.CreateDebugUtilsMessengerEXT != nil {
		vk_check(vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &g_debug_messenger), "failed to create debug messenger!")
	}

	return instance
}


are_layers_supported :: proc(required_layers: []cstring) -> b32 {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count)
	defer delete(available_layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	for req_layer in required_layers {
		found := false
		for &layer in available_layers {
			if cstring(&layer.layerName[0]) == req_layer {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}

find_queue_families :: proc(physical_device: vk.PhysicalDevice, queue_flags: vk.QueueFlags) -> (u32, bool) {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))

	for queue_family, i in queue_families {
		if (queue_flags & queue_family.queueFlags) == queue_flags {
			return u32(i), true
		}
	}
	return 0, false
}

get_device_features :: proc(
	device: vk.PhysicalDevice,
) -> (
	vk.PhysicalDeviceVulkan11Features,
	vk.PhysicalDeviceVulkan13Features,
	vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT,
	vk.PhysicalDeviceFeatures,
) {
	vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}
	extended_dynamic_state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType = vk.StructureType.PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
	}
	vulkan13_features.pNext = &extended_dynamic_state_features

	vulkan11_features := vk.PhysicalDeviceVulkan11Features {
		sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = &vulkan13_features,
	}

	features2 := vk.PhysicalDeviceFeatures2 {
		sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2,
		pNext = &vulkan11_features,
	}

	vk.GetPhysicalDeviceFeatures2(device, &features2)
	return vulkan11_features, vulkan13_features, extended_dynamic_state_features, features2.features
}

score_device :: proc(device: vk.PhysicalDevice) -> int {
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
	if _, ok := find_queue_families(device, {.GRAPHICS}); !ok {
		fmt.printfln("  %q — no graphics queue (skipped)", name)
		return -1
	}

	// Must support all required device extensions.
	required_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

	{
		ext_count: u32
		vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)
		available_exts := make([]vk.ExtensionProperties, ext_count)
		defer delete(available_exts)
		vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, raw_data(available_exts))

		for req_ext in required_extensions {
			found := false
			for &ext in available_exts {
				if cstring(&ext.extensionName[0]) == req_ext {
					found = true
					break
				}
			}
			if !found {
				fmt.printfln("  %q — missing required extension %s (skipped)", name, req_ext)
				return -1
			}
		}
	}

	vulkan11_f, vulkan13_f, ext_dynamic_f, base_f := get_device_features(device)

	if !vulkan11_f.shaderDrawParameters {
		fmt.printfln("  %q — missing shaderDrawParameters (skipped)", name)
		return -1
	}
	if !vulkan13_f.dynamicRendering {
		fmt.printfln("  %q — missing dynamicRendering (skipped)", name)
		return -1
	}
	if !ext_dynamic_f.extendedDynamicState {
		fmt.printfln("  %q — missing extendedDynamicState (skipped)", name)
		return -1
	}
	if !base_f.geometryShader {
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

pick_physical_device :: proc(instance: vk.Instance) -> vk.PhysicalDevice {
	dev_count: u32
	vk.EnumeratePhysicalDevices(instance, &dev_count, nil)
	if dev_count == 0 {
		fmt.eprintln("failed to find GPUs with Vulkan support!")
		os.exit(1)
	}

	physical_devices := make([]vk.PhysicalDevice, dev_count)
	defer delete(physical_devices)
	vk.EnumeratePhysicalDevices(instance, &dev_count, raw_data(physical_devices))

	best_score := -1
	best_device: vk.PhysicalDevice = nil

	for device in physical_devices {
		s := score_device(device)
		if s > best_score {
			best_score = s
			best_device = device
		}
	}

	if best_device == nil {
		fmt.eprintln("failed to find a suitable GPU!")
		os.exit(1)
	}

	fmt.printfln("Selected physical device (score=%d)", best_score)
	return best_device
}

main :: proc() {
	fmt.println("Vulkan initialization")
	fmt.println("-------------------------------------------")

	// We need to initialize GLFW so the glfw.GetInstanceProcAddress() method returns a valid callback to load Vulkan function addresses.
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	// Create Vulkan instance...
	instance := create_instance()
	fmt.println("Create instance... OK")

	// Pick physical device
	_ = pick_physical_device(instance)
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
