package ovk

import vk "vendor:vulkan"


Queue :: struct {
	vk_queue: vk.Queue,
}

// Get a queue from a device and queue family
get_queue :: proc(device: ^Device, queue_family: u32) -> (queue: Queue) {

	vk.GetDeviceQueue(device.vk_device, queue_family, 0, &queue.vk_queue)

	return
}
