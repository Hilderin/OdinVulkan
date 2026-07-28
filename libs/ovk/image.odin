package ovk

import vk "vendor:vulkan"


Image :: struct {
	device:           ^Device,
	vk_image:         vk.Image,
	vk_device_memory: vk.DeviceMemory,
	vk_image_view:    vk.ImageView,
}


Create_Image_Args :: struct {
	device:         ^Device,
	width:          u32,
	height:         u32,
	mip_levels:     u32,
	samples:        vk.SampleCountFlags,
	format:         vk.Format,
	usage:          vk.ImageUsageFlags,
	mem_properties: vk.MemoryPropertyFlags,
	aspect_flags:   vk.ImageAspectFlags,
}


// Create a image
create_image :: proc(args: Create_Image_Args) -> (image: Image, err: Error) {

	// Image creation
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = args.width, height = args.height, depth = 1},
		mipLevels = args.mip_levels,
		arrayLayers = 1,
		format = args.format,
		tiling = .OPTIMAL,
		initialLayout = .UNDEFINED,
		usage = args.usage,
		sharingMode = .EXCLUSIVE,
		samples = args.samples,
	}

	check(vk.CreateImage(args.device.vk_device, &image_info, nil, &image.vk_image), "Failed to create image!") or_return

	image.device = args.device


	// Memory allocation
	mem_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(args.device.vk_device, image.vk_image, &mem_requirements)

	// Find the memory type based on mem requirements and requested properties.
	memory_type_index := find_memory_type(args.device.physical_device.vk_physical_device, mem_requirements.memoryTypeBits, args.mem_properties) or_return

	// Allocate...
	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	check(vk.AllocateMemory(args.device.vk_device, &alloc_info, nil, &image.vk_device_memory), "Failed to allocate memory!") or_return

	// Bind the memory to the buffer
	check(vk.BindImageMemory(args.device.vk_device, image.vk_image, image.vk_device_memory, 0), "Failed to bind image memory!") or_return

	// Create image view
	image.vk_image_view = create_image_view(args.device.vk_device, image.vk_image, args.format, args.aspect_flags, args.mip_levels) or_return

	return
}

// Destroy an image
destroy_image :: proc(image: ^Image) {
	if image == nil || image.device == nil || image.device.vk_device == nil {
		return
	}

	if image.vk_image_view != 0 {
		vk.DestroyImageView(image.device.vk_device, image.vk_image_view, nil)
	}
	if image.vk_device_memory != 0 {
		vk.FreeMemory(image.device.vk_device, image.vk_device_memory, nil)
	}
	if image.vk_image != 0 {
		vk.DestroyImage(image.device.vk_device, image.vk_image, nil)
	}
}

@(private = "file")
create_image_view :: proc(device: vk.Device, image: vk.Image, format: vk.Format, aspect_flags: vk.ImageAspectFlags, mip_levels: u32) -> (image_view: vk.ImageView, err: Error) {

	create_info := vk.ImageViewCreateInfo {
		sType            = .IMAGE_VIEW_CREATE_INFO,
		viewType         = .D2,
		format           = format,
		subresourceRange = {aspect_flags, 0, mip_levels, 0, 1},
		image            = image,
	}

	check(vk.CreateImageView(device, &create_info, nil, &image_view), "Failed to create image view!") or_return

	return
}
