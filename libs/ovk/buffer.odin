package ovk

import vk "vendor:vulkan"


Buffer :: struct {
	device:           ^Device,
	vk_buffer:        vk.Buffer,
	vk_device_memory: vk.DeviceMemory,
}


Create_Buffer_Args :: struct {
	device:         ^Device,
	size:           u64,
	usage:          vk.BufferUsageFlags,
	mem_properties: vk.MemoryPropertyFlags,
}


// Create a buffer
create_buffer :: proc(args: Create_Buffer_Args) -> (buffer: Buffer, err: Error) {

	// Buffer creation
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = vk.DeviceSize(args.size),
		usage       = args.usage,
		sharingMode = .EXCLUSIVE,
	}

	check(vk.CreateBuffer(args.device.vk_device, &buffer_info, nil, &buffer.vk_buffer), "Failed to create buffer!") or_return

	// Memory allocation
	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(args.device.vk_device, buffer.vk_buffer, &mem_requirements)

	// Find the memory type based on mem requirements and requested properties.
	memory_type_index := find_memory_type(args.device.physical_device.vk_physical_device, mem_requirements.memoryTypeBits, args.mem_properties) or_return

	// Allocate...
	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	check(vk.AllocateMemory(args.device.vk_device, &alloc_info, nil, &buffer.vk_device_memory), "Failed to allocate memory!") or_return

	// Bind the memory to the buffer
	check(vk.BindBufferMemory(args.device.vk_device, buffer.vk_buffer, buffer.vk_device_memory, 0), "Failed to bind buffer memory!") or_return

	// Complete the struct
	buffer.device = args.device

	return
}

// Destroy an buffer
destroy_buffer :: proc(buffer: ^Buffer) {
	if buffer == nil || buffer.device == nil || buffer.device.vk_device == nil {
		return
	}
	if buffer.vk_device_memory != 0 {
		vk.FreeMemory(buffer.device.vk_device, buffer.vk_device_memory, nil)
	}
	if buffer.vk_buffer != 0 {
		vk.DestroyBuffer(buffer.device.vk_device, buffer.vk_buffer, nil)
	}
}
