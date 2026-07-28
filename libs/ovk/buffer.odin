package ovk

import "core:mem"

import vk "vendor:vulkan"

_ :: mem

Buffer :: struct {
	device:           ^Device,
	vk_buffer:        vk.Buffer,
	vk_device_memory: vk.DeviceMemory,
	size:             u64,
}

Create_Buffer_Args :: struct {
	device:         ^Device,
	size:           u64,
	usage:          vk.BufferUsageFlags,
	mem_properties: vk.MemoryPropertyFlags,
}

Mapped_Buffer :: struct {
	buffer: ^Buffer,
	ptr:    rawptr,
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
	memory_type_index := find_memory_type(args.device.physical_device, mem_requirements.memoryTypeBits, args.mem_properties) or_return

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
	buffer.size = args.size

	return
}

// Create buffers
create_buffers :: proc(args: Create_Buffer_Args, buffer_count: u32) -> (buffers: []Buffer, err: Error) {
	buffers = make([]Buffer, buffer_count)

	for i in 0 ..< buffer_count {
		buffers[i] = create_buffer(args) or_return
	}

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


// Destroy an buffer
destroy_buffers :: proc(buffers: []Buffer) {
	for &buffer in buffers {
		destroy_buffer(&buffer)
	}
	delete(buffers)
}


// Copy data to a host visible buffer
mem_copy_to_buffer :: proc(data: []$T, dest_buffer: ^Buffer) -> (err: Error) {

	size := size_of(T) * len(data)
	mapped_buffer := create_mapped_buffer(dest_buffer, 0, u64(size)) or_return

	mem.copy(mapped_buffer.ptr, raw_data(data), size)

	destroy_mapped_buffer(&mapped_buffer)

	return
}

// Transfer data to a buffer via a staging buffer.
transfer_to_buffer :: proc(command_pool: ^Command_Pool, queue: ^Queue, data: []$T, dest_buffer: ^Buffer) -> (err: Error) {

	size := u64(size_of(T) * len(data))

	// Staging buffer creation
	staging_buffer := create_buffer({device = command_pool.device, size = size, usage = {.TRANSFER_SRC}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}}) or_return
	defer destroy_buffer(&staging_buffer)

	// Copy data to staging buffer...
	mem_copy_to_buffer(data, &staging_buffer)

	// Command buffer to copy from staging to buffer
	command_buffer := create_one_time_command_buffer(command_pool) or_return

	// Command to copy from staging buffer to destination buffer
	cmd_copy_buffer(&command_buffer, &staging_buffer, 0, dest_buffer, 0, size)

	// End command buffer
	end_one_time_command_buffer(&command_buffer, queue) or_return

	return
}

// Map an host visible buffer to a raw pointer.
create_mapped_buffer :: proc(buffer: ^Buffer, offset: u64 = 0, size: u64 = 0) -> (mapped_buffer: Mapped_Buffer, err: Error) {

	local_size := size > 0 ? size : buffer.size

	check(
		vk.MapMemory(buffer.device.vk_device, buffer.vk_device_memory, vk.DeviceSize(offset), vk.DeviceSize(local_size), {}, &mapped_buffer.ptr),
		"Failed to map memory!",
	) or_return

	mapped_buffer.buffer = buffer

	return
}

// Map an host visible buffer to a raw pointer.
create_mapped_buffers :: proc(buffers: []Buffer, offset: u64 = 0, size: u64 = 0) -> (mapped_buffers: []Mapped_Buffer, err: Error) {

	mapped_buffers = make([]Mapped_Buffer, u32(len(buffers)))

	for &buffer, i in buffers {
		mapped_buffers[i] = create_mapped_buffer(&buffer, offset, size) or_return
	}

	return
}

// Unmap a host visible buffer.
destroy_mapped_buffer :: proc(mapped_buffer: ^Mapped_Buffer) {
	if mapped_buffer == nil || mapped_buffer.buffer == nil || mapped_buffer.buffer.device == nil {
		return
	}

	vk.UnmapMemory(mapped_buffer.buffer.device.vk_device, mapped_buffer.buffer.vk_device_memory)

}

// Unmap an host visible buffer.
destroy_mapped_buffers :: proc(mapped_buffers: []Mapped_Buffer) {
	for &mapped_buffer in mapped_buffers {
		destroy_mapped_buffer(&mapped_buffer)
	}
	delete(mapped_buffers)
}
