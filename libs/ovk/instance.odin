package ovk

import "base:runtime"
import "core:fmt"
import "core:strings"

import vk "vendor:vulkan"


// Required validation layers.
validation_layers :: []cstring{"VK_LAYER_KHRONOS_validation"}

// Struct containing the Vulkan instance and init information.
Instance :: struct {
	vk_instance:     vk.Instance,
	debug_messenger: vk.DebugUtilsMessengerEXT,
}

// Struct containing the Vulkan instance and init information.
Create_Instance_Args :: struct {
	application_name:       string,
	application_version:    u32,
	engine_name:            string,
	engine_version:         u32,

	// Pointer to a proc to load Vulkan proc addresses.
	get_instance_proc_addr: rawptr,

	// Extensions
	extensions:             []cstring,

	// Enable debug messages and validation layers
	debug:                  bool,

	// Debug level - controls which severities are enabled and printed.
	debug_level:            vk.DebugUtilsMessageSeverityFlagsEXT,
}

// Create the Vulkan instance.
create_instance :: proc(args: Create_Instance_Args) -> (instance: Instance, err: Error) {

	// Load the dynamic Vulkan API functions
	vk.load_proc_addresses(args.get_instance_proc_addr)

	// Check if validation layers are available to debug.
	if args.debug {
		if !are_layers_supported(validation_layers) {
			err = General_Error {
				"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
			}
			return
		}
	}

	application_name := strings.clone_to_cstring(args.application_name)
	defer delete(application_name)
	engine_name := strings.clone_to_cstring(args.engine_name)
	defer delete(engine_name)

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = application_name,
		applicationVersion = args.application_version,
		pEngineName        = engine_name,
		engineVersion      = args.engine_version,
		apiVersion         = vk.API_VERSION_1_4,
	}

	ext_names: [dynamic]cstring
	defer delete(ext_names)

	if args.extensions != nil {
		append(&ext_names, ..args.extensions)
	}


	debug_create_info: vk.DebugUtilsMessengerCreateInfoEXT
	if args.debug {
		append(&ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		debug_create_info = vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = args.debug_level,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = debug_callback,
			pUserData       = nil,
		}
	}

	layers: [dynamic]cstring
	defer delete(layers)

	// Add the validation layers in debug mode.
	if args.debug {
		append(&layers, ..validation_layers)
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(ext_names)),
		ppEnabledExtensionNames = raw_data(ext_names[:]),
		enabledLayerCount       = u32(len(layers)),
		ppEnabledLayerNames     = raw_data(layers),
		pNext                   = args.debug ? &debug_create_info : nil,
	}

	check(vk.CreateInstance(&create_info, nil, &instance.vk_instance), "failed to create instance!") or_return

	vk.load_proc_addresses_instance(instance.vk_instance)

	if args.debug && vk.CreateDebugUtilsMessengerEXT != nil {
		check(vk.CreateDebugUtilsMessengerEXT(instance.vk_instance, &debug_create_info, nil, &instance.debug_messenger), "failed to create debug messenger!") or_return
	}

	return
}

// Destroy the instance.
destroy_instance :: proc(instance: ^Instance) {
	if instance == nil || instance.vk_instance == nil {
		return
	}

	if vk.DestroyDebugUtilsMessengerEXT != nil {
		vk.DestroyDebugUtilsMessengerEXT(instance.vk_instance, instance.debug_messenger, nil)
	}

	vk.DestroyInstance(instance.vk_instance, nil)
}


// Check if all layers in parameters are supported by the device.
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


// Callback executed when a debug message is received.
@(private = "file")
debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	// "system" callbacks are called from C without an Odin context, we need to specify the default context to compile.
	context = runtime.default_context()
	if .ERROR in messageSeverity {
		fmt.eprintfln("[validation ERROR] %s", pCallbackData.pMessage)
	} else if .WARNING in messageSeverity {
		fmt.eprintfln("[validation WARNING] %s", pCallbackData.pMessage)
	} else if .INFO in messageSeverity {
		fmt.println("[validation INFO]", pCallbackData.pMessage)
	} else if .VERBOSE in messageSeverity {
		fmt.printfln("[validation VERBOSE] %s", pCallbackData.pMessage)
	}
	return false
}
