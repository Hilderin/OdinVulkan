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
import "core:slice"
import "core:strings"
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
	instance:        ovk.Instance,
	window:          ovk.Window,
	physical_device: ovk.Physical_Device,
	device:          ovk.Device,
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

	return
}

// Destroy the application.
destroy_app :: proc(app: ^App) {
	ovk.destroy_logical_device(&app.device)
	ovk.destroy_window(&app.window)
	ovk.destroy_instance(&app.instance)
	ovk.destroy_glfw()
}


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


choose_swap_min_image_count :: proc(capabilities: vk.SurfaceCapabilitiesKHR) -> u32 {
	min_image_count := max(3, capabilities.minImageCount)
	if (0 < capabilities.maxImageCount) && (capabilities.maxImageCount < min_image_count) {
		min_image_count = capabilities.maxImageCount
	}
	return min_image_count
}


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


choose_swap_surface_format :: proc(available_formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	assert(len(available_formats) > 0)

	for format in available_formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}
	return available_formats[0]
}


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


choose_present_mode :: proc(present_modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	for present_mode in present_modes {
		if present_mode == .MAILBOX {
			return present_mode
		}
	}

	return .FIFO
}


create_swap_chain :: proc(physical_device: vk.PhysicalDevice, device: vk.Device, surface: vk.SurfaceKHR, window: glfw.WindowHandle) -> (vk.SwapchainKHR, vk.Extent2D, vk.Format) {
	surface_capabilities: vk.SurfaceCapabilitiesKHR
	ovk.check_panic(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities), "Failed to get surface capabilities!")

	swap_chain_extent := choose_swap_extent(surface_capabilities, window)
	min_image_count := choose_swap_min_image_count(surface_capabilities)
	available_formats := get_surface_formats(physical_device, surface)
	defer delete(available_formats)
	format := choose_swap_surface_format(available_formats)
	available_present_modes := get_present_modes(physical_device, surface)
	defer delete(available_present_modes)
	present_mode := choose_present_mode(available_present_modes)

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = surface,
		minImageCount    = min_image_count,
		imageFormat      = format.format,
		imageColorSpace  = format.colorSpace,
		imageExtent      = swap_chain_extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageSharingMode = .EXCLUSIVE,
		preTransform     = surface_capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
	}

	swap_chain: vk.SwapchainKHR
	ovk.check_panic(vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain), "Failed to create swap chain!")

	return swap_chain, swap_chain_extent, format.format
}


create_image_view :: proc(device: vk.Device, image: vk.Image, format: vk.Format, aspect_flags: vk.ImageAspectFlags, mip_levels: u32) -> vk.ImageView {

	create_info := vk.ImageViewCreateInfo {
		sType            = .IMAGE_VIEW_CREATE_INFO,
		viewType         = .D2,
		format           = format,
		subresourceRange = {aspect_flags, 0, mip_levels, 0, 1},
		image            = image,
	}

	image_view: vk.ImageView
	ovk.check_panic(vk.CreateImageView(device, &create_info, nil, &image_view), "Failed to create image view!")

	return image_view
}

create_image_views :: proc(device: vk.Device, images: []vk.Image, format: vk.Format) -> []vk.ImageView {

	image_views := make([]vk.ImageView, len(images))
	for image, i in images {
		image_views[i] = create_image_view(device, image, format, {.COLOR}, 1)
	}

	return image_views
}

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

create_shader_module :: proc(device: vk.Device, slang_path: string, entry_points: []string) -> vk.ShaderModule {
	spv, ok := compile_slang_shader(slang_path, entry_points)
	if !ok {
		fmt.eprintln("Shader compilation failed.")
		os.exit(1)
	}
	defer delete(spv)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(spv),
		pCode    = raw_data(slice.reinterpret([]u32, spv)), // Needs to be a pointer to u32
	}

	shader_module: vk.ShaderModule
	ovk.check_panic(vk.CreateShaderModule(device, &create_info, nil, &shader_module), "Failed to create shader module!")

	return shader_module

}

create_graphics_pipeline :: proc(
	device: vk.Device,
	shader_module: vk.ShaderModule,
	vertex_entry_point: string,
	fragment_entry_point: string,
	swap_chain_format: vk.Format,
	descriptor_set_layout: vk.DescriptorSetLayout,
	depth_format: vk.Format,
	samples: vk.SampleCountFlags,
) -> (
	vk.Pipeline,
	vk.PipelineLayout,
) {

	// -----------------------------------
	// Shaders
	// Shader entrypoints
	vertex_entry_cstr := strings.clone_to_cstring(vertex_entry_point)
	defer delete(vertex_entry_cstr)
	fragment_entry_cstr := strings.clone_to_cstring(fragment_entry_point)
	defer delete(fragment_entry_cstr)

	// Shaders create info. One per entrypoint.
	shaders_create_info := []vk.PipelineShaderStageCreateInfo {
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = shader_module, pName = vertex_entry_cstr},
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = shader_module, pName = fragment_entry_cstr},
	}

	// -----------------------------------
	// Dynamic state - Defines what can be dynamic in the pipeline
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// -----------------------------------
	// Vertex input
	// Configure the format of the buffer where the vertices are stored.
	binding_description := vk.VertexInputBindingDescription{}
	binding_description.binding = 0
	binding_description.stride = size_of(Vertex)
	binding_description.inputRate = .VERTEX

	// Configure the data format of vertices
	vertex_attributes_description := []vk.VertexInputAttributeDescription {
		{binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
		{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, color))},
		{binding = 0, location = 2, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, texCoord))},
	}

	vertex_input_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding_description,
		vertexAttributeDescriptionCount = u32(len(vertex_attributes_description)),
		pVertexAttributeDescriptions    = raw_data(vertex_attributes_description),
	}

	// -----------------------------------
	// Input assembly
	// Configure topology and if primitive restart should be enabled.
	input_assembly_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	// No need to specify the pViewports and pScissors because they are dynamic due to the dynamic_states above.
	viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}


	// -----------------------------------
	// Rasterizer
	rasterizer_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = {.BACK},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
		lineWidth               = 1,
	}

	// -----------------------------------
	// Multisampling
	// Disabled for now. We will enable it in a later chapter.
	multisampling_create_info := vk.PipelineMultisampleStateCreateInfo {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable   = false,
		rasterizationSamples  = samples,
		minSampleShading      = 1,
		pSampleMask           = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable      = false,
	}

	// -----------------------------------
	// Depth and stencil testing
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		depthTestEnable       = true,
		depthWriteEnable      = true,
		depthCompareOp        = .LESS,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
	}

	// -----------------------------------
	// Color blending
	// This per-framebuffer struct allows you to configure the first way of color blending. The operations that will be performed are best demonstrated using the following pseudocode:
	//      if (blendEnable) {
	//          finalColor.rgb = (srcColorBlendFactor * newColor.rgb) <colorBlendOp> (dstColorBlendFactor * oldColor.rgb)
	//          finalColor.a = (srcAlphaBlendFactor * newColor.a) <alphaBlendOp> (dstAlphaBlendFactor * oldColor.a)
	//      } else {
	//          finalColor = newColor
	//      }
	//      finalColor = finalColor & colorWriteMask

	// Activating alpha blending where we want the new color to be blended with the old color based on its opacity
	// The finalColor should then be computed as follows:
	//      finalColor.rgb = newAlpha * newColor + (1 - newAlpha) * oldColor;
	//      finalColor.a = newAlpha.a;

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}

	color_blend_create_info := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	// -----------------------------------
	// Pipeline layout
	local_descriptor_set_layout := descriptor_set_layout
	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &local_descriptor_set_layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = nil,
	}

	pipeline_layout: vk.PipelineLayout
	ovk.check_panic(vk.CreatePipelineLayout(device, &pipeline_layout_create_info, nil, &pipeline_layout), "Failed to create pipeline layout!")

	// -----------------------------------
	// Pipeline Rendering Create Info
	// To use dynamic rendering, we need to specify the formats of the attachments that will be used during rendering.
	format := swap_chain_format
	pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &format,
		depthAttachmentFormat   = depth_format,
	}

	// -----------------------------------
	// Graphics Pipeline
	// Finally!! We create the pipeline that will be used to render!
	pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(shaders_create_info),
		pVertexInputState   = &vertex_input_create_info,
		pInputAssemblyState = &input_assembly_create_info,
		pViewportState      = &viewport_state_create_info,
		pRasterizationState = &rasterizer_create_info,
		pMultisampleState   = &multisampling_create_info,
		pColorBlendState    = &color_blend_create_info,
		pDynamicState       = &dynamic_state_create_info,
		layout              = pipeline_layout,
		renderPass          = 0, // must be null for dynamic rendering
		pDepthStencilState  = &depth_stencil,
		pNext               = &pipeline_rendering_create_info,
	}

	graphics_pipeline: vk.Pipeline
	ovk.check_panic(vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_create_info, nil, &graphics_pipeline), "Failed to create graphics pipeline!")

	return graphics_pipeline, pipeline_layout

}

create_command_pool :: proc(device: vk.Device, physical_device: ^ovk.Physical_Device) -> vk.CommandPool {
	command_pool_create_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = physical_device.graphics_queue_family,
	}

	command_pool: vk.CommandPool
	ovk.check_panic(vk.CreateCommandPool(device, &command_pool_create_info, nil, &command_pool), "Failed to create command pool!")

	return command_pool
}

create_command_buffers :: proc(device: vk.Device, command_pool: vk.CommandPool, command_buffers: []vk.CommandBuffer) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(command_buffers)),
	}

	ovk.check_panic(vk.AllocateCommandBuffers(device, &alloc_info, raw_data(command_buffers)), "Failed to create command buffer!")
}

begin_command_buffer :: proc(command_buffer: vk.CommandBuffer, flags: vk.CommandBufferUsageFlags = {}) {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		flags            = flags,
		pInheritanceInfo = nil,
	}

	ovk.check_panic(vk.BeginCommandBuffer(command_buffer, &begin_info), "Failed to begin command buffer!")
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
	ovk.check_panic(vk.EndCommandBuffer(command_buffer), "Failed to end command buffer!")
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
	ovk.check_panic(vk.CreateSemaphore(device, &semaphore_create_info, nil, &semaphore), "Failed to create a semaphore!")

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
	ovk.check_panic(vk.CreateFence(device, &fence_create_info, nil, &fence), "Failed to create a fence!")

	return fence

}


create_fences :: proc(device: vk.Device, fences: []vk.Fence) {

	for i in 0 ..< len(fences) {
		fences[i] = create_fence(device)
	}

}

wait_for_fence :: proc(device: vk.Device, fence: vk.Fence) {
	local_fence := fence
	ovk.check_panic(vk.WaitForFences(device, 1, &local_fence, true, max(u64)), "Failed to wait for fence!")
}

reset_fence :: proc(device: vk.Device, fence: vk.Fence) {
	local_fence := fence
	ovk.check_panic(vk.ResetFences(device, 1, &local_fence), "Failed to reset fence!")
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
		ovk.check_panic(result, "Failed to acquire next image!")
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

	ovk.check_panic(vk.QueueSubmit(graphics_queue, 1, &submit_info, draw_fence), "Failed to submit command buffer!")
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
		ovk.check_panic(result, "Failed to queue to presentation!")
	}

	return false
}


wait_idle_device :: proc(device: vk.Device) {
	vk.DeviceWaitIdle(device)
}

destroy_swap_chain :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR) {
	if swap_chain != 0 {
		vk.DestroySwapchainKHR(device, swap_chain, nil)
	}
}

destroy_swap_chain_images :: proc(device: vk.Device, swap_chain_images: []vk.Image) {
	if swap_chain_images != nil {
		delete(swap_chain_images)
	}
}

destroy_swap_chain_image_views :: proc(device: vk.Device, swap_chain_image_views: []vk.ImageView) {
	if swap_chain_image_views != nil {
		for image_view in swap_chain_image_views {
			vk.DestroyImageView(device, image_view, nil)
		}
		delete(swap_chain_image_views)
	}
}

create_buffer :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	size: u64,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> (
	vk.Buffer,
	vk.DeviceMemory,
) {

	// Buffer creation
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = vk.DeviceSize(size),
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	buffer: vk.Buffer
	ovk.check_panic(vk.CreateBuffer(device, &buffer_info, nil, &buffer), "Failed to create buffer!")

	// Memory allocation
	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &mem_requirements)

	// Find the memory type based on mem requirements and requested properties.
	memory_type_index, ok := find_memory_type(physical_device, mem_requirements.memoryTypeBits, properties)
	if !ok {
		fmt.eprintfln("Failed to find memory type.")
		os.exit(1)
	}

	// Allocate...
	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	buffer_memory: vk.DeviceMemory
	ovk.check_panic(vk.AllocateMemory(device, &alloc_info, nil, &buffer_memory), "Failed to allocate memory!")

	// Bind the memory to the buffer
	ovk.check_panic(vk.BindBufferMemory(device, buffer, buffer_memory, 0), "Failed to bind buffer memory!")

	return buffer, buffer_memory

}

find_memory_type :: proc(physical_device: vk.PhysicalDevice, type_filter: u32, properties: vk.MemoryPropertyFlags) -> (u32, bool) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i)) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, true
		}
	}


	return 0, false
}

mem_copy_to_buffer :: proc(device: vk.Device, buffer_memory: vk.DeviceMemory, data: []$T) {

	size := size_of(T) * len(data)
	dest_data: rawptr

	ovk.check_panic(vk.MapMemory(device, buffer_memory, 0, vk.DeviceSize(size), {}, &dest_data), "Failed to map memory!")

	mem.copy(dest_data, raw_data(data), size)

	vk.UnmapMemory(device, buffer_memory)

}

transfer_to_buffer :: proc(physical_device: vk.PhysicalDevice, device: vk.Device, command_pool: vk.CommandPool, queue: vk.Queue, data: []$T, dest_buffer: vk.Buffer) {

	size := u64(size_of(T) * len(data))

	// Staging buffer creation
	staging_buffer, staging_buffer_memory := create_buffer(physical_device, device, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	defer vk.DestroyBuffer(device, staging_buffer, nil)
	defer vk.FreeMemory(device, staging_buffer_memory, nil)

	// Copy data to staging buffer...
	mem_copy_to_buffer(device, staging_buffer_memory, data)

	// Command buffer to copy from staging to buffer
	command_buffer := begin_single_time_commands(device, command_pool)

	// Command to copy from staging buffer to destination buffer
	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = vk.DeviceSize(size),
	}
	vk.CmdCopyBuffer(command_buffer, staging_buffer, dest_buffer, 1, &copy_region)

	// End command buffer
	end_single_time_commands(device, command_pool, command_buffer, queue)
}

create_descriptor_set_layout :: proc(device: vk.Device) -> vk.DescriptorSetLayout {
	ubo_binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = {.VERTEX},
	}

	sampler_binding := vk.DescriptorSetLayoutBinding {
		binding         = 1,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		descriptorCount = 1,
		stageFlags      = {.FRAGMENT},
	}

	layout_bindings := []vk.DescriptorSetLayoutBinding{ubo_binding, sampler_binding}

	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(layout_bindings)),
		pBindings    = raw_data(layout_bindings),
	}

	descriptor_set_layout: vk.DescriptorSetLayout
	ovk.check_panic(vk.CreateDescriptorSetLayout(device, &layout_info, nil, &descriptor_set_layout), "Failed to create descriptor set layout!")

	return descriptor_set_layout
}

create_descriptor_pool :: proc(device: vk.Device, pool_sizes: []vk.DescriptorPoolSize, max_sets: u32) -> vk.DescriptorPool {
	local_pool_sizes := pool_sizes

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(local_pool_sizes)),
		pPoolSizes    = raw_data(local_pool_sizes),
		maxSets       = max_sets,
	}

	descriptor_pool: vk.DescriptorPool
	ovk.check_panic(vk.CreateDescriptorPool(device, &pool_info, nil, &descriptor_pool), "Failed to create descriptor pool!")

	return descriptor_pool
}

create_descriptor_set :: proc(device: vk.Device, descriptor_pool: vk.DescriptorPool, descriptor_layout: vk.DescriptorSetLayout, descriptor_count: u32) -> []vk.DescriptorSet {
	descriptor_layouts := make([]vk.DescriptorSetLayout, descriptor_count)
	defer delete(descriptor_layouts)

	// Same descriptor layout for each
	for i in 0 ..< descriptor_count {
		descriptor_layouts[i] = descriptor_layout
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = descriptor_pool,
		descriptorSetCount = descriptor_count,
		pSetLayouts        = raw_data(descriptor_layouts),
	}

	descriptor_sets := make([]vk.DescriptorSet, descriptor_count)

	ovk.check_panic(vk.AllocateDescriptorSets(device, &alloc_info, raw_data(descriptor_sets)), "Failed to allocate descriptor sets!")
	return descriptor_sets
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

create_image :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	width: u32,
	height: u32,
	mip_levels: u32,
	samples: vk.SampleCountFlags,
	format: vk.Format,
	usage: vk.ImageUsageFlags,
	properties: vk.MemoryPropertyFlags,
) -> (
	vk.Image,
	vk.DeviceMemory,
) {

	// Image creation
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = {width = width, height = height, depth = 1},
		mipLevels = mip_levels,
		arrayLayers = 1,
		format = format,
		tiling = .OPTIMAL,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = samples,
	}

	image: vk.Image
	ovk.check_panic(vk.CreateImage(device, &image_info, nil, &image), "Failed to create image!")


	// Memory allocation
	mem_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(device, image, &mem_requirements)

	// Find the memory type based on mem requirements and requested properties.
	memory_type_index, ok := find_memory_type(physical_device, mem_requirements.memoryTypeBits, properties)
	if !ok {
		fmt.eprintfln("Failed to find memory type.")
		os.exit(1)
	}

	// Allocate...
	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	image_memory: vk.DeviceMemory
	ovk.check_panic(vk.AllocateMemory(device, &alloc_info, nil, &image_memory), "Failed to allocate memory!")

	// Bind the memory to the buffer
	ovk.check_panic(vk.BindImageMemory(device, image, image_memory, 0), "Failed to bind image memory!")

	return image, image_memory
}

create_texture_image :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	path: string,
	command_pool: vk.CommandPool,
	queue: vk.Queue,
) -> (
	vk.Image,
	vk.DeviceMemory,
	u32,
) {

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
	staging_buffer, staging_buffer_memory := create_buffer(physical_device, device, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	defer vk.DestroyBuffer(device, staging_buffer, nil)
	defer vk.FreeMemory(device, staging_buffer_memory, nil)

	// Copy image to staging buffer
	mem_copy_to_buffer(device, staging_buffer_memory, bytes.buffer_to_bytes(&src_image.pixels))

	// No need for the original image anymore
	img.destroy(src_image)

	// Destination image
	image, image_memory := create_image(physical_device, device, width, height, mip_levels, {._1}, .R8G8B8A8_SRGB, {.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL})


	// We can use the same command buffer to do: transition -> transfer -> transition, the barriers are used to synchronize the commands.
	command_buffer := begin_single_time_commands(device, command_pool)

	// Transition the image from undefined to transfer destination
	transition_image_layout(
		command_buffer,
		image,
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
	transfer_buffer_to_image(command_buffer, staging_buffer, image, width, height)

	// Generating mipmaps...
	generate_mipmaps(physical_device, image, .R8G8B8A8_SRGB, width, height, mip_levels, command_buffer)

	end_single_time_commands(device, command_pool, command_buffer, queue)

	return image, image_memory, mip_levels
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
	ovk.check_panic(vk.QueueSubmit(queue, 1, &submit_info, 0), "Failed to submit command buffer!")
	ovk.check_panic(vk.QueueWaitIdle(queue), "Failed to wait on queue completion.")


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
	ovk.check_panic(vk.CreateSampler(device, &sampler_info, nil, &sampler), "Failed to create texture sampler!")

	return sampler
}

find_supported_format :: proc(physical_device: vk.PhysicalDevice, candidates: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> vk.Format {
	for format in candidates {
		props: vk.FormatProperties
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &props)

		if tiling == .LINEAR && (props.linearTilingFeatures & features) == features {
			return format
		}

		if tiling == .OPTIMAL && (props.optimalTilingFeatures & features) == features {
			return format
		}
	}

	fmt.eprintln("Impossible to find format in candidates: %q", candidates)
	os.exit(1)
}

find_depth_format :: proc(physical_device: vk.PhysicalDevice) -> vk.Format {
	return find_supported_format(physical_device, {.D32_SFLOAT, .D32_SFLOAT_S8_UINT, .D24_UNORM_S8_UINT}, .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
}

has_stencil_component :: proc(format: vk.Format) -> bool {
	return format == .D32_SFLOAT_S8_UINT || format == .D24_UNORM_S8_UINT
}

create_depth_resources :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	depth_format: vk.Format,
	swap_chain_extent: vk.Extent2D,
	samples: vk.SampleCountFlags,
) -> (
	vk.Image,
	vk.DeviceMemory,
	vk.ImageView,
) {

	depth_image, depth_image_memory := create_image(
		physical_device,
		device,
		swap_chain_extent.width,
		swap_chain_extent.height,
		1,
		samples,
		depth_format,
		{.DEPTH_STENCIL_ATTACHMENT},
		{.DEVICE_LOCAL},
	)
	depth_image_view := create_image_view(device, depth_image, depth_format, {.DEPTH}, 1)

	return depth_image, depth_image_memory, depth_image_view
}

destroy_depth_resources :: proc(device: vk.Device, depth_image: vk.Image, depth_image_memory: vk.DeviceMemory, depth_image_view: vk.ImageView) {
	vk.DestroyImageView(device, depth_image_view, nil)
	vk.FreeMemory(device, depth_image_memory, nil)
	vk.DestroyImage(device, depth_image, nil)
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

get_max_usable_sample_count :: proc(physical_device: vk.PhysicalDevice) -> vk.SampleCountFlags {
	physical_device_props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &physical_device_props)

	counts := physical_device_props.limits.framebufferColorSampleCounts & physical_device_props.limits.framebufferDepthSampleCounts
	if (counts & {._64}) == {._64} {return {._64}}
	if (counts & {._32}) == {._32} {return {._32}}
	if (counts & {._16}) == {._16} {return {._16}}
	if (counts & {._8}) == {._8} {return {._8}}
	if (counts & {._4}) == {._4} {return {._4}}
	if (counts & {._2}) == {._2} {return {._2}}

	return {._1}
}


create_color_resources :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	color_format: vk.Format,
	swap_chain_extent: vk.Extent2D,
	samples: vk.SampleCountFlags,
) -> (
	vk.Image,
	vk.DeviceMemory,
	vk.ImageView,
) {

	color_image, color_image_memory := create_image(
		physical_device,
		device,
		swap_chain_extent.width,
		swap_chain_extent.height,
		1,
		samples,
		color_format,
		{.TRANSIENT_ATTACHMENT, .COLOR_ATTACHMENT},
		{.DEVICE_LOCAL},
	)
	color_image_view := create_image_view(device, color_image, color_format, {.COLOR}, 1)

	return color_image, color_image_memory, color_image_view
}


destroy_color_resources :: proc(device: vk.Device, color_image: vk.Image, color_image_memory: vk.DeviceMemory, color_image_view: vk.ImageView) {
	vk.DestroyImageView(device, color_image_view, nil)
	vk.FreeMemory(device, color_image_memory, nil)
	vk.DestroyImage(device, color_image, nil)
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

	// Create swap chain
	swap_chain, swap_chain_extent, swap_chain_format := create_swap_chain(
		app.physical_device.vk_physical_device,
		app.device.vk_device,
		app.window.surface,
		app.window.window_handle,
	)
	fmt.println("Swap chain... OK")

	// Get swap chain images
	swap_chain_images := get_swap_chain_images(app.device.vk_device, swap_chain)
	fmt.printfln("Swap chain images [%d]... OK", len(swap_chain_images))

	// Create image views
	swap_chain_image_views := create_image_views(app.device.vk_device, swap_chain_images, swap_chain_format)
	fmt.println("Swap chain images views... OK")

	// Color resources
	samples := get_max_usable_sample_count(app.physical_device.vk_physical_device)
	color_image, color_image_memory, color_image_view := create_color_resources(
		app.physical_device.vk_physical_device,
		app.device.vk_device,
		swap_chain_format,
		swap_chain_extent,
		samples,
	)
	fmt.println("Color resource... OK")

	// Depth resources
	depth_format := find_depth_format(app.physical_device.vk_physical_device)
	depth_image, depth_image_memory, depth_image_view := create_depth_resources(
		app.physical_device.vk_physical_device,
		app.device.vk_device,
		depth_format,
		swap_chain_extent,
		samples,
	)
	fmt.println("Depth resource... OK")

	// Create shader module
	shader_module := create_shader_module(app.device.vk_device, "shader.slang", {"vertMain", "fragMain"})
	fmt.println("Shader module... OK")

	// Descriptor set layout
	ubo_descriptor_set_layout := create_descriptor_set_layout(app.device.vk_device)
	fmt.println("UBO descriptor set layout... OK")

	// Descriptor pool
	descriptor_pool := create_descriptor_pool(
		app.device.vk_device,
		{{type = .UNIFORM_BUFFER, descriptorCount = NB_FRAMES_IN_FLIGHT}, {type = .COMBINED_IMAGE_SAMPLER, descriptorCount = NB_FRAMES_IN_FLIGHT}},
		NB_FRAMES_IN_FLIGHT,
	)
	fmt.println("Descriptor pool... OK")

	// Descriptor sets...
	descriptor_sets := create_descriptor_set(app.device.vk_device, descriptor_pool, ubo_descriptor_set_layout, NB_FRAMES_IN_FLIGHT)
	fmt.println("Descriptor sets... OK")

	// Create graphics pipeline
	graphics_pipeline, pipeline_layout := create_graphics_pipeline(
		app.device.vk_device,
		shader_module,
		"vertMain",
		"fragMain",
		swap_chain_format,
		ubo_descriptor_set_layout,
		depth_format,
		samples,
	)
	fmt.println("Graphics pipeline... OK")

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
	submit_semaphores := make([]vk.Semaphore, len(swap_chain_images))
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
	vertex_buffer, vertex_buffer_memory := create_buffer(
		app.physical_device.vk_physical_device,
		app.device.vk_device,
		u64(size_of(Vertex) * len(vertices)),
		{.VERTEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)
	fmt.println("Vertex buffer... OK")

	// Copy vertex data to memory
	transfer_to_buffer(app.physical_device.vk_physical_device, app.device.vk_device, command_pool, app.device.graphics_queue, vertices, vertex_buffer)
	fmt.println("Vertex copied to buffer using staging buffer... OK")

	// Create the index buffer on the GPU with a transfer destination flag to allow copy from staging buffer
	index_buffer, index_buffer_memory := create_buffer(
		app.physical_device.vk_physical_device,
		app.device.vk_device,
		u64(size_of(u16) * len(indices)),
		{.INDEX_BUFFER, .TRANSFER_DST},
		{.DEVICE_LOCAL},
	)
	fmt.println("Index buffer... OK")

	// Copy index data to memory
	transfer_to_buffer(app.physical_device.vk_physical_device, app.device.vk_device, command_pool, app.device.graphics_queue, indices, index_buffer)
	fmt.println("Indices copied to buffer using staging buffer... OK")

	// Create texture image
	image, image_memory, texture_mip_levels := create_texture_image(
		app.physical_device.vk_physical_device,
		app.device.vk_device,
		"../../assets/models/viking_room/viking_room.png",
		command_pool,
		app.device.graphics_queue,
	)
	fmt.println("Texture image loaded... OK")

	// Image view
	image_view := create_image_view(app.device.vk_device, image, .R8G8B8A8_SRGB, {.COLOR}, texture_mip_levels)
	fmt.println("Texture image view... OK")

	// Sampler
	sampler := create_sampler(app.physical_device.vk_physical_device, app.device.vk_device)
	fmt.println("Sampler... OK")

	// Uniform buffer
	// One buffer per frame so the data can be updated for the next frame while the previous frame is being rendered on the GPU.
	ubo_buffers: [NB_FRAMES_IN_FLIGHT]vk.Buffer
	ubo_buffer_memories: [NB_FRAMES_IN_FLIGHT]vk.DeviceMemory
	ubo_map_memory_ptrs: [NB_FRAMES_IN_FLIGHT]rawptr
	for i in 0 ..< NB_FRAMES_IN_FLIGHT {
		size := u64(size_of(Uniform_Buffer_Object))
		ubo_buffers[i], ubo_buffer_memories[i] = create_buffer(
			app.physical_device.vk_physical_device,
			app.device.vk_device,
			size,
			{.UNIFORM_BUFFER},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		ovk.check_panic(vk.MapMemory(app.device.vk_device, ubo_buffer_memories[i], 0, vk.DeviceSize(size), {}, &ubo_map_memory_ptrs[i]), "Failed to map memory!")
	}
	fmt.println("Uniform buffer... OK")

	// Set uniform buffer in descriptor sets
	for i in 0 ..< NB_FRAMES_IN_FLIGHT {
		update_descriptor_set(app.device.vk_device, descriptor_sets[i], ubo_buffers[i], image_view, sampler)
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
		swap_chain_image_index, swap_chain_recreation_needed := acquire_next_image(app.device.vk_device, swap_chain, draw_fences[frame_index], acquire_semaphores[frame_index])

		if !swap_chain_recreation_needed {

			// Update uniform buffer with the new rotation
			update_uniform_buffer(start_time, ubo_map_memory_ptrs[frame_index], swap_chain_extent)

			// Record command buffer
			record_command_buffer(
				command_buffers[frame_index],
				swap_chain_images[swap_chain_image_index],
				swap_chain_image_views[swap_chain_image_index],
				swap_chain_extent,
				graphics_pipeline,
				pipeline_layout,
				vertex_buffer,
				index_buffer,
				u32(len(indices)),
				descriptor_sets[frame_index],
				depth_image,
				depth_image_view,
				color_image,
				color_image_view,
			)

			// Submit the command buffer to the graphics queue
			submit_command_buffer(
				app.device.vk_device,
				command_buffers[frame_index],
				draw_fences[frame_index],
				acquire_semaphores[frame_index],
				submit_semaphores[swap_chain_image_index],
				app.device.graphics_queue,
			)

			// Present the image to the user
			swap_chain_recreation_needed = queue_present(
				app.device.vk_device,
				swap_chain,
				submit_semaphores[swap_chain_image_index],
				app.device.graphics_queue,
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

			destroy_depth_resources(app.device.vk_device, depth_image, depth_image_memory, depth_image_view)
			destroy_color_resources(app.device.vk_device, color_image, color_image_memory, color_image_view)
			destroy_swap_chain_image_views(app.device.vk_device, swap_chain_image_views)
			destroy_swap_chain_images(app.device.vk_device, swap_chain_images)
			destroy_swap_chain(app.device.vk_device, swap_chain)

			swap_chain, swap_chain_extent, swap_chain_format = create_swap_chain(
				app.physical_device.vk_physical_device,
				app.device.vk_device,
				app.window.surface,
				app.window.window_handle,
			)
			swap_chain_images = get_swap_chain_images(app.device.vk_device, swap_chain)
			swap_chain_image_views = create_image_views(app.device.vk_device, swap_chain_images, swap_chain_format)
			color_image, color_image_memory, color_image_view = create_color_resources(
				app.physical_device.vk_physical_device,
				app.device.vk_device,
				swap_chain_format,
				swap_chain_extent,
				samples,
			)
			depth_image, depth_image_memory, depth_image_view = create_depth_resources(
				app.physical_device.vk_physical_device,
				app.device.vk_device,
				depth_format,
				swap_chain_extent,
				samples,
			)

			fmt.println("Swap chain recreation... OK")
		}

		// Next frame
		frame_index = (frame_index + 1) % NB_FRAMES_IN_FLIGHT
	}

	// Wait to prevent fence-in-use error.
	wait_idle_device(app.device.vk_device)

	//---------------------

	// Cleanup
	delete(descriptor_sets)
	if descriptor_pool != 0 {
		vk.DestroyDescriptorPool(app.device.vk_device, descriptor_pool, nil)
	}
	for i in 0 ..< NB_FRAMES_IN_FLIGHT {
		vk.UnmapMemory(app.device.vk_device, ubo_buffer_memories[i])
		vk.FreeMemory(app.device.vk_device, ubo_buffer_memories[i], nil)
		vk.DestroyBuffer(app.device.vk_device, ubo_buffers[i], nil)
	}
	if ubo_descriptor_set_layout != 0 {
		vk.DestroyDescriptorSetLayout(app.device.vk_device, ubo_descriptor_set_layout, nil)
	}
	if sampler != 0 {
		vk.DestroySampler(app.device.vk_device, sampler, nil)
	}
	if image_view != 0 {
		vk.DestroyImageView(app.device.vk_device, image_view, nil)
	}
	if image_memory != 0 {
		vk.FreeMemory(app.device.vk_device, image_memory, nil)
	}
	if image != 0 {
		vk.DestroyImage(app.device.vk_device, image, nil)
	}
	if index_buffer_memory != 0 {
		vk.FreeMemory(app.device.vk_device, index_buffer_memory, nil)
	}
	if index_buffer != 0 {
		vk.DestroyBuffer(app.device.vk_device, index_buffer, nil)
	}
	if vertex_buffer_memory != 0 {
		vk.FreeMemory(app.device.vk_device, vertex_buffer_memory, nil)
	}
	if vertex_buffer != 0 {
		vk.DestroyBuffer(app.device.vk_device, vertex_buffer, nil)
	}
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
	if pipeline_layout != 0 {
		vk.DestroyPipelineLayout(app.device.vk_device, pipeline_layout, nil)
	}
	if graphics_pipeline != 0 {
		vk.DestroyPipeline(app.device.vk_device, graphics_pipeline, nil)
	}
	if shader_module != 0 {
		vk.DestroyShaderModule(app.device.vk_device, shader_module, nil)
	}

	destroy_depth_resources(app.device.vk_device, depth_image, depth_image_memory, depth_image_view)
	destroy_color_resources(app.device.vk_device, color_image, color_image_memory, color_image_view)
	destroy_swap_chain_image_views(app.device.vk_device, swap_chain_image_views)
	destroy_swap_chain_images(app.device.vk_device, swap_chain_images)
	destroy_swap_chain(app.device.vk_device, swap_chain)

	destroy_app(&app)
}
