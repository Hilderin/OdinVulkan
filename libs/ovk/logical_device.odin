package ovk

import vk "vendor:vulkan"

// Information on a logical device.
Device :: struct {
	physical_device: ^Physical_Device,
	vk_device:       vk.Device,
	graphics_queue:  Queue,
	compute_queue:   Queue,
	transfer_queue:  Queue,
}

// Arguments to create a logical device.
Create_Logical_Device_Args :: struct {
	physical_device:     ^Physical_Device,
	required_extensions: []cstring,
}

// Create a logical device.
create_logical_device :: proc(args: Create_Logical_Device_Args) -> (device: Device, err: Error) {
	queue_priority: f32 = 0.5
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = args.physical_device.graphics_queue_family,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	device_feature_extended_dynamic_state := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType                = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		extendedDynamicState = true,
	}

	device_feature_vulkan13 := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		// Since we now use vk.CmdPipelineBarrier2 and the ImageMemoryBarrier2/DependencyInfo structs in transition_image_layout,
		// we now require the synchronization2 feature from Vulkan1.3
		synchronization2 = true,
		pNext            = &device_feature_extended_dynamic_state,
	}

	// Timeline semaphores allow a semaphore to carry a 64 bit counter instead of a boolean state,
	// which lets us wait on a specific value from the host and from other queues.
	device_feature_vulkan12 := vk.PhysicalDeviceVulkan12Features {
		sType              = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		timelineSemaphore  = true,
		pNext              = &device_feature_vulkan13,
	}

	device_feature_vulkan11 := vk.PhysicalDeviceVulkan11Features {
		sType                = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		shaderDrawParameters = true,
		pNext                = &device_feature_vulkan12,
	}

	device_feature_2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &device_feature_vulkan11,
		features = {samplerAnisotropy = true},
	}

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &queue_create_info,
		queueCreateInfoCount    = 1,
		enabledExtensionCount   = u32(len(args.required_extensions)),
		ppEnabledExtensionNames = raw_data(args.required_extensions),
		pNext                   = &device_feature_2,
	}


	// Create the logical device.
	check(vk.CreateDevice(args.physical_device.vk_physical_device, &create_info, nil, &device.vk_device), "Failed to create logical device!") or_return

	// Set the other props on our device.
	device.physical_device = args.physical_device

	// Get all the queue once...
	device.graphics_queue = get_queue(&device, device.physical_device.graphics_queue_family)
	device.compute_queue = get_queue(&device, device.physical_device.compute_queue_family)
	device.transfer_queue = get_queue(&device, device.physical_device.transfer_queue_family)
	return
}

// Destroy the logical device
destroy_logical_device :: proc(device: ^Device) {
	if device != nil && device.vk_device != nil {
		vk.DestroyDevice(device.vk_device, nil)
	}
}

// Wait for the device to be idle.
wait_idle_device :: proc(device: ^Device) {
	vk.DeviceWaitIdle(device.vk_device)
}
