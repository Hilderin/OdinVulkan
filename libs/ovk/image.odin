package ovk

import "core:math"

import vk "vendor:vulkan"

Image :: struct {
	device:           ^Device,
	vk_image:         vk.Image,
	vk_device_memory: vk.DeviceMemory,
	vk_image_view:    vk.ImageView,
	width:            u32,
	height:           u32,
	mip_levels:       u32,
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
	image.width = args.width
	image.height = args.height
	image.mip_levels = args.mip_levels


	// Memory allocation
	mem_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(args.device.vk_device, image.vk_image, &mem_requirements)

	// Find the memory type based on mem requirements and requested properties.
	memory_type_index := find_memory_type(args.device.physical_device, mem_requirements.memoryTypeBits, args.mem_properties) or_return

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

// Create a texture image from an image on the disk.
create_image_from_file :: proc(path: string, mipmaps: bool, command_pool: ^Command_Pool, queue: ^Queue) -> (image: Image, err: Error) {

	src_bitmap := load_bitmap_from_file(path, {.alpha_add_if_missing}) or_return
	defer destroy_bitmap(&src_bitmap)

	assert(src_bitmap.channels == 4, "Image should have 4 channels (rgba).") or_return

	size := u64(src_bitmap.width) * u64(src_bitmap.height) * u64(src_bitmap.channels)
	mip_levels := mipmaps ? u32(math.floor(math.log2(f32(max(src_bitmap.width, src_bitmap.height))))) + 1 : 1

	// Staging buffer
	staging_buffer := create_buffer({device = command_pool.device, size = size, usage = {.TRANSFER_SRC}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}}) or_return
	defer destroy_buffer(&staging_buffer)

	// Copy image to staging buffer
	mem_copy_to_buffer(src_bitmap.pixels, &staging_buffer) or_return


	// Destination image
	image = create_image(
		{
			device = command_pool.device,
			width = src_bitmap.width,
			height = src_bitmap.height,
			mip_levels = mip_levels,
			samples = {._1},
			format = .R8G8B8A8_SRGB,
			usage = {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.COLOR},
		},
	) or_return

	// We can use the same command buffer to do: transition -> transfer -> transition, the barriers are used to synchronize the commands.
	command_buffer := create_one_time_command_buffer(command_pool) or_return

	// Transition the image from undefined to transfer destination
	cmd_transition_image_layout(
		&command_buffer,
		&image,
		.UNDEFINED, //old_layout
		.TRANSFER_DST_OPTIMAL, //new_layout
		{}, // src_access_mask
		{.TRANSFER_WRITE}, // dst_access_mask
		{.TOP_OF_PIPE}, // src_stage
		{.TRANSFER}, // dst_stage
		{.COLOR}, //image_aspect_flags
		mip_levels, //mip_levels
	)

	// Copy the buffer to the image
	cmd_copy_buffer_to_image(&command_buffer, &staging_buffer, &image)

	// Generating mipmaps...
	if mipmaps {
		cmd_generate_mipmaps(&command_buffer, &image, .R8G8B8A8_SRGB, src_bitmap.width, src_bitmap.height, mip_levels) or_return
	}

	// Submit and wait
	end_one_time_command_buffer(&command_buffer, queue) or_return

	return
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
