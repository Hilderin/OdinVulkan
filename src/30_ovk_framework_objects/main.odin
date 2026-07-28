package main

import "core:bytes"
import "core:fmt"
import img "core:image"
import "core:image/png"
import "core:math"
import la "core:math/linalg"
import "core:mem"
import "core:os"
import "core:path/slashpath"
import "core:reflect"
import "core:time"

import ovk "../../libs/ovk"
import tinyobj "../../libs/tinyobj"
import "vendor:glfw"
import vk "vendor:vulkan"


// Avoids 'unused import' error: "core:image/png" needs to be imported in order
// to make `img.load` understand png format.
_ :: png


// Important aliases for math types
vec2 :: [2]f32
vec3 :: [3]f32
mat4 :: matrix[4, 4]f32


// Contains a reference to the ovk structs
App :: struct {
	instance:              ovk.Instance,
	window:                ovk.Window,
	physical_device:       ovk.Physical_Device,
	device:                ovk.Device,
	swap_chain:            ovk.Swap_Chain,
	shader:                ovk.Shader,
	descriptor_set_layout: ovk.Descriptor_Set_Layout,
	descriptor_pool:       ovk.Descriptor_Pool,
	descriptor_sets:       []ovk.Descriptor_Set,
	samples:               vk.SampleCountFlags,
	color_image:           ovk.Image,
	depth_format:          vk.Format,
	depth_image:           ovk.Image,
	graphics_pipeline:     ovk.Graphics_Pipeline,
}

// Vertex attributes
Vertex :: struct {
	pos:      vec3,
	color:    vec3,
	texCoord: vec2,
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

// Manage the escape key exit.
running: bool = true

// Manage the window resize callback
framebuffer_resized: bool = false

// Check if a result from a Vulkan API call is a success and panic with a detailed error otherwise.
// Temporary: will be removed once all code uses the error-returning `check` instead.
check_panic :: proc(result: vk.Result, operation: string, loc := #caller_location) {
	if result == .SUCCESS {
		return
	}
	p := context.assertion_failure_proc
	when ODIN_DEBUG {
		p(operation, reflect.enum_string(result), loc)
	} else {
		p(operation, "Vulkan operation failed", loc)
	}
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
			vertex_attributes_stride = size_of(Vertex),
			vertex_attributes        = {
				{binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
				{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, color))},
				{binding = 0, location = 2, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, texCoord))},
			},
			depth_format             = app.depth_format,
			samples                  = app.samples,
		},
	) or_return


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


create_command_pool :: proc(device: vk.Device, physical_device: ^ovk.Physical_Device) -> vk.CommandPool {
	command_pool_create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = physical_device.graphics_queue_family,
	}

	command_pool: vk.CommandPool
	check_panic(vk.CreateCommandPool(device, &command_pool_create_info, nil, &command_pool), "Failed to create command pool!")

	return command_pool
}

create_command_buffers :: proc(device: vk.Device, command_pool: vk.CommandPool, command_buffers: []vk.CommandBuffer) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(command_buffers)),
	}

	check_panic(vk.AllocateCommandBuffers(device, &alloc_info, raw_data(command_buffers)), "Failed to create command buffer!")
}

begin_command_buffer :: proc(command_buffer: vk.CommandBuffer, flags: vk.CommandBufferUsageFlags = {}) {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		flags            = flags,
		pInheritanceInfo = nil,
	}

	check_panic(vk.BeginCommandBuffer(command_buffer, &begin_info), "Failed to begin command buffer!")
}

transition_image_layout :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	src_access_mask: vk.AccessFlags2,
	dst_access_mask: vk.AccessFlags2,
	src_stage_mask: vk.PipelineStageFlags2,
	dst_stage_mask: vk.PipelineStageFlags2,
	image_aspect_flags: vk.ImageAspectFlags,
	mip_levels: u32,
) {

	image_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage_mask,
		srcAccessMask = src_access_mask,
		dstStageMask = dst_stage_mask,
		dstAccessMask = dst_access_mask,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = vk.ImageSubresourceRange{aspectMask = image_aspect_flags, baseMipLevel = 0, levelCount = mip_levels, baseArrayLayer = 0, layerCount = 1},
	}

	dependency_info := vk.DependencyInfo {
		sType                    = .DEPENDENCY_INFO,
		dependencyFlags          = {},
		memoryBarrierCount       = 0,
		pMemoryBarriers          = nil,
		bufferMemoryBarrierCount = 0,
		pBufferMemoryBarriers    = nil,
		imageMemoryBarrierCount  = 1,
		pImageMemoryBarriers     = &image_barrier,
	}

	vk.CmdPipelineBarrier2(command_buffer, &dependency_info)
}

begin_rendering :: proc(
	command_buffer: vk.CommandBuffer,
	color_image_view: vk.ImageView,
	resolve_image_view: vk.ImageView,
	swap_chain_extent: vk.Extent2D,
	depth_image_view: vk.ImageView,
) {

	attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = color_image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		// The multisampled color image is resolved (averaged) into the swapchain
		// image view at the end of rendering.
		resolveMode = {.AVERAGE},
		resolveImageView = resolve_image_view,
		resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
	}

	depth_attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = depth_image_view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		clearValue = {depthStencil = {1.0, 0}},
	}

	render_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		renderArea = {extent = swap_chain_extent},
		pColorAttachments = &attachment_info,
		colorAttachmentCount = 1,
		pDepthAttachment = &depth_attachment_info,
	}
	vk.CmdBeginRendering(command_buffer, &render_info)
}

set_viewport :: proc(command_buffer: vk.CommandBuffer, swap_chain_extent: vk.Extent2D) {
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = f32(swap_chain_extent.width),
		height   = f32(swap_chain_extent.height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
}

set_scissor :: proc(command_buffer: vk.CommandBuffer, swap_chain_extent: vk.Extent2D) {
	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {swap_chain_extent.width, swap_chain_extent.height},
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
}


end_rendering :: proc(command_buffer: vk.CommandBuffer) {
	vk.CmdEndRendering(command_buffer)
}


end_command_buffer :: proc(command_buffer: vk.CommandBuffer) {
	check_panic(vk.EndCommandBuffer(command_buffer), "Failed to end command buffer!")
}

record_command_buffer :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	image_view: vk.ImageView,
	swap_chain_extent: vk.Extent2D,
	graphics_pipeline: vk.Pipeline,
	pipeline_layout: vk.PipelineLayout,
	vertex_buffer: vk.Buffer,
	index_buffer: vk.Buffer,
	index_count: u32,
	descriptor_set: vk.DescriptorSet,
	depth_image: vk.Image,
	depth_image_view: vk.ImageView,
	color_image: vk.Image,
	color_image_view: vk.ImageView,
) {

	// Start the recording...
	begin_command_buffer(command_buffer)

	// Transfer the image to ColorAttachmentOptimal
	transition_image_layout(
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
	transition_image_layout(
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
	transition_image_layout(
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
	begin_rendering(command_buffer, color_image_view, image_view, swap_chain_extent, depth_image_view)

	// We can now bind the graphics pipeline
	vk.CmdBindPipeline(command_buffer, .GRAPHICS, graphics_pipeline)

	// Set viewport
	set_viewport(command_buffer, swap_chain_extent)

	// Set scissor
	set_scissor(command_buffer, swap_chain_extent)

	// Bind vertex buffer to binding 0
	offsets := vk.DeviceSize(0)
	local_vertex_buffer := vertex_buffer
	vk.CmdBindVertexBuffers(command_buffer, 0, 1, &local_vertex_buffer, &offsets)

	// Bind index buffer
	vk.CmdBindIndexBuffer(command_buffer, index_buffer, 0, .UINT16)

	// Bind descriptor sets
	local_descriptor_set := descriptor_set
	vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, pipeline_layout, 0, 1, &local_descriptor_set, 0, nil)

	// Draw vertices from vertex buffer
	vk.CmdDrawIndexed(command_buffer, index_count, 1, 0, 0, 0)

	// End the rendering
	end_rendering(command_buffer)

	// After rendering, we need to transition the image layout to PresentSrcKHR so it can be displayed on the screen.
	transition_image_layout(
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
	end_command_buffer(command_buffer)

}

create_semaphore :: proc(device: vk.Device) -> vk.Semaphore {

	semaphore_create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
		flags = {},
	}

	semaphore: vk.Semaphore
	check_panic(vk.CreateSemaphore(device, &semaphore_create_info, nil, &semaphore), "Failed to create a semaphore!")

	return semaphore

}

create_semaphores :: proc(device: vk.Device, semaphores: []vk.Semaphore) {

	for i in 0 ..< len(semaphores) {
		semaphores[i] = create_semaphore(device)
	}

}

create_fence :: proc(device: vk.Device) -> vk.Fence {

	fence_create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	fence: vk.Fence
	check_panic(vk.CreateFence(device, &fence_create_info, nil, &fence), "Failed to create a fence!")

	return fence

}


create_fences :: proc(device: vk.Device, fences: []vk.Fence) {

	for i in 0 ..< len(fences) {
		fences[i] = create_fence(device)
	}

}

wait_for_fence :: proc(device: vk.Device, fence: vk.Fence) {
	local_fence := fence
	check_panic(vk.WaitForFences(device, 1, &local_fence, true, max(u64)), "Failed to wait for fence!")
}

reset_fence :: proc(device: vk.Device, fence: vk.Fence) {
	local_fence := fence
	check_panic(vk.ResetFences(device, 1, &local_fence), "Failed to reset fence!")
}

acquire_next_image :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR, draw_fence: vk.Fence, acquire_semaphore: vk.Semaphore) -> (u32, bool) {

	// Wait until the last frame has finished rendering.
	wait_for_fence(device, draw_fence)


	// Acquire next image.
	swapchain_image_index: u32
	result := vk.AcquireNextImageKHR(device, swap_chain, max(u64), acquire_semaphore, 0, &swapchain_image_index)

	// Special results from AcquireNextImageKHR:
	// - VK_SUBOPTIMAL_KHR: A swapchain no longer matches the surface properties exactly, but can still be used to present to the surface successfully.
	// - VK_ERROR_OUT_OF_DATE_KHR: (usually when the window is resized) A surface has changed in such a way that it is no longer compatible with the swapchain, and further presentation requests using the swapchain will fail. Applications must query the new surface properties and recreate their swapchain if they wish to continue presenting to the surface.
	if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
		// Swap chain recreation needed
		return swapchain_image_index, true
	} else if result != .SUCCESS {
		check_panic(result, "Failed to acquire next image!")
	}

	// We need to manually reset the fence to the unsignaled state because a fence does not automatically reset.
	reset_fence(device, draw_fence)

	return swapchain_image_index, false

}

submit_command_buffer :: proc(
	device: vk.Device,
	command_buffer: vk.CommandBuffer,
	draw_fence: vk.Fence,
	acquire_semaphore: vk.Semaphore,
	render_finish_semaphore: vk.Semaphore,
	graphics_queue: vk.Queue,
) {

	local_acquire_semaphore := acquire_semaphore
	wait_dest_stages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}

	local_command_buffer := command_buffer
	local_render_finish_semaphore := render_finish_semaphore

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &local_acquire_semaphore,
		pWaitDstStageMask    = &wait_dest_stages,
		commandBufferCount   = 1,
		pCommandBuffers      = &local_command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &local_render_finish_semaphore,
	}

	check_panic(vk.QueueSubmit(graphics_queue, 1, &submit_info, draw_fence), "Failed to submit command buffer!")
}

queue_present :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR, render_finish_semaphore: vk.Semaphore, graphics_queue: vk.Queue, swapchain_image_index: u32) -> bool {
	local_swap_chain := swap_chain
	local_render_finish_semaphore := render_finish_semaphore
	local_swapchain_image_index := swapchain_image_index

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		pSwapchains        = &local_swap_chain,
		swapchainCount     = 1,
		pWaitSemaphores    = &local_render_finish_semaphore,
		waitSemaphoreCount = 1,
		pImageIndices      = &local_swapchain_image_index,
	}

	result := vk.QueuePresentKHR(graphics_queue, &present_info)
	if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
		// Swap chain recreation needed
		return true
	} else {
		check_panic(result, "Failed to queue to presentation!")
	}

	return false
}


wait_idle_device :: proc(device: vk.Device) {
	vk.DeviceWaitIdle(device)
}

mem_copy_to_buffer :: proc(device: vk.Device, buffer_memory: vk.DeviceMemory, data: []$T) {

	size := size_of(T) * len(data)
	dest_data: rawptr

	check_panic(vk.MapMemory(device, buffer_memory, 0, vk.DeviceSize(size), {}, &dest_data), "Failed to map memory!")

	mem.copy(dest_data, raw_data(data), size)

	vk.UnmapMemory(device, buffer_memory)

}

transfer_to_buffer :: proc(device: ^ovk.Device, command_pool: vk.CommandPool, queue: vk.Queue, data: []$T, dest_buffer: vk.Buffer) {

	size := u64(size_of(T) * len(data))

	// Staging buffer creation
	staging_buffer, err_stag_buffer := ovk.create_buffer({device = device, size = size, usage = {.TRANSFER_SRC}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}})
	if err_stag_buffer != nil {
		fmt.eprintfln("Failed to create staging_buffer:\n%#v", err_stag_buffer)
		os.exit(1)
	}
	defer ovk.destroy_buffer(&staging_buffer)

	// Copy data to staging buffer...
	mem_copy_to_buffer(device.vk_device, staging_buffer.vk_device_memory, data)

	// Command buffer to copy from staging to buffer
	command_buffer := begin_single_time_commands(device.vk_device, command_pool)

	// Command to copy from staging buffer to destination buffer
	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = vk.DeviceSize(size),
	}
	vk.CmdCopyBuffer(command_buffer, staging_buffer.vk_buffer, dest_buffer, 1, &copy_region)

	// End command buffer
	end_single_time_commands(device.vk_device, command_pool, command_buffer, queue)
}

update_descriptor_set :: proc(device: vk.Device, descriptor_set: vk.DescriptorSet, uniform_buffer: vk.Buffer, image_view: vk.ImageView, sampler: vk.Sampler) {
	buffer_info := vk.DescriptorBufferInfo {
		buffer = uniform_buffer,
		offset = 0,
		range  = size_of(Uniform_Buffer_Object),
	}

	image_info := vk.DescriptorImageInfo {
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = image_view,
		sampler     = sampler,
	}

	ubo_descriptor_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor_set,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		pBufferInfo     = &buffer_info,
	}

	image_sampler_descriptor_write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor_set,
		dstBinding      = 1,
		dstArrayElement = 0,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		pImageInfo      = &image_info,
	}

	descriptor_writes := []vk.WriteDescriptorSet{ubo_descriptor_write, image_sampler_descriptor_write}

	vk.UpdateDescriptorSets(device, u32(len(descriptor_writes)), raw_data(descriptor_writes), 0, nil)
}

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
		proj  = matrix4_perspective_vulkan(math.to_radians_f32(45.0), aspect, 0.1, 10.0),
	}

	// The uniform buffer is typed so we can just assign the new ubo at the rawptr which will copy the ubo value
	mapped_ubo := cast(^Uniform_Buffer_Object)ubo_map_memory_ptr
	mapped_ubo^ = ubo
}


matrix4_perspective_vulkan :: proc(fovy, aspect, near, far: f32) -> (m: mat4) {
	tan_half_fovy := math.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect * tan_half_fovy)
	m[1, 1] = -1 / (tan_half_fovy)
	m[2, 2] = -far / (far - near)
	m[3, 2] = -1
	m[2, 3] = -(far * near) / (far - near)

	return
}

create_texture_image :: proc(device: ^ovk.Device, path: string, command_pool: vk.CommandPool, queue: vk.Queue) -> ovk.Image {

	// Using core image/png to prevent problems with missing stbi on Linux systems.
	src_image, err := img.load(path, {.alpha_add_if_missing})
	if err != nil {
		fmt.eprintfln("Failed to open image file: %q %q.", path, err)
		os.exit(1)
	}

	assert(src_image.channels == 4, "Image should have 4 channels (rgba)")

	fmt.printfln("Image loaded %d x %d, channels: %d", src_image.width, src_image.height, src_image.channels)

	width := u32(src_image.width)
	height := u32(src_image.height)
	size := u64(src_image.width) * u64(src_image.height) * u64(src_image.channels)
	mip_levels := u32(math.floor(math.log2(f32(max(width, height))))) + 1

	// Staging buffer
	staging_buffer, err_stag_buffer := ovk.create_buffer({device = device, size = size, usage = {.TRANSFER_SRC}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}})
	if err_stag_buffer != nil {
		fmt.eprintfln("Failed to create staging buffer: %#v.", err_stag_buffer)
		os.exit(1)
	}
	defer ovk.destroy_buffer(&staging_buffer)

	// Copy image to staging buffer
	mem_copy_to_buffer(device.vk_device, staging_buffer.vk_device_memory, bytes.buffer_to_bytes(&src_image.pixels))

	// No need for the original image anymore
	img.destroy(src_image)

	// Destination image
	image, err_image := ovk.create_image(
		{
			device = device,
			width = width,
			height = height,
			mip_levels = mip_levels,
			samples = {._1},
			format = .R8G8B8A8_SRGB,
			usage = {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
			mem_properties = {.DEVICE_LOCAL},
			aspect_flags = {.COLOR},
		},
	)
	if err_image != nil {
		fmt.eprintfln("Failed to open image file: %q %#v.", path, err_image)
		os.exit(1)
	}

	// We can use the same command buffer to do: transition -> transfer -> transition, the barriers are used to synchronize the commands.
	command_buffer := begin_single_time_commands(device.vk_device, command_pool)

	// Transition the image from undefined to transfer destination
	transition_image_layout(
		command_buffer,
		image.vk_image,
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
	transfer_buffer_to_image(command_buffer, staging_buffer.vk_buffer, image.vk_image, width, height)

	// Generating mipmaps...
	generate_mipmaps(device.physical_device.vk_physical_device, image.vk_image, .R8G8B8A8_SRGB, width, height, mip_levels, command_buffer)

	end_single_time_commands(device.vk_device, command_pool, command_buffer, queue)

	return image
}

generate_mipmaps :: proc(physical_device: vk.PhysicalDevice, image: vk.Image, format: vk.Format, width: u32, height: u32, mip_levels: u32, command_buffer: vk.CommandBuffer) {

	// Check if image format supports linear blitting
	format_props: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(physical_device, format, &format_props)

	if ((format_props.optimalTilingFeatures & {.SAMPLED_IMAGE_FILTER_LINEAR}) != {.SAMPLED_IMAGE_FILTER_LINEAR}) {
		fmt.eprintln("Texture image format does not support linear blitting!")
		os.exit(1)
	}

	barrier := vk.ImageMemoryBarrier {
		sType               = .IMAGE_MEMORY_BARRIER,
		image               = image,
		srcQueueFamilyIndex = 0, //VK_QUEUE_FAMILY_IGNORED
		dstQueueFamilyIndex = 0, //VK_QUEUE_FAMILY_IGNORED
		subresourceRange    = {{.COLOR}, 0, 1, 0, 1},
	}

	mip_width := width
	mip_height := height

	for i in 1 ..< mip_levels {
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)

		blit := vk.ImageBlit {
			srcOffsets     = {{0, 0, 0}, {i32(mip_width), i32(mip_height), 1}},
			srcSubresource = {{.COLOR}, i - 1, 0, 1},
			dstOffsets     = {{0, 0, 0}, {i32(mip_width > 1 ? mip_width / 2 : 1), i32(mip_height > 1 ? mip_height / 2 : 1), 1}},
			dstSubresource = {{.COLOR}, i, 0, 1},
		}


		vk.CmdBlitImage(command_buffer, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

		if mip_width > 1 {
			mip_width /= 2
		}
		if mip_height > 1 {
			mip_height /= 2
		}
	}

	barrier.subresourceRange.baseMipLevel = mip_levels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.FRAGMENT_SHADER}, {}, 0, nil, 0, nil, 1, &barrier)

}

begin_single_time_commands :: proc(device: vk.Device, command_pool: vk.CommandPool) -> vk.CommandBuffer {
	command_buffers: [1]vk.CommandBuffer
	create_command_buffers(device, command_pool, command_buffers[:])
	command_buffer := command_buffers[0]

	begin_command_buffer(command_buffer, {.ONE_TIME_SUBMIT})

	return command_buffer
}


end_single_time_commands :: proc(device: vk.Device, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer, queue: vk.Queue) {

	local_command_buffer := command_buffer

	// End command buffer
	end_command_buffer(command_buffer)

	// Submit and wait
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &local_command_buffer,
	}
	check_panic(vk.QueueSubmit(queue, 1, &submit_info, 0), "Failed to submit command buffer!")
	check_panic(vk.QueueWaitIdle(queue), "Failed to wait on queue completion.")


	vk.FreeCommandBuffers(device, command_pool, 1, &local_command_buffer)
}

transfer_buffer_to_image :: proc(command_buffer: vk.CommandBuffer, src_buffer: vk.Buffer, dest_image: vk.Image, width: u32, height: u32) {
	// Command to copy from staging buffer to destination buffer
	copy_region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		imageOffset = {0, 0, 0},
		imageExtent = {width, height, 1},
	}
	vk.CmdCopyBufferToImage(command_buffer, src_buffer, dest_image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)
}

create_sampler :: proc(physical_device: vk.PhysicalDevice, device: vk.Device) -> vk.Sampler {

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &props)

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		anisotropyEnable        = true,
		maxAnisotropy           = props.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0.0,
		minLod                  = 0.0,
		maxLod                  = vk.LOD_CLAMP_NONE,
	}

	sampler: vk.Sampler
	check_panic(vk.CreateSampler(device, &sampler_info, nil, &sampler), "Failed to create texture sampler!")

	return sampler
}

load_model :: proc(path: string) -> (vertices: []Vertex, indices: []u16) {

	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("Failed to read obj file: %v, error: %v", path, err)
		os.exit(1)
	}
	defer delete(data)

	current_dir := slashpath.dir(path)
	defer delete(current_dir)
	obj := tinyobj.parse_obj(string(data), current_dir, tinyobj.FLAG_TRIANGULATE)
	if !obj.success {
		fmt.eprintln("Failed to read obj file:", path)
		os.exit(1)
	}
	defer tinyobj.destroy(&obj)

	vertices = make([]Vertex, len(obj.attrib.vertices) / 3)
	for f_index in 0 ..< len(vertices) {
		v := Vertex {
			pos   = {obj.attrib.vertices[f_index * 3], obj.attrib.vertices[(f_index * 3) + 1], obj.attrib.vertices[(f_index * 3) + 2]},
			color = {1.0, 1.0, 1.0},
		}
		vertices[f_index] = v
	}

	indices_list: [dynamic]u16
	for &vertex_index in obj.attrib.faces {
		append(&indices_list, u16(vertex_index.v_idx))

		texCoord := vec2{obj.attrib.texcoords[vertex_index.vt_idx * 2], 1.0 - obj.attrib.texcoords[(vertex_index.vt_idx * 2) + 1]}
		vertices[vertex_index.v_idx].texCoord = texCoord
	}

	indices = indices_list[:]
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

	// Command pool
	command_pool := create_command_pool(app.device.vk_device, &app.physical_device)
	fmt.println("Command pool... OK")

	// Command buffer
	command_buffers: [NB_FRAMES_IN_FLIGHT]vk.CommandBuffer
	create_command_buffers(app.device.vk_device, command_pool, command_buffers[:])
	fmt.println("Command buffer... OK")

	// Semaphore to signal that an image has been acquired from the swapchain and is ready for rendering
	acquire_semaphores: [NB_FRAMES_IN_FLIGHT]vk.Semaphore
	create_semaphores(app.device.vk_device, acquire_semaphores[:])
	fmt.println("Acquire complete semaphore... OK")

	// Semaphores that are waited on by QueuePresent are buffered based on the number of swapchain images
	// NOTE: I adjusted the code from the official Vulkan Tutorial to follow guidelines for semaphore
	//       which suggest a semaphore per swap chain image.
	//       See: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
	submit_semaphores := make([]vk.Semaphore, len(app.swap_chain.images))
	defer delete(submit_semaphores)
	create_semaphores(app.device.vk_device, submit_semaphores[:])
	fmt.printfln("Submit finish semaphores (%d)... OK", len(submit_semaphores))

	// Fence to make sure only one frame is rendered at a time
	draw_fences: [NB_FRAMES_IN_FLIGHT]vk.Fence
	create_fences(app.device.vk_device, draw_fences[:])
	fmt.println("Draw fence... OK")

	// Loading model
	vertices, indices := load_model("../../assets/models/viking_room/viking_room.obj")
	fmt.println("Model loaded... OK")

	// Create the vertex buffer on the GPU with a transfer destination flag to allow copy from staging buffer
	vertex_buffer, err_vertex_buffer := ovk.create_buffer(
		{device = &app.device, size = u64(size_of(Vertex) * len(vertices)), usage = {.VERTEX_BUFFER, .TRANSFER_DST}, mem_properties = {.DEVICE_LOCAL}},
	)
	if err_vertex_buffer != nil {
		fmt.eprintfln("Failed to create vertex_buffer:\n%#v", err_vertex_buffer)
		os.exit(1)
	}
	fmt.println("Vertex buffer... OK")

	// Copy vertex data to memory
	transfer_to_buffer(&app.device, command_pool, app.device.graphics_queue.vk_queue, vertices, vertex_buffer.vk_buffer)
	fmt.println("Vertex copied to buffer using staging buffer... OK")

	// Create the index buffer on the GPU with a transfer destination flag to allow copy from staging buffer
	index_buffer, err_index_buffer := ovk.create_buffer(
		{device = &app.device, size = u64(size_of(u16) * len(indices)), usage = {.INDEX_BUFFER, .TRANSFER_DST}, mem_properties = {.DEVICE_LOCAL}},
	)
	if err_index_buffer != nil {
		fmt.eprintfln("Failed to create index_buffer:\n%#v", err_index_buffer)
		os.exit(1)
	}
	fmt.println("Index buffer... OK")

	// Copy index data to memory
	transfer_to_buffer(&app.device, command_pool, app.device.graphics_queue.vk_queue, indices, index_buffer.vk_buffer)
	fmt.println("Indices copied to buffer using staging buffer... OK")

	// Create texture image
	image := create_texture_image(&app.device, "../../assets/models/viking_room/viking_room.png", command_pool, app.device.graphics_queue.vk_queue)
	fmt.println("Texture image loaded... OK")

	// Sampler
	sampler := create_sampler(app.physical_device.vk_physical_device, app.device.vk_device)
	fmt.println("Sampler... OK")

	// Uniform buffer
	// One buffer per frame so the data can be updated for the next frame while the previous frame is being rendered on the GPU.
	ubo_buffers: [NB_FRAMES_IN_FLIGHT]ovk.Buffer
	ubo_map_memory_ptrs: [NB_FRAMES_IN_FLIGHT]rawptr
	for i in 0 ..< NB_FRAMES_IN_FLIGHT {
		size := u64(size_of(Uniform_Buffer_Object))
		err_ubo_buffer: ovk.Error
		ubo_buffers[i], err_ubo_buffer = ovk.create_buffer({device = &app.device, size = size, usage = {.UNIFORM_BUFFER}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}})
		if err_ubo_buffer != nil {
			fmt.eprintfln("Failed to create ubo_buffer:\n%#v", err_ubo_buffer)
			os.exit(1)
		}
		check_panic(vk.MapMemory(app.device.vk_device, ubo_buffers[i].vk_device_memory, 0, vk.DeviceSize(size), {}, &ubo_map_memory_ptrs[i]), "Failed to map memory!")
	}
	fmt.println("Uniform buffer... OK")

	// Set uniform buffer in descriptor sets
	for i in 0 ..< NB_FRAMES_IN_FLIGHT {
		update_descriptor_set(app.device.vk_device, app.descriptor_sets[i].vk_descriptor_set, ubo_buffers[i].vk_buffer, image.vk_image_view, sampler)
	}
	fmt.println("Descriptor sets updated... OK")

	fmt.println()
	fmt.println("Vulkan initialization completed with success!")
	fmt.println("Press Escape to quit.")

	//---------------------
	// Event loop - keep the window open until the user closes it or hits Escape.
	key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
		if key == glfw.KEY_ESCAPE {
			running = false
		}
	}
	glfw.SetKeyCallback(app.window.window_handle, key_callback)

	// Window resize
	framebuffer_resize_callback :: proc "c" (window: glfw.WindowHandle, width: i32, height: i32) {
		framebuffer_resized = true
	}
	glfw.SetFramebufferSizeCallback(app.window.window_handle, framebuffer_resize_callback)

	frame_index: u32 = 0
	start_time := time.tick_now()
	for !glfw.WindowShouldClose(app.window.window_handle) && running {
		glfw.PollEvents()

		// Acquire next image.
		swap_chain_image_index, swap_chain_recreation_needed := acquire_next_image(
			app.device.vk_device,
			app.swap_chain.vk_swap_chain,
			draw_fences[frame_index],
			acquire_semaphores[frame_index],
		)

		if !swap_chain_recreation_needed {

			// Update uniform buffer with the new rotation
			update_uniform_buffer(start_time, ubo_map_memory_ptrs[frame_index], app.swap_chain.extent)

			// Record command buffer
			record_command_buffer(
				command_buffers[frame_index],
				app.swap_chain.images[swap_chain_image_index].vk_image,
				app.swap_chain.images[swap_chain_image_index].vk_image_view,
				app.swap_chain.extent,
				app.graphics_pipeline.vk_pipeline,
				app.graphics_pipeline.vk_pipeline_layout,
				vertex_buffer.vk_buffer,
				index_buffer.vk_buffer,
				u32(len(indices)),
				app.descriptor_sets[frame_index].vk_descriptor_set,
				app.depth_image.vk_image,
				app.depth_image.vk_image_view,
				app.color_image.vk_image,
				app.color_image.vk_image_view,
			)

			// Submit the command buffer to the graphics queue
			submit_command_buffer(
				app.device.vk_device,
				command_buffers[frame_index],
				draw_fences[frame_index],
				acquire_semaphores[frame_index],
				submit_semaphores[swap_chain_image_index],
				app.device.graphics_queue.vk_queue,
			)

			// Present the image to the user
			swap_chain_recreation_needed = queue_present(
				app.device.vk_device,
				app.swap_chain.vk_swap_chain,
				submit_semaphores[swap_chain_image_index],
				app.device.graphics_queue.vk_queue,
				swap_chain_image_index,
			)
		}

		// Swap chain recreation?
		if swap_chain_recreation_needed || framebuffer_resized {
			fmt.println("Swap chain recreation...")

			// Manage minimized window, we will simply pause the process
			width, height := glfw.GetFramebufferSize(app.window.window_handle)
			for width == 0 && height == 0 {
				glfw.WaitEvents()
				width, height = glfw.GetFramebufferSize(app.window.window_handle)
			}

			framebuffer_resized = false
			wait_idle_device(app.device.vk_device)

			destroy_swap_chain(&app)

			if err_swap_chain_creation := create_swap_chain(&app); err_swap_chain_creation != nil {
				fmt.eprintfln("Swap chain recreation failed:\n%#v", err_swap_chain_creation)
				os.exit(1)
			}

			fmt.println("Swap chain recreation... OK")
		}

		// Next frame
		frame_index = (frame_index + 1) % NB_FRAMES_IN_FLIGHT
	}

	// Wait to prevent fence-in-use error.
	wait_idle_device(app.device.vk_device)

	//---------------------

	// Cleanup
	for &ubo_buffer in ubo_buffers {
		ovk.destroy_buffer(&ubo_buffer)
	}

	if sampler != 0 {
		vk.DestroySampler(app.device.vk_device, sampler, nil)
	}
	ovk.destroy_image(&image)
	ovk.destroy_buffer(&index_buffer)
	ovk.destroy_buffer(&vertex_buffer)

	for draw_fence in draw_fences {
		if draw_fence != 0 {
			vk.DestroyFence(app.device.vk_device, draw_fence, nil)
		}
	}
	for acquire_semaphore in acquire_semaphores {
		if acquire_semaphore != 0 {
			vk.DestroySemaphore(app.device.vk_device, acquire_semaphore, nil)
		}
	}
	for submit_semaphore in submit_semaphores {
		if submit_semaphore != 0 {
			vk.DestroySemaphore(app.device.vk_device, submit_semaphore, nil)
		}
	}
	if command_pool != 0 {
		vk.DestroyCommandPool(app.device.vk_device, command_pool, nil)
	}

	destroy_app(&app)
}
