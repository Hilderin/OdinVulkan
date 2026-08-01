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
	wait_dest_stages:  []vk.PipelineStageFlags2,
	// Values to wait on when using timeline semaphores, 0 for binary semaphores.
	// Must be of same length as wait_semaphores when provided.
	wait_values:       []u64,
	signal_semaphores: []^Semaphore,
	// Values to signal when using timeline semaphores, 0 for binary semaphores.
	// Must be of same length as signal_semaphores when provided.
	signal_values:     []u64,
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

	wait_semaphore_infos := make([]vk.SemaphoreSubmitInfo, len(args.wait_semaphores))
	defer delete(wait_semaphore_infos)

	signal_semaphore_infos := make([]vk.SemaphoreSubmitInfo, len(args.signal_semaphores))
	defer delete(signal_semaphore_infos)

	for wait_semaphore, i in args.wait_semaphores {
		wait_value: u64 = 0
		if i < len(args.wait_values) {
			wait_value = args.wait_values[i]
		}
		wait_semaphore_infos[i] = vk.SemaphoreSubmitInfo {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = wait_semaphore.vk_semaphore,
			value     = wait_value,
			stageMask = args.wait_dest_stages[i],
		}
	}
	for signal_semaphore, i in args.signal_semaphores {
		signal_value: u64 = 0
		if i < len(args.signal_values) {
			signal_value = args.signal_values[i]
		}
		signal_semaphore_infos[i] = vk.SemaphoreSubmitInfo {
			sType     = .SEMAPHORE_SUBMIT_INFO,
			semaphore = signal_semaphore.vk_semaphore,
			value     = signal_value,
			stageMask = {.ALL_COMMANDS},
		}
	}

	command_buffer_info := vk.CommandBufferSubmitInfo {
		sType         = .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer = args.command_buffer.vk_command_buffer,
	}

	submit_info := vk.SubmitInfo2 {
		sType                    = .SUBMIT_INFO_2,
		waitSemaphoreInfoCount   = u32(len(wait_semaphore_infos)),
		pWaitSemaphoreInfos      = raw_data(wait_semaphore_infos),
		commandBufferInfoCount   = 1,
		pCommandBufferInfos      = &command_buffer_info,
		signalSemaphoreInfoCount = u32(len(signal_semaphore_infos)),
		pSignalSemaphoreInfos    = raw_data(signal_semaphore_infos),
	}

	check(vk.QueueSubmit2(args.queue.vk_queue, 1, &submit_info, args.fence != nil ? args.fence.vk_fence : 0), "Failed to submit command buffer!") or_return

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
