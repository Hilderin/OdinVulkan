package ovk


import vk "vendor:vulkan"

Command_Pool :: struct {
	device:          ^Device,
	vk_command_pool: vk.CommandPool,
	queue_family:    u32,
}

Create_Command_Pool_Args :: struct {
	device:       ^Device,
	queue_family: u32,
	flags:        vk.CommandPoolCreateFlags,
}

// Create a command pool
create_command_pool :: proc(args: Create_Command_Pool_Args) -> (command_pool: Command_Pool, err: Error) {
	command_pool_create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = args.flags,
		queueFamilyIndex = args.queue_family,
	}

	check(vk.CreateCommandPool(args.device.vk_device, &command_pool_create_info, nil, &command_pool.vk_command_pool), "Failed to create command pool!") or_return

	// Complete the struct
	command_pool.device = args.device
	command_pool.queue_family = args.queue_family

	return
}

// Destroy a command pool
destroy_command_pool :: proc(command_pool: ^Command_Pool) {
	if command_pool == nil || command_pool.device == nil || command_pool.device.vk_device == nil {
		return
	}

	if command_pool.vk_command_pool != 0 {
		vk.DestroyCommandPool(command_pool.device.vk_device, command_pool.vk_command_pool, nil)
	}
}
