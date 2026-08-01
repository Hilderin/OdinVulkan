package ovk

import im "../imgui"
import im_glfw "../imgui/backends/glfw"
import im_vk "../imgui/backends/vulkan"
import vk "vendor:vulkan"

// State kept by ovk for the ImGui integration. The rest of ImGui's state lives
// in its own global context, created by init_imgui.
ImGui :: struct {
	device:            ^Device,
	swap_chain_format: vk.Format,
	descriptor_pool:   vk.DescriptorPool,
}

Init_ImGui_Args :: struct {
	device:            ^Device,
	window:            ^Window,
	swap_chain_format: vk.Format,
	min_image_count:   u32,
	image_count:       u32,
}

// Initialize the three ImGui layers: core context, GLFW backend, Vulkan backend.
// The Vulkan backend renders with dynamic rendering, like the rest of ovk, so it
// gets the swapchain color format instead of a render pass.
// Call this after the swap chain is created and before the main loop.
init_imgui :: proc(args: Init_ImGui_Args) -> (imgui: ImGui, err: Error) {

	im.CHECKVERSION()

	imgui.device = args.device
	// Stored on the struct so the pointer handed to the backend stays valid for
	// the whole application lifetime.
	imgui.swap_chain_format = args.swap_chain_format

	// ImGui allocates all its descriptors from one pool. The pool is sized
	// generously, like in the ImGui demo: a too small pool makes a single
	// widget throw a validation error in the middle of a frame.
	pool_sizes := []vk.DescriptorPoolSize {
		{type = .SAMPLER, descriptorCount = 1000},
		{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1000},
		{type = .SAMPLED_IMAGE, descriptorCount = 1000},
		{type = .STORAGE_IMAGE, descriptorCount = 1000},
		{type = .UNIFORM_TEXEL_BUFFER, descriptorCount = 1000},
		{type = .STORAGE_TEXEL_BUFFER, descriptorCount = 1000},
		{type = .UNIFORM_BUFFER, descriptorCount = 1000},
		{type = .STORAGE_BUFFER, descriptorCount = 1000},
		{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = 1000},
		{type = .STORAGE_BUFFER_DYNAMIC, descriptorCount = 1000},
		{type = .INPUT_ATTACHMENT, descriptorCount = 1000},
	}

	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1000,
		poolSizeCount = u32(len(pool_sizes)),
		pPoolSizes    = raw_data(pool_sizes),
	}

	check(vk.CreateDescriptorPool(args.device.vk_device, &pool_info, nil, &imgui.descriptor_pool), "Failed to create the ImGui descriptor pool!") or_return

	// ImGui's core context keeps the global state of the UI (windows, widgets...).
	im.CreateContext()

	// The GLFW backend installs ImGui's input callbacks on the window. The
	// callbacks chain to previously installed ones, so register your own callbacks
	// (like the Escape key callback) before calling init_imgui.
	if !im_glfw.InitForVulkan(args.window.window_handle, true) {
		err = General_Error{"Failed to initialize the ImGui GLFW backend!"}
		return
	}

	// The Vulkan backend builds its pipeline with dynamic rendering.
	pipeline_info := im_vk.PipelineInfo {
		PipelineRenderingCreateInfo = vk.PipelineRenderingCreateInfo {
			sType = .PIPELINE_RENDERING_CREATE_INFO,
			colorAttachmentCount = 1,
			pColorAttachmentFormats = &imgui.swap_chain_format,
		},
		MSAASamples = {._1},
	}

	init_info := im_vk.InitInfo {
		ApiVersion          = vk.API_VERSION_1_4,
		Instance            = args.device.physical_device.instance.vk_instance,
		PhysicalDevice      = args.device.physical_device.vk_physical_device,
		Device              = args.device.vk_device,
		QueueFamily         = args.device.physical_device.graphics_queue_family,
		Queue               = args.device.graphics_queue.vk_queue,
		DescriptorPool      = imgui.descriptor_pool,
		MinImageCount       = args.min_image_count,
		ImageCount          = args.image_count,
		UseDynamicRendering = true,
		PipelineInfoMain    = pipeline_info,
	}

	// The backend needs to resolve the Vulkan functions it uses, so we hand it a
	// loader based on our instance, like the one used at instance creation.
	if !im_vk.LoadFunctions(vk.API_VERSION_1_4, imgui_load_functions, rawptr(args.device.physical_device.instance)) {
		err = General_Error{"Failed to load the ImGui Vulkan functions!"}
		return
	}

	if !im_vk.Init(&init_info) {
		err = General_Error{"Failed to initialize the ImGui Vulkan backend!"}
		return
	}

	return
}

// Shutdown the three ImGui layers and free the descriptor pool.
// Call this when the device is done with its last frame and before destroying the device.
destroy_imgui :: proc(imgui: ^ImGui) {
	if imgui == nil {
		return
	}

	im_vk.Shutdown()
	im_glfw.Shutdown()
	im.DestroyContext()

	if imgui.device != nil && imgui.device.vk_device != nil && imgui.descriptor_pool != 0 {
		vk.DestroyDescriptorPool(imgui.device.vk_device, imgui.descriptor_pool, nil)
	}
}

// Start a new ImGui frame. The order matters: the platform backend (GLFW) feeds
// the inputs, the renderer backend (Vulkan) reads them, and the core builds the UI.
// Call this once per rendered frame, after acquiring the swapchain image and
// before building the UI and calling im.Render().
imgui_new_frame :: proc() {
	im_glfw.NewFrame()
	im_vk.NewFrame()
	im.NewFrame()
}

// Record a dynamic rendering pass that draws the ImGui UI into a single color
// attachment. The attachment is the swapchain image: it must be in
// COLOR_ATTACHMENT_OPTIMAL layout. loadOp is LOAD so the geometry rendered
// before stays visible behind the UI.
cmd_draw_imgui :: proc(command_buffer: ^Command_Buffer, target_view: vk.ImageView, extent: vk.Extent2D) {

	attachment_info := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = target_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .LOAD,
		storeOp     = .STORE,
	}

	render_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = extent},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &attachment_info,
	}

	vk.CmdBeginRendering(command_buffer.vk_command_buffer, &render_info)
	im_vk.RenderDrawData(im.GetDrawData(), command_buffer.vk_command_buffer)
	vk.CmdEndRendering(command_buffer.vk_command_buffer)
}

// Resolve Vulkan function pointers for the ImGui backend.
@(private = "file")
imgui_load_functions :: proc "c" (function_name: cstring, user_data: rawptr) -> vk.ProcVoidFunction {
	instance := cast(^Instance)user_data
	return vk.GetInstanceProcAddr(instance.vk_instance, function_name)
}
