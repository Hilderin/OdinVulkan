package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:reflect"

import "vendor:glfw"
import vk "vendor:vulkan"

// Globals needed for debug messenger cleanup.
debug_messenger: vk.DebugUtilsMessengerEXT = {}

// Debug level - controls which severities are enabled and printed.
debug_level: vk.DebugUtilsMessageSeverityFlagsEXT = {.WARNING, .ERROR}

// Required validation layers.
validation_layers := []cstring{"VK_LAYER_KHRONOS_validation"}


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
	if .ERROR in messageSeverity && .ERROR in debug_level {
		fmt.eprintfln("[validation ERROR] %s", pCallbackData.pMessage)
	} else if .WARNING in messageSeverity && .WARNING in debug_level {
		fmt.eprintfln("[validation WARNING] %s", pCallbackData.pMessage)
	} else if .INFO in messageSeverity && .INFO in debug_level {
		fmt.println("[validation INFO]", pCallbackData.pMessage)
	} else if .VERBOSE in messageSeverity && .VERBOSE in debug_level {
		fmt.printfln("[validation VERBOSE] %s", pCallbackData.pMessage)
	}
	return false
}


create_instance :: proc() -> vk.Instance {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	if !are_layers_supported(validation_layers) {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		os.exit(1)
	}

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Odin Vulkan Tutorial",
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

	// Debug messenger create info - chained in pNext to intercept
	// messages DURING instance creation.
	debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = debug_level,
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_callback,
		pUserData       = nil,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(ext_names)),
		ppEnabledExtensionNames = raw_data(ext_names[:]),
		enabledLayerCount       = u32(len(validation_layers)),
		ppEnabledLayerNames     = raw_data(validation_layers),
		pNext                   = &debug_create_info,
	}

	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "failed to create instance!")
	vk.load_proc_addresses_instance(instance)

	// Once the instance is created, install the persistent messenger.
	if vk.CreateDebugUtilsMessengerEXT != nil {
		vk_check(vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &debug_messenger), "failed to create debug messenger!")
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


main :: proc() {
	fmt.println("Odin Vulkan Tutorial")
	fmt.println("-------------------------------------------")

	// We need to initialize GLFW so the glfw.GetInstanceProcAddress() method returns a valid callback to load Vulkan function addresses.
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	// Create Vulkan instance...
	instance := create_instance()
	fmt.println("Create instance... OK")

	fmt.println()
	fmt.println("Vulkan initialization completed with success!")

	// Cleanup
	if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
		vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
	}
	if instance != nil {
		vk.DestroyInstance(instance, nil)
	}
}
