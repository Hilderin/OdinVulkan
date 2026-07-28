package ovk

import "vendor:glfw"
import vk "vendor:vulkan"

// Informations about a swap chain.
Swap_Chain :: struct {
	device:        ^Device,
	vk_swap_chain: vk.SwapchainKHR,
	extent:        vk.Extent2D,
	format:        vk.Format,
	color_space:   vk.ColorSpaceKHR,
	images:        []Image,
}

Create_Swap_Chain_Args :: struct {
	device: ^Device,
	window: ^Window,
}


// Create a swap chain
create_swap_chain :: proc(args: Create_Swap_Chain_Args) -> (swap_chain: Swap_Chain, err: Error) {
	surface_capabilities: vk.SurfaceCapabilitiesKHR
	check(
		vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(args.device.physical_device.vk_physical_device, args.window.surface, &surface_capabilities),
		"Failed to get surface capabilities!",
	) or_return

	swap_chain.device = args.device
	swap_chain.extent = choose_swap_extent(surface_capabilities, args.window.window_handle)
	min_image_count := choose_swap_min_image_count(surface_capabilities)
	available_formats := get_surface_formats(args.device.physical_device.vk_physical_device, args.window.surface)
	defer delete(available_formats)

	swap_chain_format := choose_swap_surface_format(available_formats) or_return
	swap_chain.format = swap_chain_format.format
	swap_chain.color_space = swap_chain_format.colorSpace

	available_present_modes := get_present_modes(args.device.physical_device.vk_physical_device, args.window.surface)
	defer delete(available_present_modes)
	present_mode := choose_present_mode(available_present_modes)

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = args.window.surface,
		minImageCount    = min_image_count,
		imageFormat      = swap_chain.format,
		imageColorSpace  = swap_chain.color_space,
		imageExtent      = swap_chain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE,
		preTransform     = surface_capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
	}

	check(vk.CreateSwapchainKHR(args.device.vk_device, &create_info, nil, &swap_chain.vk_swap_chain), "Failed to create swap chain!") or_return


	// Create swap chain images.
	swap_chain.images = get_swap_chain_images(args.device, swap_chain.vk_swap_chain, swap_chain.extent, swap_chain.format) or_return

	return
}

// Destroy the swap chain
destroy_swap_chain :: proc(swap_chain: ^Swap_Chain) {
	if swap_chain == nil {
		return
	}

	if swap_chain.images != nil {
		// We cannot use the destroy_image because it's a builtin image from the swapchain,
		// but we need to create the image view that we created ourself.
		for &image in swap_chain.images {
			if image.device != nil && image.device.vk_device != nil && image.vk_image_view != 0 {
				vk.DestroyImageView(image.device.vk_device, image.vk_image_view, nil)
			}
		}

		delete(swap_chain.images)
	}

	if swap_chain.device != nil && swap_chain.device.vk_device != nil && swap_chain.vk_swap_chain != 0 {
		vk.DestroySwapchainKHR(swap_chain.device.vk_device, swap_chain.vk_swap_chain, nil)
	}
}

// Acquire the next image for the swap chain and returns it's index.
acquire_next_image :: proc(swap_chain: ^Swap_Chain, draw_fence: ^Fence, acquire_semaphore: ^Semaphore) -> (swapchain_image_index: u32, needs_recreation: bool, err: Error) {

	// Wait until the last frame has finished rendering.
	wait_for_fence(draw_fence)


	// Acquire next image.
	result := vk.AcquireNextImageKHR(swap_chain.device.vk_device, swap_chain.vk_swap_chain, max(u64), acquire_semaphore.vk_semaphore, 0, &swapchain_image_index)

	// Special results from AcquireNextImageKHR:
	// - VK_SUBOPTIMAL_KHR: A swapchain no longer matches the surface properties exactly, but can still be used to present to the surface successfully.
	// - VK_ERROR_OUT_OF_DATE_KHR: (usually when the window is resized) A surface has changed in such a way that it is no longer compatible with the swapchain, and further presentation requests using the swapchain will fail. Applications must query the new surface properties and recreate their swapchain if they wish to continue presenting to the surface.
	if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
		// Swap chain recreation needed
		needs_recreation = true
		return
	} else if result != .SUCCESS {
		err = check(result, "Failed to acquire next image!")
		return
	}

	// We need to manually reset the fence to the unsignaled state because a fence does not automatically reset.
	reset_fence(draw_fence)

	return

}

// Queue the presentation of the swap chain.
queue_present :: proc(swap_chain: ^Swap_Chain, render_finish_semaphore: ^Semaphore, graphics_queue: ^Queue, swapchain_image_index: u32) -> (needs_recreation: bool, err: Error) {
	local_swapchain_image_index := swapchain_image_index

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &swap_chain.vk_swap_chain,
		swapchainCount     = 1,
		pWaitSemaphores    = &render_finish_semaphore.vk_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &local_swapchain_image_index,
	}

	result := vk.QueuePresentKHR(graphics_queue.vk_queue, &present_info)
	if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
		// Swap chain recreation needed
		needs_recreation = true
		return
	} else {
		check(result, "Failed to queue to presentation!") or_return
	}

	return
}

@(private = "file")
choose_swap_extent :: proc(capabilities: vk.SurfaceCapabilitiesKHR, window: glfw.WindowHandle) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window)

	return {
		clamp(u32(width), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
		clamp(u32(height), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
	}
}

@(private = "file")
choose_swap_min_image_count :: proc(capabilities: vk.SurfaceCapabilitiesKHR) -> u32 {
	min_image_count := max(3, capabilities.minImageCount)
	if (0 < capabilities.maxImageCount) && (capabilities.maxImageCount < min_image_count) {
		min_image_count = capabilities.maxImageCount
	}
	return min_image_count
}

@(private = "file")
get_surface_formats :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> []vk.SurfaceFormatKHR {
	surface_format_count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, nil)

	if surface_format_count == 0 {
		return nil
	}

	formats := make([]vk.SurfaceFormatKHR, surface_format_count)
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, raw_data(formats))

	return formats
}

@(private = "file")
choose_swap_surface_format :: proc(available_formats: []vk.SurfaceFormatKHR) -> (surface_format: vk.SurfaceFormatKHR, err: Error) {
	assert(len(available_formats) > 0, "No avaiable formats for the surface.") or_return

	for format in available_formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			surface_format = format
			return
		}
	}
	surface_format = available_formats[0]
	return
}

@(private = "file")
get_present_modes :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> []vk.PresentModeKHR {
	present_mode_count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, nil)

	if present_mode_count == 0 {
		return nil
	}

	present_modes := make([]vk.PresentModeKHR, present_mode_count)
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, raw_data(present_modes))

	return present_modes
}

@(private = "file")
choose_present_mode :: proc(present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	for present_mode in present_modes {
		if present_mode == .MAILBOX {
			return present_mode
		}
	}

	return .FIFO
}

@(private = "file")
get_swap_chain_images :: proc(device: ^Device, swap_chain: vk.SwapchainKHR, extent: vk.Extent2D, format: vk.Format) -> (images: []Image, err: Error) {
	image_count: u32
	vk.GetSwapchainImagesKHR(device.vk_device, swap_chain, &image_count, nil)

	assert(image_count != 0, "No image in the swap chain.") or_return

	images = make([]Image, image_count)
	local_images := make([]vk.Image, image_count)
	defer delete(local_images)

	vk.GetSwapchainImagesKHR(device.vk_device, swap_chain, &image_count, raw_data(local_images))

	image_views := create_image_views(device.vk_device, local_images, format) or_return

	for i in 0 ..< len(images) {
		images[i].device = device
		images[i].vk_image = local_images[i]
		images[i].vk_image_view = image_views[i]
		images[i].width = extent.width
		images[i].height = extent.height
	}

	delete(image_views)

	return
}

@(private = "file")
create_image_views :: proc(device: vk.Device, images: []vk.Image, format: vk.Format) -> (image_views: []vk.ImageView, err: Error) {

	image_views = make([]vk.ImageView, len(images))
	for image, i in images {

		create_info := vk.ImageViewCreateInfo {
			sType            = .IMAGE_VIEW_CREATE_INFO,
			viewType         = .D2,
			format           = format,
			subresourceRange = {{.COLOR}, 0, 1, 0, 1},
			image            = image,
		}

		check(vk.CreateImageView(device, &create_info, nil, &image_views[i]), "Failed to create image view!") or_return
	}

	return
}
