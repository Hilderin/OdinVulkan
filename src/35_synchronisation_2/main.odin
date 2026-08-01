package main

import "core:fmt"
import "core:math"
import la "core:math/linalg"
import "core:os"
import "core:time"

import ovk "../../libs/ovk"
import "vendor:glfw"
import vk "vendor:vulkan"


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
	swap_chain:               ovk.Swap_Chain_Helper,
	shader:                   ovk.Shader,
	descriptor_set_layout:    ovk.Descriptor_Set_Layout,
	descriptor_pool:          ovk.Descriptor_Pool,
	descriptor_sets:          []ovk.Descriptor_Set,
	samples:                  vk.SampleCountFlags,
	depth_format:             vk.Format,
	graphics_pipeline:        ovk.Graphics_Pipeline,
	graphics_command_pool:    ovk.Command_Pool,
	graphics_command_buffers: []ovk.Command_Buffer,
	vertex_buffer:            ovk.Buffer,
	index_buffer:             ovk.Buffer,
	texture:                  ovk.Image,
	sampler:                  ovk.Sampler,
	ubo_buffers:              []ovk.Buffer,
	ubo_mapped_buffers:       []ovk.Mapped_Buffer,
	running:                  bool, // Manage the escape key exit.
}

// Uniform buffer Model View Projection
Uniform_Buffer_Object :: struct {
	model: mat4,
	view:  mat4,
	proj:  mat4,
}

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
	app.window = ovk.create_window({instance = &app.instance, title = "Same with synchronisation 2", width = 512, height = 512, resizable = true}) or_return

	// Pick physical device
	app.physical_device = ovk.get_physical_device({instance = &app.instance, surface = app.window.surface, required_extensions = ovk.required_extensions}) or_return

	// Create logical device
	app.device = ovk.create_logical_device({physical_device = &app.physical_device, required_extensions = ovk.required_extensions}) or_return

	// Samples
	app.samples = ovk.get_max_usable_sample_count(&app.physical_device)

	// Depth format
	app.depth_format = ovk.find_depth_format(&app.physical_device) or_return

	// Create the swap chain helper
	app.swap_chain = ovk.create_swap_chain_helper(
		{swap_chain_args = {device = &app.device, window = &app.window}, samples = app.samples, depth_format = app.depth_format},
	) or_return

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
			pool_sizes = {
				{type = .UNIFORM_BUFFER, descriptorCount = app.swap_chain.nb_frames_in_flight},
				{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = app.swap_chain.nb_frames_in_flight},
			},
			max_sets = app.swap_chain.nb_frames_in_flight,
		},
	) or_return


	// Descriptor sets...
	app.descriptor_sets = ovk.create_descriptor_sets(
		{descriptor_pool = &app.descriptor_pool, descriptor_set_layout = &app.descriptor_set_layout},
		app.swap_chain.nb_frames_in_flight,
	) or_return

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
	app.graphics_command_buffers = ovk.create_command_buffers({command_pool = &app.graphics_command_pool}, app.swap_chain.nb_frames_in_flight) or_return


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
	app.texture = ovk.create_image_from_file("../../assets/models/viking_room/viking_room.png", true, &app.graphics_command_pool, &app.device.graphics_queue) or_return

	// Sampler
	app.sampler = ovk.create_sampler({device = &app.device}) or_return

	// Uniform buffer
	// One buffer per frame so the data can be updated for the next frame while the previous frame is being rendered on the GPU.
	app.ubo_buffers = ovk.create_buffers(
		{device = &app.device, size = u64(size_of(Uniform_Buffer_Object)), usage = {.UNIFORM_BUFFER}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}},
		app.swap_chain.nb_frames_in_flight,
	) or_return
	app.ubo_mapped_buffers = ovk.create_mapped_buffers(app.ubo_buffers) or_return

	// Set uniform buffer in descriptor sets
	for i in 0 ..< app.swap_chain.nb_frames_in_flight {
		ovk.update_descriptor_set(
			&app.descriptor_sets[i],
			{{type = .UNIFORM_BUFFER, binding = 0, buffer = &app.ubo_buffers[i]}, {type = .COMBINED_IMAGE_SAMPLER, binding = 1, image = &app.texture, sampler = &app.sampler}},
		) or_return
	}

	return
}

// Destroy the application.
destroy_app :: proc(app: ^App) {
	ovk.destroy_mapped_buffers(app.ubo_mapped_buffers)
	ovk.destroy_buffers(app.ubo_buffers)
	ovk.destroy_sampler(&app.sampler)
	ovk.destroy_image(&app.texture)
	ovk.destroy_buffer(&app.index_buffer)
	ovk.destroy_buffer(&app.vertex_buffer)
	ovk.destroy_command_buffers(app.graphics_command_buffers)
	ovk.destroy_command_pool(&app.graphics_command_pool)
	ovk.destroy_graphics_pipeline(&app.graphics_pipeline)
	ovk.destroy_descriptor_sets(app.descriptor_sets)
	ovk.destroy_descriptor_pool(&app.descriptor_pool)
	ovk.destroy_descriptor_set_layout(&app.descriptor_set_layout)
	ovk.destroy_shader(&app.shader)
	ovk.destroy_swap_chain_helper(&app.swap_chain)
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
update_uniform_buffer :: proc(start_time: time.Tick, ubo_mapped_buffer: ^ovk.Mapped_Buffer, swap_chain_extent: vk.Extent2D) {
	elapsed_seconds := f32(time.tick_since(start_time)) / f32(time.Second)

	angle := elapsed_seconds * math.to_radians_f32(90)

	width := swap_chain_extent.width
	height := swap_chain_extent.height

	if height == 0 {
		return
	}

	aspect := f32(width) / f32(height)

	ovk.mem_copy_to_mapped_buffer(
		Uniform_Buffer_Object {
			model = la.matrix4_rotate(angle, vec3{0.0, 0.0, 1.0}),
			view  = la.matrix4_look_at(vec3{2.0, 2.0, 2.0}, vec3{0.0, 0.0, 0.0}, vec3{0.0, 0.0, 1.0}),
			// Vulkan's depth range is [0, 1], not OpenGL's [-1, 1]. core:math/linalg's matrix4_perspective
			// produces the OpenGL range and has no equivalent of GLM_FORCE_DEPTH_ZERO_TO_ONE,
			// so we use a custom matrix4_perspective_vulkan proc that bakes the Vulkan Z range and the Y flip in.
			proj  = ovk.matrix4_perspective_vulkan(math.to_radians_f32(45.0), aspect, 0.1, 10.0),
		},
		ubo_mapped_buffer,
	)
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

	start_time := time.tick_now()
	for !ovk.window_should_close(&app.window) && app.running {
		ovk.poll_events()

		// Acquire next image.
		if acquired := ovk.swap_chain_helper_acquire_next_image(&app.swap_chain) or_return; !acquired {
			continue
		}

		// Update uniform buffer with the new rotation
		update_uniform_buffer(start_time, &app.ubo_mapped_buffers[app.swap_chain.frame_index], app.swap_chain.extent)

		// Record command buffer
		record_command_buffer(
			&app.graphics_command_buffers[app.swap_chain.frame_index],
			&app.swap_chain.images[app.swap_chain.image_index],
			app.swap_chain.extent,
			&app.graphics_pipeline,
			&app.vertex_buffer,
			&app.index_buffer,
			u32(app.index_buffer.size / size_of(u32)),
			&app.descriptor_sets[app.swap_chain.frame_index],
			&app.swap_chain.depth_image,
			&app.swap_chain.color_image,
		)

		ovk.swap_chain_helper_submit_and_queue_present(&app.swap_chain, &app.graphics_command_buffers[app.swap_chain.frame_index]) or_return
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
