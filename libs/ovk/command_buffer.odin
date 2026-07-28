package ovk

import vk "vendor:vulkan"

Command_Buffer :: struct {
	command_pool:      ^Command_Pool,
	vk_command_buffer: vk.CommandBuffer,
}

Create_Command_Buffer_Args :: struct {
	command_pool: ^Command_Pool,
}

Submit_Command_Buffer_Args :: struct {
	command_buffer:    ^Command_Buffer,
	queue:             ^Queue,
	// fence can be nil when no fence synchronization is needed (e.g. one-time commands)
	fence:             ^Fence,
	wait_semaphores:   []^Semaphore,
	wait_dest_stages:  []vk.PipelineStageFlags,
	signal_semaphores: []^Semaphore,
}

// Create one command buffer
create_command_buffer :: proc(args: Create_Command_Buffer_Args) -> (command_buffer: Command_Buffer, err: Error) {

	command_buffers := create_command_buffers(args, 1) or_return
	command_buffer = command_buffers[0]
	delete(command_buffers)

	return
}

// Create command buffers
create_command_buffers :: proc(args: Create_Command_Buffer_Args, command_buffer_count: u32) -> (command_buffers: []Command_Buffer, err: Error) {

	local_command_buffers := make([]vk.CommandBuffer, command_buffer_count)
	command_buffers = make([]Command_Buffer, command_buffer_count)

	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = args.command_pool.vk_command_pool,
		level              = .PRIMARY,
		commandBufferCount = command_buffer_count,
	}

	check(vk.AllocateCommandBuffers(args.command_pool.device.vk_device, &alloc_info, raw_data(local_command_buffers)), "Failed to create command buffer!") or_return

	// Complete the structs
	for i in 0 ..< command_buffer_count {
		command_buffers[i].command_pool = args.command_pool
		command_buffers[i].vk_command_buffer = local_command_buffers[i]
	}

	return
}

// Destroy a command buffer
destroy_command_buffer :: proc(command_buffer: ^Command_Buffer) {
	if command_buffer == nil || command_buffer.command_pool == nil || command_buffer.command_pool.device == nil {
		return
	}

	vk.FreeCommandBuffers(command_buffer.command_pool.device.vk_device, command_buffer.command_pool.vk_command_pool, 1, &command_buffer.vk_command_buffer)
}

// Destroy command buffers
destroy_command_buffers :: proc(command_buffers: []Command_Buffer) {
	for &command_buffer in command_buffers {
		destroy_command_buffer(&command_buffer)
	}

	delete(command_buffers)
}

// Begin the recording of a command buffer
begin_command_buffer :: proc(command_buffer: ^Command_Buffer, flags: vk.CommandBufferUsageFlags = {}) -> (err: Error) {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		flags            = flags,
		pInheritanceInfo = nil,
	}

	check(vk.BeginCommandBuffer(command_buffer.vk_command_buffer, &begin_info), "Failed to begin command buffer!") or_return

	return
}

// End the recording of a commmand buffer.
end_command_buffer :: proc(command_buffer: ^Command_Buffer) -> (err: Error) {

	check(vk.EndCommandBuffer(command_buffer.vk_command_buffer), "Failed to end command buffer!") or_return

	return
}

// Submit a command buffer.
submit_command_buffer :: proc(args: Submit_Command_Buffer_Args) -> (err: Error) {
	assert(len(args.wait_semaphores) == len(args.wait_dest_stages), "Wait dest stages must be of same length as wait_semaphores") or_return

	vk_wait_semaphores := make([]vk.Semaphore, len(args.wait_semaphores))
	defer delete(vk_wait_semaphores)

	vk_signal_semaphores := make([]vk.Semaphore, len(args.signal_semaphores))
	defer delete(vk_signal_semaphores)

	for &wait_semaphore, i in args.wait_semaphores {
		vk_wait_semaphores[i] = wait_semaphore.vk_semaphore
	}
	for &signal_semaphore, i in args.signal_semaphores {
		vk_signal_semaphores[i] = signal_semaphore.vk_semaphore
	}


	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = u32(len(vk_wait_semaphores)),
		pWaitSemaphores      = raw_data(vk_wait_semaphores),
		pWaitDstStageMask    = raw_data(args.wait_dest_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = &args.command_buffer.vk_command_buffer,
		signalSemaphoreCount = u32(len(vk_signal_semaphores)),
		pSignalSemaphores    = raw_data(vk_signal_semaphores),
	}

	check(vk.QueueSubmit(args.queue.vk_queue, 1, &submit_info, args.fence != nil ? args.fence.vk_fence : 0), "Failed to submit command buffer!") or_return

	return
}

// Wait for the queue to be idle.
queue_wait_idle :: proc(queue: ^Queue) -> (err: Error) {
	check(vk.QueueWaitIdle(queue.vk_queue), "Failed to wait on queue completion.") or_return

	return
}

// Create a one time submit command buffer.
create_one_time_command_buffer :: proc(command_pool: ^Command_Pool) -> (command_buffer: Command_Buffer, err: Error) {

	command_buffer = create_command_buffer({command_pool = command_pool}) or_return

	begin_command_buffer(&command_buffer, {.ONE_TIME_SUBMIT}) or_return

	return
}

// Submits and wait for a command buffer then destroys it.
end_one_time_command_buffer :: proc(command_buffer: ^Command_Buffer, queue: ^Queue) -> (err: Error) {

	// End command buffer
	end_command_buffer(command_buffer)

	// Submit and wait
	submit_command_buffer({command_buffer = command_buffer, queue = queue}) or_return
	queue_wait_idle(queue) or_return

	destroy_command_buffer(command_buffer)

	return
}
