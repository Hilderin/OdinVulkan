package main

import "core:bytes"
import "core:fmt"
import img "core:image"
import "core:image/png"
import "core:math"
import la "core:math/linalg"
import "core:os"
import "core:time"

import ovk "../../libs/ovk"
import "vendor:glfw"
import vk "vendor:vulkan"


// Avoids 'unused import' error: "core:image/png" needs to be imported in order
// to make `img.load` understand png format.
_ :: png


// Important aliases for math types
vec2 :: ovk.vec2
vec3 :: ovk.vec3
vec4 :: ovk.vec4
mat4 :: ovk.mat4


// Contains a reference to the ovk structs
App :: struct {
	instance:                 ovk.Instance,
	window:                   ovk.Window,
	physical_device:          ovk.Physical_Device,
	device:                   ovk.Device,
	swap_chain:               ovk.Swap_Chain,
	shader:                   ovk.Shader,
	descriptor_set_layout:    ovk.Descriptor_Set_Layout,
	descriptor_pool:          ovk.Descriptor_Pool,
	descriptor_sets:          []ovk.Descriptor_Set,
	samples:                  vk.SampleCountFlags,
	color_image:              ovk.Image,
	depth_format:             vk.Format,
	depth_image:              ovk.Image,
	graphics_pipeline:        ovk.Graphics_Pipeline,
	graphics_command_pool:    ovk.Command_Pool,
	graphics_command_buffers: []ovk.Command_Buffer,
	acquire_semaphores:       []ovk.Semaphore,
	submit_semaphores:        []ovk.Semaphore,
	draw_fences:              []ovk.Fence,
	vertex_buffer:            ovk.Buffer,
	index_buffer:             ovk.Buffer,
	texture:                  ovk.Image,
	sampler:                  ovk.Sampler,
	ubo_buffers:              []ovk.Buffer,
	ubo_mapped_buffers:       []ovk.Mapped_Buffer,
	running:                  bool, // Manage the escape key exit.
	framebuffer_resized:      bool, // Manage the window resize callback.
}

// Uniform buffer Model View Projection
Uniform_Buffer_Object :: struct {
	model: mat4,
	view:  mat4,
	proj:  mat4,
}

// Number of frames in flight
NB_FRAMES_IN_FLIGHT :: 2

// Required extensions
required_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}


// Initialize the application.
init_app :: proc(app: ^App) -> (err: ovk.Error) {

	// We need to initialize GLFW so the glfw.GetInstanceProcAddress() method returns a valid callback to load Vulkan function addresses.
	ovk.init_glfw() or_return

	// Create Vulkan instance...
	app.instance = ovk.create_instance(
		{
			application_name = "Odin Vulkan",
			application_version = vk.MAKE_VERSION(1, 0, 0),
			engine_name = "No engine",
			engine_version = vk.MAKE_VERSION(1, 0, 0),
			get_instance_proc_addr = rawptr(glfw.GetInstanceProcAddress),
			extensions = glfw.GetRequiredInstanceExtensions(),
			debug = true,
			debug_level = {.WARNING, .ERROR},
		},
	) or_return

	// Create window
	app.window = ovk.create_window({instance = &app.instance, title = "My little window from the lib", width = 512, height = 512, resizable = true}) or_return

	// Pick physical device
	app.physical_device = ovk.get_physical_device({instance = &app.instance, surface = app.window.surface, required_extensions = required_extensions}) or_return

	// Create logical device
	app.device = ovk.create_logical_device({physical_device = &app.physical_device, required_extensions = required_extensions}) or_return

	// Create the swap chain
	create_swap_chain(app) or_return

	// Create shader module
	app.shader = ovk.create_shader({device = &app.device, slang_path = "shader.slang", entry_points = {"vertMain", "fragMain"}}) or_return

	// Create descriptor set layout
	app.descriptor_set_layout = ovk.create_descriptor_set_layout(
		{
			device = &app.device,
			bindings = {
				{binding = 0, descriptorType = .UNIFORM_BUFFER, descriptorCount = 1, stageFlags = {.VERTEX}},
				{binding = 1, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
			},
		},
	) or_return

	// Descriptor pool
	app.descriptor_pool = ovk.create_descriptor_pool(
		{
			device = &app.device,
			pool_sizes = {{type = .UNIFORM_BUFFER, descriptorCount = NB_FRAMES_IN_FLIGHT}, {type = .COMBINED_IMAGE_SAMPLER, descriptorCount = NB_FRAMES_IN_FLIGHT}},
			max_sets = NB_FRAMES_IN_FLIGHT,
		},
	) or_return


	// Descriptor sets...
	app.descriptor_sets = ovk.create_descriptor_sets({descriptor_pool = &app.descriptor_pool, descriptor_set_layout = &app.descriptor_set_layout}, NB_FRAMES_IN_FLIGHT) or_return

	// Graphics pipeline
	app.graphics_pipeline = ovk.create_graphics_pipeline(
		{
			device                   = &app.device,
			shader                   = &app.shader,
			vertex_entry_point       = "vertMain",
			fragment_entry_point     = "fragMain",
			swap_chain_format        = app.swap_chain.format,
			descriptor_set_layout    = &app.descriptor_set_layout,

			// Configure the data format of vertices
			vertex_attributes_stride = size_of(ovk.Vertex),
			vertex_attributes        = {
				{binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(ovk.Vertex, pos))},
				{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(ovk.Vertex, color))},
				{binding = 0, location = 2, format = .R32G32_SFLOAT, offset = u32(offset_of(ovk.Vertex, texCoord))},
			},
			depth_format             = app.depth_format,
			samples                  = app.samples,
		},
	) or_return

	// Graphics command pool
	app.graphics_command_pool = ovk.create_command_pool(
		{device = &app.device, flags = {.RESET_COMMAND_BUFFER}, queue_family = app.physical_device.graphics_queue_family},
	) or_return


	// Command buffers
	app.graphics_command_buffers = ovk.create_command_buffers({command_pool = &app.graphics_command_pool}, NB_FRAMES_IN_FLIGHT) or_return

	// Semaphore to signal that an image has been acquired from the swapchain and is ready for rendering
	app.acquire_semaphores = ovk.create_semaphores({device = &app.device}, NB_FRAMES_IN_FLIGHT) or_return

	// Semaphores that are waited on by QueuePresent are buffered based on the number of swapchain images
	// NOTE: I adjusted the code from the official Vulkan Tutorial to follow guidelines for semaphore
	//       which suggest a semaphore per swap chain image.
	//       See: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
	app.submit_semaphores = ovk.create_semaphores({device = &app.device}, u32(len(app.swap_chain.images))) or_return

	// Fence to make sure only one frame is rendered at a time
	app.draw_fences = ovk.create_fences({device = &app.device, flags = {.SIGNALED}}, NB_FRAMES_IN_FLIGHT) or_return

	// Loading model
	mesh := ovk.load_mesh("../../assets/models/viking_room/viking_room.obj") or_return
	defer ovk.destroy_mesh(&mesh)

	// Create the vertex buffer on the GPU with a transfer destination flag to allow copy from staging buffer
	app.vertex_buffer = ovk.create_buffer(
		{device = &app.device, size = u64(size_of(ovk.Vertex) * len(mesh.vertices)), usage = {.VERTEX_BUFFER, .TRANSFER_DST}, mem_properties = {.DEVICE_LOCAL}},
	) or_return

	// Copy vertex data to memory
	ovk.transfer_to_buffer(&app.graphics_command_pool, &app.device.graphics_queue, mesh.vertices, &app.vertex_buffer)


	// Create the index buffer on the GPU with a transfer destination flag to allow copy from staging buffer
	app.index_buffer = ovk.create_buffer(
		{device = &app.device, size = u64(size_of(u32) * len(mesh.indices)), usage = {.INDEX_BUFFER, .TRANSFER_DST}, mem_properties = {.DEVICE_LOCAL}},
	) or_return

	// Copy index data to memory
	ovk.transfer_to_buffer(&app.graphics_command_pool, &app.device.graphics_queue, mesh.indices, &app.index_buffer)

	// Create texture image
	app.texture = create_texture_image("../../assets/models/viking_room/viking_room.png", &app.graphics_command_pool, &app.device.graphics_queue) or_return

	// Sampler
	app.sampler = ovk.create_sampler({device = &app.device}) or_return

	// Uniform buffer
	// One buffer per frame so the data can be updated for the next frame while the previous frame is being rendered on the GPU.
	app.ubo_buffers = ovk.create_buffers(
		{device = &app.device, size = u64(size_of(Uniform_Buffer_Object)), usage = {.UNIFORM_BUFFER}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}},
		NB_FRAMES_IN_FLIGHT,
	) or_return
	app.ubo_mapped_buffers = ovk.create_mapped_buffers(app.ubo_buffers) or_return

	// Set uniform buffer in descriptor sets
	for i in 0 ..< NB_FRAMES_IN_FLIGHT {
		ovk.update_descriptor_set(
			&app.descriptor_sets[i],
			{{type = .UNIFORM_BUFFER, binding = 0, buffer = &app.ubo_buffers[i]}, {type = .COMBINED_IMAGE_SAMPLER, binding = 1, image = &app.texture, sampler = &app.sampler}},
		) or_return
	}

	return
}

// Create the swap chain in the app
create_swap_chain :: proc(app: ^App) -> (err: ovk.Error) {

	// Create swap chain
	app.swap_chain = ovk.create_swap_chain({device = &app.device, window = &app.window}) or_return

	// Color resources
	app.samples = ovk.get_max_usable_sample_count(&app.physical_device)
	app.color_image = ovk.create_image(
		{
			device = &app.device,
			width = app.swap_chain.extent.width,
			height = app.swap_chain.extent.height,
			mip_levels = 1,
			samples = app.samples,
			format = app.swap_chain.format,
			usage = {.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.COLOR},
		},
	) or_return

	// Depth resources
	app.depth_format = ovk.find_depth_format(&app.physical_device) or_return
	app.depth_image = ovk.create_image(
		{
			device = &app.device,
			width = app.swap_chain.extent.width,
			height = app.swap_chain.extent.height,
			mip_levels = 1,
			samples = app.samples,
			format = app.depth_format,
			usage = {.DEPTH_STENCIL_ATTACHMENT},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.DEPTH},
		},
	) or_return

	return
}

// Destroy the swap chain and it's dependencies
destroy_swap_chain :: proc(app: ^App) {
	ovk.destroy_image(&app.depth_image)
	ovk.destroy_image(&app.color_image)
	ovk.destroy_swap_chain(&app.swap_chain)
}

// Destroy the application.
destroy_app :: proc(app: ^App) {
	ovk.destroy_mapped_buffers(app.ubo_mapped_buffers)
	ovk.destroy_buffers(app.ubo_buffers)
	ovk.destroy_sampler(&app.sampler)
	ovk.destroy_image(&app.texture)
	ovk.destroy_buffer(&app.index_buffer)
	ovk.destroy_buffer(&app.vertex_buffer)
	ovk.destroy_fences(app.draw_fences)
	ovk.destroy_semaphores(app.submit_semaphores)
	ovk.destroy_semaphores(app.acquire_semaphores)
	ovk.destroy_command_buffers(app.graphics_command_buffers)
	ovk.destroy_command_pool(&app.graphics_command_pool)
	ovk.destroy_graphics_pipeline(&app.graphics_pipeline)
	ovk.destroy_descriptor_sets(app.descriptor_sets)
	ovk.destroy_descriptor_pool(&app.descriptor_pool)
	ovk.destroy_descriptor_set_layout(&app.descriptor_set_layout)
	ovk.destroy_shader(&app.shader)
	destroy_swap_chain(app)
	ovk.destroy_logical_device(&app.device)
	ovk.destroy_window(&app.window)
	ovk.destroy_instance(&app.instance)
	ovk.destroy_glfw()
}

// Record the command buffer for the rendering
record_command_buffer :: proc(
	command_buffer: ^ovk.Command_Buffer,
	image: ^ovk.Image,
	swap_chain_extent: vk.Extent2D,
	graphics_pipeline: ^ovk.Graphics_Pipeline,
	vertex_buffer: ^ovk.Buffer,
	index_buffer: ^ovk.Buffer,
	index_count: u32,
	descriptor_set: ^ovk.Descriptor_Set,
	depth_image: ^ovk.Image,
	color_image: ^ovk.Image,
) {

	// Start the recording...
	ovk.begin_command_buffer(command_buffer)

	// Transfer the image to ColorAttachmentOptimal
	ovk.cmd_transition_image_layout(
		command_buffer,
		image,
		.UNDEFINED, // old_layout
		.COLOR_ATTACHMENT_OPTIMAL, // new_layout
		{}, // src_access_mask
		{.COLOR_ATTACHMENT_WRITE}, // dst_access_mask
		{.COLOR_ATTACHMENT_OUTPUT}, // src_stage
		{.COLOR_ATTACHMENT_OUTPUT}, // dst_stage
		{.COLOR}, //image_aspect_flags
		1,
	)

	// Transfer the depth image to DepthAttachmentOptimal
	ovk.cmd_transition_image_layout(
		command_buffer,
		depth_image,
		.UNDEFINED, // old_layout
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL, // new_layout
		{.DEPTH_STENCIL_ATTACHMENT_WRITE}, // src_access_mask
		{.DEPTH_STENCIL_ATTACHMENT_WRITE}, // dst_access_mask
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, // src_stage
		{.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, // dst_stage
		{.DEPTH}, //image_aspect_flags
		1,
	)

	// Transfer the multisampled color image to ColorAttachmentOptimal
	ovk.cmd_transition_image_layout(
		command_buffer,
		color_image,
		.UNDEFINED, // old_layout
		.COLOR_ATTACHMENT_OPTIMAL, // new_layout
		{.COLOR_ATTACHMENT_WRITE}, // src_access_mask
		{.COLOR_ATTACHMENT_WRITE}, // dst_access_mask
		{.COLOR_ATTACHMENT_OUTPUT}, // src_stage
		{.COLOR_ATTACHMENT_OUTPUT}, // dst_stage
		{.COLOR}, //image_aspect_flags
		1,
	)

	// Start rendering
	ovk.cmd_begin_rendering(command_buffer, color_image, image, swap_chain_extent, depth_image)

	// We can now bind the graphics pipeline
	ovk.cmd_bind_graphics_pipeline(command_buffer, graphics_pipeline)

	// Set viewport
	ovk.cmd_set_viewport(command_buffer, f32(swap_chain_extent.width), f32(swap_chain_extent.height))

	// Set scissor
	ovk.cmd_set_scissor(command_buffer, swap_chain_extent.width, swap_chain_extent.height)

	// Bind vertex buffer to binding 0
	ovk.cmd_bind_vertex_buffer(command_buffer, 0, 1, vertex_buffer, 0)

	// Bind index buffer
	ovk.cmd_bind_index_buffer(command_buffer, index_buffer, 0, .UINT32)

	// Bind descriptor sets
	ovk.cmd_bind_graphics_descriptor_set(command_buffer, graphics_pipeline, descriptor_set)

	// Draw vertices from vertex buffer
	ovk.cmd_draw_indexed(command_buffer, index_count, 1, 0, 0, 0)

	// End the rendering
	ovk.cmd_end_rendering(command_buffer)

	// After rendering, we need to transition the image layout to PresentSrcKHR so it can be displayed on the screen.
	ovk.cmd_transition_image_layout(
		command_buffer,
		image,
		.COLOR_ATTACHMENT_OPTIMAL, //old_layout
		.PRESENT_SRC_KHR, //new_layout
		{.COLOR_ATTACHMENT_WRITE}, // src_access_mask
		{}, // dst_access_mask
		{.COLOR_ATTACHMENT_OUTPUT}, // src_stage
		{.BOTTOM_OF_PIPE}, // dst_stage
		{.COLOR}, //image_aspect_flags
		1,
	)

	// And we're done recording.
	ovk.end_command_buffer(command_buffer)

}

// Update the uniform buffer each frame
update_uniform_buffer :: proc(start_time: time.Tick, ubo_map_memory_ptr: rawptr, swap_chain_extent: vk.Extent2D) {
	elapsed_seconds := f32(time.tick_since(start_time)) / f32(time.Second)

	angle := elapsed_seconds * math.to_radians_f32(90)

	width := swap_chain_extent.width
	height := swap_chain_extent.height

	if height == 0 {
		return
	}

	aspect := f32(width) / f32(height)

	ubo := Uniform_Buffer_Object {
		model = la.matrix4_rotate(angle, vec3{0.0, 0.0, 1.0}),
		view  = la.matrix4_look_at(vec3{2.0, 2.0, 2.0}, vec3{0.0, 0.0, 0.0}, vec3{0.0, 0.0, 1.0}),
		// Vulkan's depth range is [0, 1], not OpenGL's [-1, 1]. core:math/linalg's matrix4_perspective
		// produces the OpenGL range and has no equivalent of GLM_FORCE_DEPTH_ZERO_TO_ONE,
		// so we use a custom matrix4_perspective_vulkan proc that bakes the Vulkan Z range and the Y flip in.
		proj  = ovk.matrix4_perspective_vulkan(math.to_radians_f32(45.0), aspect, 0.1, 10.0),
	}

	// The uniform buffer is typed so we can just assign the new ubo at the rawptr which will copy the ubo value
	mapped_ubo := cast(^Uniform_Buffer_Object)ubo_map_memory_ptr
	mapped_ubo^ = ubo
}

// Create a texture image from an image on the disk.
create_texture_image :: proc(path: string, command_pool: ^ovk.Command_Pool, queue: ^ovk.Queue) -> (image: ovk.Image, err: ovk.Error) {

	// Using core image/png to prevent problems with missing stbi on Linux systems.
	src_image, err_load_image := img.load(path, {.alpha_add_if_missing})
	ovk.assert(err_load_image == nil, "Failed to open image file: %q %q.", path, err_load_image) or_return
	ovk.assert(src_image.channels == 4, "Image should have 4 channels (rgba).") or_return

	width := u32(src_image.width)
	height := u32(src_image.height)
	size := u64(src_image.width) * u64(src_image.height) * u64(src_image.channels)
	mip_levels := u32(math.floor(math.log2(f32(max(width, height))))) + 1

	// Staging buffer
	staging_buffer := ovk.create_buffer({device = command_pool.device, size = size, usage = {.TRANSFER_SRC}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}}) or_return
	defer ovk.destroy_buffer(&staging_buffer)

	// Copy image to staging buffer
	ovk.mem_copy_to_buffer(bytes.buffer_to_bytes(&src_image.pixels), &staging_buffer) or_return

	// No need for the original image anymore
	img.destroy(src_image)

	// Destination image
	image = ovk.create_image(
		{
			device = command_pool.device,
			width = width,
			height = height,
			mip_levels = mip_levels,
			samples = {._1},
			format = .R8G8B8A8_SRGB,
			usage = {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.COLOR},
		},
	) or_return

	// We can use the same command buffer to do: transition -> transfer -> transition, the barriers are used to synchronize the commands.
	command_buffer := ovk.create_one_time_command_buffer(command_pool) or_return

	// Transition the image from undefined to transfer destination
	ovk.cmd_transition_image_layout(
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
	ovk.cmd_copy_buffer_to_image(&command_buffer, &staging_buffer, &image)

	// Generating mipmaps...
	ovk.cmd_generate_mipmaps(&command_buffer, &image, .R8G8B8A8_SRGB, width, height, mip_levels) or_return

	// Submit and wait
	ovk.end_one_time_command_buffer(&command_buffer, queue) or_return

	return
}

// Application loop
run_app :: proc(app: ^App) -> (err: ovk.Error) {

	fmt.println()
	fmt.println("Vulkan initialization completed with success!")
	fmt.println("Press Escape to quit.")

	//---------------------
	app.running = true

	// Event loop - keep the window open until the user closes it or hits Escape.
	key_callback :: proc(window: ^ovk.Window, user_pointer: rawptr, key, scancode, action, mods: i32) {
		if key == glfw.KEY_ESCAPE {
			(cast(^App)user_pointer).running = false
		}
	}
	ovk.set_key_callback(&app.window, rawptr(app), key_callback)

	// Window resize
	framebuffer_resize_callback :: proc(window: ^ovk.Window, user_pointer: rawptr, width: i32, height: i32) {
		(cast(^App)user_pointer).framebuffer_resized = true
	}
	ovk.set_framebuffer_size_callback(&app.window, rawptr(app), framebuffer_resize_callback)

	frame_index: u32 = 0
	start_time := time.tick_now()
	for !ovk.window_should_close(&app.window) && app.running {
		ovk.poll_events()

		// Acquire next image.
		swap_chain_image_index, swap_chain_recreation_needed := ovk.acquire_next_image(
			&app.swap_chain,
			&app.draw_fences[frame_index],
			&app.acquire_semaphores[frame_index],
		) or_return

		if !swap_chain_recreation_needed {

			// Update uniform buffer with the new rotation
			update_uniform_buffer(start_time, app.ubo_mapped_buffers[frame_index].ptr, app.swap_chain.extent)

			// Record command buffer
			record_command_buffer(
				&app.graphics_command_buffers[frame_index],
				&app.swap_chain.images[swap_chain_image_index],
				app.swap_chain.extent,
				&app.graphics_pipeline,
				&app.vertex_buffer,
				&app.index_buffer,
				u32(app.index_buffer.size / size_of(u32)),
				&app.descriptor_sets[frame_index],
				&app.depth_image,
				&app.color_image,
			)

			// Submit the command buffer to the graphics queue
			ovk.submit_command_buffer(
				{
					command_buffer = &app.graphics_command_buffers[frame_index],
					queue = &app.device.graphics_queue,
					fence = &app.draw_fences[frame_index],
					wait_semaphores = {&app.acquire_semaphores[frame_index]},
					wait_dest_stages = {{.COLOR_ATTACHMENT_OUTPUT}},
					signal_semaphores = {&app.submit_semaphores[swap_chain_image_index]},
				},
			) or_return

			// Present the image to the user
			swap_chain_recreation_needed = ovk.queue_present(
				&app.swap_chain,
				&app.submit_semaphores[swap_chain_image_index],
				&app.device.graphics_queue,
				swap_chain_image_index,
			) or_return
		}

		// Swap chain recreation?
		if swap_chain_recreation_needed || app.framebuffer_resized {
			fmt.println("Swap chain recreation...")

			// Manage minimized window, we will simply pause the process
			width, height := ovk.get_window_size(&app.window)
			for width == 0 && height == 0 {
				ovk.wait_events()
				width, height = ovk.get_window_size(&app.window)
			}

			app.framebuffer_resized = false
			ovk.wait_idle_device(&app.device)

			destroy_swap_chain(app)

			create_swap_chain(app) or_return

			fmt.println("Swap chain recreation... OK")
		}

		// Next frame
		frame_index = (frame_index + 1) % NB_FRAMES_IN_FLIGHT
	}

	return
}

main :: proc() {
	fmt.println("Odin Vulkan Tutorial")
	fmt.println("-------------------------------------------")


	// Initialize the application
	app: App
	err := init_app(&app)
	if err != nil {
		fmt.eprintfln("Failed to initialize vulkan:\n%#v", err)
		os.exit(1)
	}

	// Run the application
	err = run_app(&app)
	if err != nil {
		fmt.eprintfln("Error while running the application:\n%#v", err)
		os.exit(1)
	}

	// Wait to prevent fence-in-use error.
	ovk.wait_idle_device(&app.device)

	//---------------------

	destroy_app(&app)
}
