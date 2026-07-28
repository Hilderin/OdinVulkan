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
	images:        []vk.Image,
	image_views:   []vk.ImageView,
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

	swap_chain_format := choose_swap_surface_format(available_formats)
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
	swap_chain.images = get_swap_chain_images(args.device.vk_device, swap_chain.vk_swap_chain)

	// Create swap chain image views.
	swap_chain.image_views = create_image_views(args.device.vk_device, swap_chain.images, swap_chain.format) or_return

	return
}

// Destroy the swap chain
destroy_swap_chain :: proc(swap_chain: ^Swap_Chain) {
	if swap_chain == nil {
		return
	}

	if swap_chain.image_views != nil {
		if swap_chain.device != nil && swap_chain.device.vk_device != nil {
			for image_view in swap_chain.image_views {
				vk.DestroyImageView(swap_chain.device.vk_device, image_view, nil)
			}
		}
		delete(swap_chain.image_views)
	}

	if swap_chain.images != nil {
		delete(swap_chain.images)
	}
	if swap_chain.device != nil && swap_chain.device.vk_device != nil && swap_chain.vk_swap_chain != 0 {
		vk.DestroySwapchainKHR(swap_chain.device.vk_device, swap_chain.vk_swap_chain, nil)
	}
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
choose_swap_surface_format :: proc(available_formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	assert(len(available_formats) > 0)

	for format in available_formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}
	return available_formats[0]
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
get_swap_chain_images :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR) -> []vk.Image {
	image_count: u32
	vk.GetSwapchainImagesKHR(device, swap_chain, &image_count, nil)

	if image_count == 0 {
		return nil
	}

	images := make([]vk.Image, image_count)
	vk.GetSwapchainImagesKHR(device, swap_chain, &image_count, raw_data(images))

	return images
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
