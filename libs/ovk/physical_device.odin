package ovk


import vk "vendor:vulkan"

// Information on the physical device.
Physical_Device :: struct {
	instance:              ^Instance,
	vk_physical_device:    vk.PhysicalDevice,
	graphics_queue_family: u32,
	compute_queue_family:  u32,
	transfer_queue_family: u32,
}

// Arguments to get the physical device.
Get_Physical_Device_Args :: struct {
	instance:            ^Instance,
	surface:             vk.SurfaceKHR,
	required_extensions: []cstring,
}

// Returns the best physical device to use.
get_physical_device :: proc(args: Get_Physical_Device_Args) -> (physical_device: Physical_Device, err: Error) {
	dev_count: u32
	vk.EnumeratePhysicalDevices(args.instance.vk_instance, &dev_count, nil)
	assert(dev_count != 0, "Failed to find GPUs with Vulkan support, no GPU found.") or_return

	physical_devices := make([]vk.PhysicalDevice, dev_count)
	defer delete(physical_devices)
	vk.EnumeratePhysicalDevices(args.instance.vk_instance, &dev_count, raw_data(physical_devices))

	best_score := -1
	best_device: vk.PhysicalDevice = nil

	for device in physical_devices {
		s := score_device(device, args.surface, args.required_extensions)
		if s > best_score {
			best_score = s
			best_device = device
		}
	}

	assert(best_device != nil, "Failed to find a suitable GPU.") or_return

	// Create the physical device.
	physical_device = {
		instance           = args.instance,
		vk_physical_device = best_device,
	}

	// Search for the graphics queue
	ok: bool
	physical_device.graphics_queue_family, ok = find_queue_families(best_device, {.GRAPHICS}, args.surface)
	assert(ok, "Failed to find the graphics queue.") or_return

	// Search for the compute queue
	physical_device.compute_queue_family, ok = find_queue_families(best_device, {.COMPUTE}, 0)
	if !ok {
		// No specific compute queue, we will use the graphics queue that must also support compute.
		physical_device.compute_queue_family = physical_device.graphics_queue_family
	}

	// Search for the transfer queue
	physical_device.transfer_queue_family, ok = find_queue_families(best_device, {.TRANSFER}, 0)
	if !ok {
		// No specific transfer queue, we will use the graphics queue that must also support transfer.
		physical_device.transfer_queue_family = physical_device.graphics_queue_family
	}

	return
}


// Check if a physical device queue supports a surface.
@(private = "file")
is_physical_device_support_surface :: proc(physical_device: vk.PhysicalDevice, queue_index: u32, surface: vk.SurfaceKHR) -> bool {
	supported: b32
	result := vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, queue_index, surface, &supported)
	if result != .SUCCESS {
		return false
	}
	return bool(supported)
}

@(private = "file")
find_queue_families :: proc(physical_device: vk.PhysicalDevice, queue_flags: vk.QueueFlags, surface: vk.SurfaceKHR) -> (u32, bool) {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))

	for queue_family, i in queue_families {
		if (queue_flags & queue_family.queueFlags) == queue_flags {
			if surface == 0 || is_physical_device_support_surface(physical_device, u32(i), surface) {
				return u32(i), true
			}
		}
	}
	return 0, false
}

@(private = "file")
get_device_features :: proc(
	device: vk.PhysicalDevice,
) -> (
	vk.PhysicalDeviceVulkan11Features,
	vk.PhysicalDeviceVulkan12Features,
	vk.PhysicalDeviceVulkan13Features,
	vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT,
	vk.PhysicalDeviceFeatures,
) {
	vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}
	extended_dynamic_state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
	}
	vulkan13_features.pNext = &extended_dynamic_state_features

	vulkan12_features := vk.PhysicalDeviceVulkan12Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext = &vulkan13_features,
	}

	vulkan11_features := vk.PhysicalDeviceVulkan11Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = &vulkan12_features,
	}

	features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &vulkan11_features,
	}

	vk.GetPhysicalDeviceFeatures2(device, &features2)
	return vulkan11_features, vulkan12_features, vulkan13_features, extended_dynamic_state_features, features2.features
}

@(private = "file")
score_device :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR, required_extensions: []cstring) -> int {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &props)

	// Require at least Vulkan 1.4.
	if props.apiVersion < vk.API_VERSION_1_4 {
		return -1
	}

	// Must have at least a graphics queue family.
	if _, ok := find_queue_families(device, {.GRAPHICS}, surface); !ok {
		return -1
	}

	// Must support all required device extensions.
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
			return -1
		}
	}

	vulkan11_f, vulkan12_f, vulkan13_f, ext_dynamic_f, base_f := get_device_features(device)

	if !vulkan11_f.shaderDrawParameters {
		return -1
	}
	if !vulkan12_f.timelineSemaphore {
		return -1
	}
	if !vulkan13_f.dynamicRendering {
		return -1
	}
	// Since we now use vk.CmdPipelineBarrier2 and the ImageMemoryBarrier2/DependencyInfo structs in transition_image_layout,
	// we now require the synchronization2 feature from Vulkan1.3
	if !vulkan13_f.synchronization2 {
		return -1
	}
	if !ext_dynamic_f.extendedDynamicState {
		return -1
	}
	if !base_f.samplerAnisotropy {
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

	return score
}


// Search for memory type on a physical device
find_memory_type :: proc(physical_device: ^Physical_Device, type_filter: u32, properties: vk.MemoryPropertyFlags) -> (u32, Error) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device.vk_physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i)) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, nil
		}
	}


	return 0, General_Error{"Failed to find memory type."}
}


// Returns the maximum usable sample for a physical device.
get_max_usable_sample_count :: proc(physical_device: ^Physical_Device) -> vk.SampleCountFlags {
	physical_device_props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device.vk_physical_device, &physical_device_props)

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
find_depth_format :: proc(physical_device: ^Physical_Device) -> (vk.Format, Error) {
	return find_supported_format(physical_device.vk_physical_device, {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
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
