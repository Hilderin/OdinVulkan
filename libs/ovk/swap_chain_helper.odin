package ovk

import vk "vendor:vulkan"

// Default number of frames in flight
DEFAULT_NB_FRAMES_IN_FLIGHT :: 2

Swap_Chain_Helper :: struct {
	device:              ^Device,
	window:              ^Window,
	swap_chain_args:     Create_Swap_Chain_Args,
	samples:             vk.SampleCountFlags,
	depth_format:        vk.Format,
	acquire_semaphores:  []Semaphore,
	// Frame in flight synchronization.
	// When use_timeline is false, draw_fences are used (one per frame in flight).
	// When use_timeline is true, a single timeline semaphore is used with a monotonic counter.
	use_timeline:        bool,
	draw_fences:         []Fence,
	frame_timeline:      Semaphore,
	frame_counter:       u64,
	nb_frames_in_flight: u32,
	frame_index:         u32, // Frame in flight to render
	image_index:         u32, // Image index in the swap chain to render to	

	// Elements recreated when the swap chain needs recreation
	swap_chain:          Swap_Chain,
	color_image:         Image,
	depth_image:         Image,
	submit_semaphores:   []Semaphore,
	extent:              vk.Extent2D,
	format:              vk.Format,
	color_space:         vk.ColorSpaceKHR,
	images:              []Image,
}


Create_Swap_Chain_Helper_Args :: struct {
	swap_chain_args:     Create_Swap_Chain_Args,
	samples:             vk.SampleCountFlags,
	depth_format:        vk.Format,
	nb_frames_in_flight: u32,
	// Use a timeline semaphore for the frame in flight synchronization instead of fences.
	use_timeline:        bool,
}

// Create the swap chain helper
create_swap_chain_helper :: proc(args: Create_Swap_Chain_Helper_Args) -> (swap_chain_helper: Swap_Chain_Helper, err: Error) {

	swap_chain_helper.device = args.swap_chain_args.device
	swap_chain_helper.window = args.swap_chain_args.window
	swap_chain_helper.swap_chain_args = args.swap_chain_args
	swap_chain_helper.samples = args.samples
	swap_chain_helper.depth_format = args.depth_format
	swap_chain_helper.nb_frames_in_flight = args.nb_frames_in_flight > 0 ? args.nb_frames_in_flight : DEFAULT_NB_FRAMES_IN_FLIGHT
	swap_chain_helper.use_timeline = args.use_timeline

	create_swap_chain_internal(&swap_chain_helper) or_return

	// Semaphore to signal that an image has been acquired from the swapchain and is ready for rendering
	swap_chain_helper.acquire_semaphores = create_semaphores({device = swap_chain_helper.device}, swap_chain_helper.nb_frames_in_flight) or_return

	// Synchronization to make sure only one frame is rendered at a time.
	// A fence is created per frame in flight, a timeline semaphore is created once and reused with a monotonic counter.
	if args.use_timeline {
		swap_chain_helper.frame_timeline = create_semaphore({device = swap_chain_helper.device, semaphore_type = .TIMELINE}) or_return
	} else {
		swap_chain_helper.draw_fences = create_fences({device = swap_chain_helper.device, flags = {.SIGNALED}}, swap_chain_helper.nb_frames_in_flight) or_return
	}

	return
}

// Destroy the swap chain helper
destroy_swap_chain_helper :: proc(swap_chain_helper: ^Swap_Chain_Helper) {

	if swap_chain_helper.use_timeline {
		destroy_semaphore(&swap_chain_helper.frame_timeline)
	} else {
		destroy_fences(swap_chain_helper.draw_fences)
	}
	destroy_semaphores(swap_chain_helper.acquire_semaphores)

	destroy_swap_chain_internal(swap_chain_helper)

}

// Acquire next image.
// Returns true if the image is correctly acquired.
swap_chain_helper_acquire_next_image :: proc(swap_chain_helper: ^Swap_Chain_Helper) -> (acquired: bool, err: Error) {

	recreation_needed: bool

	if swap_chain_helper.use_timeline {
		// Wait until the last frame that used this frame slot has finished rendering.
		// Wait on the value that the previous use of this frame slot was signaled with.
		//   The counter is incremented on every submit, so the previous use of this frame slot
		//   was the (frame_counter - nb_frames_in_flight)th submit.
		// The first nb_frames_in_flight frames have no previous use, so there is nothing to wait on.
		nb_frames := u64(swap_chain_helper.nb_frames_in_flight)
		if swap_chain_helper.frame_counter >= nb_frames {
			wait_value := swap_chain_helper.frame_counter - nb_frames + 1
			wait_for_semaphore(&swap_chain_helper.frame_timeline, wait_value) or_return
		}

		// No fence: the timeline semaphore handles the frame in flight synchronization.
		swap_chain_helper.image_index, recreation_needed = acquire_next_image(
			&swap_chain_helper.swap_chain,
			nil,
			&swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index],
		) or_return
	} else {
		// Wait for the frame fence and reset it after a successful acquire, inside acquire_next_image.
		swap_chain_helper.image_index, recreation_needed = acquire_next_image(
			&swap_chain_helper.swap_chain,
			&swap_chain_helper.draw_fences[swap_chain_helper.frame_index],
			&swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index],
		) or_return
	}

	if recreation_needed {
		swap_chain_helper_recreate_swap_chain(swap_chain_helper) or_return
	} else {
		acquired = true
	}

	return
}

// Submit the command buffer and queue the presentation of the new frame image.
swap_chain_helper_submit_and_queue_present :: proc(swap_chain_helper: ^Swap_Chain_Helper, command_buffer: ^Command_Buffer) -> (err: Error) {

	if swap_chain_helper.use_timeline {
		// Signal the timeline semaphore to the next counter value.
		// It replaces the fence: the host waits on this value before reusing the frame slot.
		swap_chain_helper.frame_counter += 1

		// Submit the command buffer to the graphics queue
		submit_command_buffer(
			{
				command_buffer = command_buffer,
				queue = &swap_chain_helper.device.graphics_queue,
				wait_semaphores = {&swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index]},
				wait_dest_stages = {{.COLOR_ATTACHMENT_OUTPUT}},
				signal_semaphores = {&swap_chain_helper.frame_timeline, &swap_chain_helper.submit_semaphores[swap_chain_helper.image_index]},
				signal_values = {swap_chain_helper.frame_counter, 0},
			},
		) or_return
	} else {
		// Submit the command buffer to the graphics queue
		submit_command_buffer(
			{
				command_buffer = command_buffer,
				queue = &swap_chain_helper.device.graphics_queue,
				fence = &swap_chain_helper.draw_fences[swap_chain_helper.frame_index],
				wait_semaphores = {&swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index]},
				wait_dest_stages = {{.COLOR_ATTACHMENT_OUTPUT}},
				signal_semaphores = {&swap_chain_helper.submit_semaphores[swap_chain_helper.image_index]},
			},
		) or_return
	}

	// Present the image to the user
	recreation_needed := queue_present(
		&swap_chain_helper.swap_chain,
		&swap_chain_helper.submit_semaphores[swap_chain_helper.image_index],
		&swap_chain_helper.device.graphics_queue,
		swap_chain_helper.image_index,
	) or_return


	if recreation_needed {
		swap_chain_helper_recreate_swap_chain(swap_chain_helper) or_return
	}

	// Next frame
	swap_chain_helper.frame_index = (swap_chain_helper.frame_index + 1) % swap_chain_helper.nb_frames_in_flight

	return
}

// Destroy and recreate the swap chain
swap_chain_helper_recreate_swap_chain :: proc(swap_chain_helper: ^Swap_Chain_Helper) -> (err: Error) {

	// Manage minimized window, we will simply pause the process
	width, height := get_window_size(swap_chain_helper.window)
	for width == 0 && height == 0 {
		wait_events()
		width, height = get_window_size(swap_chain_helper.window)
	}

	wait_idle_device(swap_chain_helper.device)

	destroy_swap_chain_internal(swap_chain_helper)
	create_swap_chain_internal(swap_chain_helper) or_return

	return
}

// Create the swap chain in the helper
@(private = "file")
create_swap_chain_internal :: proc(swap_chain_helper: ^Swap_Chain_Helper) -> (err: Error) {

	// Create swap chain
	swap_chain_helper.swap_chain = create_swap_chain({device = swap_chain_helper.device, window = swap_chain_helper.swap_chain_args.window}) or_return

	// Copy some values to make it easier to access them
	swap_chain_helper.extent = swap_chain_helper.swap_chain.extent
	swap_chain_helper.format = swap_chain_helper.swap_chain.format
	swap_chain_helper.color_space = swap_chain_helper.swap_chain.color_space
	swap_chain_helper.images = swap_chain_helper.swap_chain.images

	// Color resources
	swap_chain_helper.color_image = create_image(
		{
			device = swap_chain_helper.device,
			width = swap_chain_helper.swap_chain.extent.width,
			height = swap_chain_helper.swap_chain.extent.height,
			mip_levels = 1,
			samples = swap_chain_helper.samples,
			format = swap_chain_helper.swap_chain.format,
			usage = {.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.COLOR},
		},
	) or_return

	// Depth resources
	swap_chain_helper.depth_image = create_image(
		{
			device = swap_chain_helper.device,
			width = swap_chain_helper.swap_chain.extent.width,
			height = swap_chain_helper.swap_chain.extent.height,
			mip_levels = 1,
			samples = swap_chain_helper.samples,
			format = swap_chain_helper.depth_format,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.DEPTH},
		},
	) or_return

	// Semaphores that are waited on by QueuePresent are buffered based on the number of swapchain images
	// NOTE: I adjusted the code from the official Vulkan Tutorial to follow guidelines for semaphore
	//       which suggest a semaphore per swap chain image.
	//       See: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
	swap_chain_helper.submit_semaphores = create_semaphores({device = swap_chain_helper.device}, u32(len(swap_chain_helper.swap_chain.images))) or_return

	return
}

// Destroy the swap chain in the helper
@(private = "file")
destroy_swap_chain_internal :: proc(swap_chain_helper: ^Swap_Chain_Helper) {

	destroy_image(&swap_chain_helper.depth_image)
	destroy_image(&swap_chain_helper.color_image)
	destroy_swap_chain(&swap_chain_helper.swap_chain)
	destroy_semaphores(swap_chain_helper.submit_semaphores)
}
