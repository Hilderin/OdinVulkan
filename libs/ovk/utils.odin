package ovk


import "core:fmt"
import "core:reflect"

import vk "vendor:vulkan"

// Check if a result from a Vulkan API call is a success and panic with a detailed error otherwise.
// Temporary: will be removed once all code uses the error-returning `check` instead.
check_panic :: proc(result: vk.Result, operation: string, loc := #caller_location) {
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

// Check if a result from a Vulkan API call is a success and returns an error struct otherwise.
check :: proc(result: vk.Result, operation: string, loc := #caller_location) -> (err: Error) {
	if result == .SUCCESS {
		return
	}

	err = Vulkan_Error{result, fmt.tprint(operation, reflect.enum_string(result)), loc}
	return
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
