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

// Search for memory type on a physical device
find_memory_type :: proc(physical_device: vk.PhysicalDevice, type_filter: u32, properties: vk.MemoryPropertyFlags) -> (u32, Error) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i)) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, nil
		}
	}


	return 0, General_Error{"Failed to find memory type."}
}

// Returns the maximum usable sample for a physical device.
get_max_usable_sample_count :: proc(physical_device: vk.PhysicalDevice) -> vk.SampleCountFlags {
	physical_device_props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &physical_device_props)

	counts := physical_device_props.limits.framebufferColorSampleCounts & physical_device_props.limits.framebufferDepthSampleCounts
	if (counts & {._64}) == {._64} {return {._64}}
	if (counts & {._32}) == {._32} {return {._32}}
	if (counts & {._16}) == {._16} {return {._16}}
	if (counts & {._8}) == {._8} {return {._8}}
	if (counts & {._4}) == {._4} {return {._4}}
	if (counts & {._2}) == {._2} {return {._2}}

	return {._1}
}

// Return the best format for the depth image
find_depth_format :: proc(physical_device: vk.PhysicalDevice) -> (vk.Format, Error) {
	return find_supported_format(physical_device, {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

// Check if a format contains a stencil element
has_stencil_component :: proc(format: vk.Format) -> bool {
	return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}

// Find the best format according the the passed arguments.
@(private = "file")
find_supported_format :: proc(physical_device: vk.PhysicalDevice, candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> (vk.Format, Error) {
	for format in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &props)

		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
			return format, nil
		}

		if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
			return format, nil
		}
	}

	return {}, General_Error{"Failed to find a supported format"}
}
