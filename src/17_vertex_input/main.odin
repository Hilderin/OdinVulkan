package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"


// Important aliases for math types
vec2 :: [2]f32
vec3 :: [3]f32

// Vertex attributes
Vertex :: struct {
	pos:   vec2,
	color: vec3,
}

// Number of frames in flight
NB_FRAMES_IN_FLIGHT :: 2

// Globals needed for debug messenger cleanup.
g_debug_messenger: vk.DebugUtilsMessengerEXT = {}

// Debug level — controls which severities are enabled and printed.
g_debug_level: vk.DebugUtilsMessageSeverityFlagsEXT = {.WARNING, .ERROR}

// Required validation layers.
g_validation_layers := []cstring{"VK_LAYER_KHRONOS_validation"}

// Required extensions
g_required_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

// Manage the escape key exit.
g_running: bool = true

// Manage the window resize callback
g_framebuffer_resized: bool = false


vk_check :: proc(result: vk.Result, operation: string, loc := #caller_location) {
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


debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	// "system" callbacks are called from C without an Odin context, we need to specify the default context to compile.
	context = runtime.default_context()
	if .ERROR in messageSeverity && .ERROR in g_debug_level {
		fmt.eprintfln("[validation ERROR] %s", pCallbackData.pMessage)
	} else if .WARNING in messageSeverity && .WARNING in g_debug_level {
		fmt.eprintfln("[validation WARNING] %s", pCallbackData.pMessage)
	} else if .INFO in messageSeverity && .INFO in g_debug_level {
		fmt.println("[validation INFO]", pCallbackData.pMessage)
	} else if .VERBOSE in messageSeverity && .VERBOSE in g_debug_level {
		fmt.printfln("[validation VERBOSE] %s", pCallbackData.pMessage)
	}
	return false
}


create_instance :: proc() -> vk.Instance {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	if !are_layers_supported(g_validation_layers) {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		os.exit(1)
	}

	app_info := vk.ApplicationInfo {
		sType              = vk.StructureType.APPLICATION_INFO,
		pApplicationName   = "Vulkan initialization",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_4,
	}

	extensions := glfw.GetRequiredInstanceExtensions()
	ext_names: [dynamic]cstring
	defer delete(ext_names)
	append(&ext_names, ..extensions)
	append(&ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

	debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = g_debug_level,
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_callback,
		pUserData       = nil,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(ext_names)),
		ppEnabledExtensionNames = raw_data(ext_names[:]),
		enabledLayerCount       = u32(len(g_validation_layers)),
		ppEnabledLayerNames     = raw_data(g_validation_layers),
		pNext                   = &debug_create_info,
	}

	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "failed to create instance!")
	vk.load_proc_addresses_instance(instance)

	if vk.CreateDebugUtilsMessengerEXT != nil {
		vk_check(vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &g_debug_messenger), "failed to create debug messenger!")
	}

	return instance
}


are_layers_supported :: proc(required_layers: []cstring) -> b32 {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count)
	defer delete(available_layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	for req_layer in required_layers {
		found := false
		for &layer in available_layers {
			if cstring(&layer.layerName[0]) == req_layer {
				found = true
				break
			}
		}
		if !found {
			return false
		}
	}
	return true
}


is_physical_device_support_surface :: proc(physical_device: vk.PhysicalDevice, queue_index: u32, surface: vk.SurfaceKHR) -> bool {
	supported: b32
	result := vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, queue_index, surface, &supported)
	if result != .SUCCESS {
		fmt.eprintln("Error getting physical device surface support.")
		return false
	}
	return bool(supported)
}


find_queue_families :: proc(physical_device: vk.PhysicalDevice, queue_flags: vk.QueueFlags, surface: vk.SurfaceKHR) -> (u32, bool) {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, nil)

	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, raw_data(queue_families))

	for queue_family, i in queue_families {
		if (queue_flags & queue_family.queueFlags) == queue_flags {
			if surface == 0 || is_physical_device_support_surface(physical_device, u32(i), surface) {
				return u32(i), true
			}
		}
	}
	return 0, false
}


get_device_features :: proc(
	device: vk.PhysicalDevice,
) -> (
	vk.PhysicalDeviceVulkan11Features,
	vk.PhysicalDeviceVulkan13Features,
	vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT,
	vk.PhysicalDeviceFeatures,
) {
	vulkan13_features := vk.PhysicalDeviceVulkan13Features {
		sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}
	extended_dynamic_state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType = vk.StructureType.PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
	}
	vulkan13_features.pNext = &extended_dynamic_state_features

	vulkan11_features := vk.PhysicalDeviceVulkan11Features {
		sType = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = &vulkan13_features,
	}

	features2 := vk.PhysicalDeviceFeatures2 {
		sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2,
		pNext = &vulkan11_features,
	}

	vk.GetPhysicalDeviceFeatures2(device, &features2)
	return vulkan11_features, vulkan13_features, extended_dynamic_state_features, features2.features
}


score_device :: proc(device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> int {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(device, &props)

	name := string(cstring(&props.deviceName[0]))

	// Require at least Vulkan 1.4.
	if props.apiVersion < vk.API_VERSION_1_4 {
		fmt.printfln(
			"  %q — apiVersion=%d.%d.%d, < 1.4 (skipped)",
			name,
			vk.API_VERSION_MAJOR(props.apiVersion),
			vk.API_VERSION_MINOR(props.apiVersion),
			vk.API_VERSION_PATCH(props.apiVersion),
		)
		return -1
	}

	// Must have at least a graphics queue family.
	if _, ok := find_queue_families(device, {.GRAPHICS}, surface); !ok {
		fmt.printfln("  %q — no graphics queue (skipped)", name)
		return -1
	}

	// Must support all required device extensions.
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)
	available_exts := make([]vk.ExtensionProperties, ext_count)
	defer delete(available_exts)
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, raw_data(available_exts))

	for req_ext in g_required_extensions {
		found := false
		for &ext in available_exts {
			if cstring(&ext.extensionName[0]) == req_ext {
				found = true
				break
			}
		}
		if !found {
			fmt.printfln("  %q — missing required extension %s (skipped)", name, req_ext)
			return -1
		}
	}

	vulkan11_f, vulkan13_f, ext_dynamic_f, base_f := get_device_features(device)

	if !vulkan11_f.shaderDrawParameters {
		fmt.printfln("  %q — missing shaderDrawParameters (skipped)", name)
		return -1
	}
	if !vulkan13_f.dynamicRendering {
		fmt.printfln("  %q — missing dynamicRendering (skipped)", name)
		return -1
	}
	// Since we now use vk.CmdPipelineBarrier2 and the ImageMemoryBarrier2/DependencyInfo structs in transition_image_layout,
	// we now require the synchronization2 feature from Vulkan1.3
	if !vulkan13_f.synchronization2 {
		fmt.printfln("  %q — missing synchronization2 (skipped)", name)
		return -1
	}
	if !ext_dynamic_f.extendedDynamicState {
		fmt.printfln("  %q — missing extendedDynamicState (skipped)", name)
		return -1
	}
	if !base_f.geometryShader {
		fmt.printfln("  %q — missing geometryShader (skipped)", name)
		return -1
	}


	score := 0

	// Discrete GPUs have a significant performance advantage.
	if props.deviceType == .DISCRETE_GPU {
		score += 1000
	} else if props.deviceType == .INTEGRATED_GPU {
		score += 500
	}

	// Maximum possible size of textures affects graphics quality.
	score += int(props.limits.maxImageDimension2D)

	fmt.printfln("  %q — type=%v, score=%d", name, props.deviceType, score)
	return score
}


pick_physical_device :: proc(instance: vk.Instance, surface: vk.SurfaceKHR) -> vk.PhysicalDevice {
	dev_count: u32
	vk.EnumeratePhysicalDevices(instance, &dev_count, nil)
	if dev_count == 0 {
		fmt.eprintln("failed to find GPUs with Vulkan support!")
		os.exit(1)
	}

	physical_devices := make([]vk.PhysicalDevice, dev_count)
	defer delete(physical_devices)
	vk.EnumeratePhysicalDevices(instance, &dev_count, raw_data(physical_devices))

	best_score := -1
	best_device: vk.PhysicalDevice = nil

	for device in physical_devices {
		s := score_device(device, surface)
		if s > best_score {
			best_score = s
			best_device = device
		}
	}

	if best_device == nil {
		fmt.eprintln("failed to find a suitable GPU!")
		os.exit(1)
	}

	fmt.printfln("Selected physical device (score=%d)", best_score)
	return best_device
}


create_logical_device :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (vk.Device, vk.Queue) {
	queue_index, ok := find_queue_families(physical_device, {.GRAPHICS}, surface)
	if !ok {
		fmt.eprintfln("No graphics queue found on physical device.")
		os.exit(1)
	}

	queue_priority: f32 = 0.5
	queue_create_info := vk.DeviceQueueCreateInfo {
		sType            = vk.StructureType.DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = queue_index,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	device_feature_extended_dynamic_state := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType                = vk.StructureType.PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		extendedDynamicState = true,
	}

	device_feature_vulkan13 := vk.PhysicalDeviceVulkan13Features {
		sType            = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		// Since we now use vk.CmdPipelineBarrier2 and the ImageMemoryBarrier2/DependencyInfo structs in transition_image_layout,
		// we now require the synchronization2 feature from Vulkan1.3
		synchronization2 = true,
		pNext            = &device_feature_extended_dynamic_state,
	}

	device_feature_vulkan11 := vk.PhysicalDeviceVulkan11Features {
		sType                = vk.StructureType.PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		shaderDrawParameters = true,
		pNext                = &device_feature_vulkan13,
	}

	device_feature_2 := vk.PhysicalDeviceFeatures2 {
		sType = vk.StructureType.PHYSICAL_DEVICE_FEATURES_2,
		pNext = &device_feature_vulkan11,
	}

	create_info := vk.DeviceCreateInfo {
		sType                   = vk.StructureType.DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &queue_create_info,
		queueCreateInfoCount    = 1,
		enabledExtensionCount   = u32(len(g_required_extensions)),
		ppEnabledExtensionNames = raw_data(g_required_extensions),
		pNext                   = &device_feature_2,
	}

	device: vk.Device
	vk_check(vk.CreateDevice(physical_device, &create_info, nil, &device), "Failed to create logical device!")

	queue: vk.Queue
	vk.GetDeviceQueue(device, queue_index, 0, &queue)

	return device, queue
}


create_window :: proc() -> glfw.WindowHandle {
	glfw.WindowHint(glfw.RESIZABLE, 1)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(512, 512, "My first Vulkan Triangle", nil, nil)
	if window == nil {
		fmt.eprintln("Unable to create window")
		os.exit(1)
	}
	return window
}


create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> vk.SurfaceKHR {
	surface: vk.SurfaceKHR
	vk_check(glfw.CreateWindowSurface(instance, window, nil, &surface), "Failed to create surface!")

	return surface
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
	if ((0 < capabilities.maxImageCount) && (capabilities.maxImageCount < min_image_count)) {
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
	vk_check(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities), "Failed to get surface capabilities!")

	swap_chain_extent := choose_swap_extent(surface_capabilities, window)
	min_image_count := choose_swap_min_image_count(surface_capabilities)
	available_formats := get_surface_formats(physical_device, surface)
	defer delete(available_formats)
	format := choose_swap_surface_format(available_formats)
	available_present_modes := get_present_modes(physical_device, surface)
	defer delete(available_present_modes)
	present_mode := choose_present_mode(available_present_modes)

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = vk.StructureType.SWAPCHAIN_CREATE_INFO_KHR,
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
	vk_check(vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain), "Failed to create swap chain!")

	return swap_chain, swap_chain_extent, format.format
}


create_image_views :: proc(device: vk.Device, images: []vk.Image, swap_chain_format: vk.Format) -> []vk.ImageView {

	create_info := vk.ImageViewCreateInfo {
		sType            = vk.StructureType.IMAGE_VIEW_CREATE_INFO,
		viewType         = vk.ImageViewType.D2,
		format           = swap_chain_format,
		subresourceRange = {{.COLOR}, 0, 1, 0, 1},
	}

	image_views := make([]vk.ImageView, len(images))
	for &image, i in images {

		// Set the image, the rest of the struct stays the same for each image.
		create_info.image = image

		vk_check(vk.CreateImageView(device, &create_info, nil, &image_views[i]), "Failed to create image view!")
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
		sType    = vk.StructureType.SHADER_MODULE_CREATE_INFO,
		codeSize = len(spv),
		pCode    = raw_data(slice.reinterpret([]u32, spv)), //Needs to be a pointer to u32
	}

	shader_module: vk.ShaderModule
	vk_check(vk.CreateShaderModule(device, &create_info, nil, &shader_module), "Failed to create shader module!")

	return shader_module

}

create_graphics_pipeline :: proc(
	device: vk.Device,
	shader_module: vk.ShaderModule,
	vertex_entry_point: string,
	fragment_entry_point: string,
	swap_chain_format: vk.Format,
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
		{sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = shader_module, pName = vertex_entry_cstr},
		{sType = vk.StructureType.PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = shader_module, pName = fragment_entry_cstr},
	}

	// -----------------------------------
	// Dynamic state - Defines what can be dymanic in the pipeline
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
		sType             = vk.StructureType.PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// -----------------------------------
	// Vertex input
	// Configure que format of the buffer where the vertices are stored.
	binding_description := vk.VertexInputBindingDescription{}
	binding_description.binding = 0
	binding_description.stride = size_of(Vertex)
	binding_description.inputRate = .VERTEX

	// Configure the data format of vertices
	vertex_attributes_description := []vk.VertexInputAttributeDescription {
		{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
		{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, color))},
	}

	vertex_input_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding_description,
		vertexAttributeDescriptionCount = u32(len(vertex_attributes_description)),
		pVertexAttributeDescriptions    = raw_data(vertex_attributes_description),
	}

	// -----------------------------------
	// Input assembly
	// Configure topology and if primitive restart should be enabled.
	input_assembly_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = vk.StructureType.PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	// No need to specify the pViewports and pScissors because they are dynamic due to the dynamic_states above.
	viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
		sType         = vk.StructureType.PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}


	// -----------------------------------
	// Rasterizer
	rasterizer_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType                   = vk.StructureType.PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = {.BACK},
		frontFace               = .CLOCKWISE,
		depthBiasEnable         = false,
		lineWidth               = 1,
	}

	// -----------------------------------
	// Multisampling
	// Disabled for now. We will enable it in a later chapter.
	multisampling_create_info := vk.PipelineMultisampleStateCreateInfo {
		sType                 = vk.StructureType.PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable   = false,
		rasterizationSamples  = {._1},
		minSampleShading      = 1,
		pSampleMask           = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable      = false,
	}

	// -----------------------------------
	// Depth and stencil testing
	//
	// We don't use it right now, will be back to it in a later chapter.
	//

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
		sType           = vk.StructureType.PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	// -----------------------------------
	// Pipeline layout
	// No uniform right now, so create an empty pipeline layout. We will be back for that too in later chapter.
	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType                  = vk.StructureType.PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 0,
		pSetLayouts            = nil,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = nil,
	}

	pipeline_layout: vk.PipelineLayout
	vk_check(vk.CreatePipelineLayout(device, &pipeline_layout_create_info, nil, &pipeline_layout), "Failed to create pipeline layout!")

	// -----------------------------------
	// Pipeline Rendering Create Info
	// To use dynamic rendering, we need to specify the formats of the attachments that will be used during rendering.
	format := swap_chain_format
	pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType                   = vk.StructureType.PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &format,
	}

	// -----------------------------------
	// Graphics Pipeline
	// Finally!! We create the pipeline that will be used to render!

	pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType               = vk.StructureType.GRAPHICS_PIPELINE_CREATE_INFO,
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
		pNext               = &pipeline_rendering_create_info,
	}

	graphics_pipeline: vk.Pipeline
	vk_check(vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_create_info, nil, &graphics_pipeline), "Failed to create graphics pipeline!")

	return graphics_pipeline, pipeline_layout

}

create_command_pool :: proc(device: vk.Device, physical_device: vk.PhysicalDevice) -> vk.CommandPool {

	queue_index, ok := find_queue_families(physical_device, {.GRAPHICS}, 0)
	if !ok {
		fmt.eprintfln("Impossible to find queue index for graphics.")
		os.exit(1)
	}
	command_pool_create_info := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queue_index,
	}

	command_pool: vk.CommandPool
	vk_check(vk.CreateCommandPool(device, &command_pool_create_info, nil, &command_pool), "Failed to create command pool!")

	return command_pool
}

create_command_buffers :: proc(device: vk.Device, command_pool: vk.CommandPool, command_buffers: []vk.CommandBuffer) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = u32(len(command_buffers)),
	}

	vk_check(vk.AllocateCommandBuffers(device, &alloc_info, raw_data(command_buffers)), "Failed to create command buffer!")
}

begin_command_buffer :: proc(command_buffer: vk.CommandBuffer) {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		flags            = {},
		pInheritanceInfo = nil,
	}

	vk_check(vk.BeginCommandBuffer(command_buffer, &begin_info), "Failed to begin command buffer!")
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
) {

	image_barrier := vk.ImageMemoryBarrier2 {
		sType = vk.StructureType.IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage_mask,
		srcAccessMask = src_access_mask,
		dstStageMask = dst_stage_mask,
		dstAccessMask = dst_access_mask,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = vk.ImageSubresourceRange{aspectMask = {.COLOR}, baseMipLevel = 0, levelCount = 1, baseArrayLayer = 0, layerCount = 1},
	}

	dependency_info := vk.DependencyInfo {
		sType                    = vk.StructureType.DEPENDENCY_INFO,
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

begin_rendering :: proc(command_buffer: vk.CommandBuffer, image_view: vk.ImageView, swap_chain_extent: vk.Extent2D) {

	attachment_info := vk.RenderingAttachmentInfo {
		sType = vk.StructureType.RENDERING_ATTACHMENT_INFO,
		imageView = image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
	}

	render_info := vk.RenderingInfo {
		sType = vk.StructureType.RENDERING_INFO,
		layerCount = 1,
		renderArea = {extent = swap_chain_extent},
		pColorAttachments = &attachment_info,
		colorAttachmentCount = 1,
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
	vk_check(vk.EndCommandBuffer(command_buffer), "Failed to end command buffer!")
}

record_command_buffer :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	image_view: vk.ImageView,
	swap_chain_extent: vk.Extent2D,
	graphics_pipeline: vk.Pipeline,
	vertex_buffer: vk.Buffer,
) {

	// Begin to start the recording...
	begin_command_buffer(command_buffer)

	// Transfert the image to ColorAttachmentOptimal
	transition_image_layout(
		command_buffer,
		image,
		.UNDEFINED,
		.COLOR_ATTACHMENT_OPTIMAL,
		{}, // srcAccessMask
		{.COLOR_ATTACHMENT_WRITE}, // dstAccessMask
		{.COLOR_ATTACHMENT_OUTPUT}, // srcStage
		{.COLOR_ATTACHMENT_OUTPUT}, // dstStage
	)

	// Start rendering
	begin_rendering(command_buffer, image_view, swap_chain_extent)

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

	// Draw vertices from vertex buffer
	vk.CmdDraw(command_buffer, 3, 1, 0, 0)

	// End the rendering
	end_rendering(command_buffer)

	// After rendering, we need to transition the image layout to PresentSrcKHR so it can be displayed on the screen.
	transition_image_layout(
		command_buffer,
		image,
		.COLOR_ATTACHMENT_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.COLOR_ATTACHMENT_WRITE}, // srcAccessMask
		{}, // dstAccessMask
		{.COLOR_ATTACHMENT_OUTPUT}, // srcStage
		{.BOTTOM_OF_PIPE}, // dstStage
	)

	// And we're done recording.
	end_command_buffer(command_buffer)

}

create_semaphore :: proc(device: vk.Device) -> vk.Semaphore {

	semaphore_create_info := vk.SemaphoreCreateInfo {
		sType = vk.StructureType.SEMAPHORE_CREATE_INFO,
		flags = {},
	}

	semaphore: vk.Semaphore
	vk_check(vk.CreateSemaphore(device, &semaphore_create_info, nil, &semaphore), "Failed to create a semaphore!")

	return semaphore

}

create_semaphores :: proc(device: vk.Device, semaphores: []vk.Semaphore) {

	for i in 0 ..< len(semaphores) {
		semaphores[i] = create_semaphore(device)
	}

}

create_fence :: proc(device: vk.Device) -> vk.Fence {

	fence_create_info := vk.FenceCreateInfo {
		sType = vk.StructureType.FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}

	fence: vk.Fence
	vk_check(vk.CreateFence(device, &fence_create_info, nil, &fence), "Failed to create a fence!")

	return fence

}


create_fences :: proc(device: vk.Device, fences: []vk.Fence) {

	for i in 0 ..< len(fences) {
		fences[i] = create_fence(device)
	}

}

wait_for_fence :: proc(device: vk.Device, fence: vk.Fence) {
	local_fence := fence
	vk_check(vk.WaitForFences(device, 1, &local_fence, true, max(u64)), "Failed to wait for fence!")
}

reset_fence :: proc(device: vk.Device, fence: vk.Fence) {
	local_fence := fence
	vk_check(vk.ResetFences(device, 1, &local_fence), "Failed to reset fence!")
}

acquire_next_image :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR, draw_fence: vk.Fence, acquire_semaphore: vk.Semaphore) -> (u32, bool) {

	// Wait until last frame is not done rendering.
	wait_for_fence(device, draw_fence)


	// Acquire next image.
	swapchain_image_index: u32
	result := vk.AcquireNextImageKHR(device, swap_chain, max(u64), acquire_semaphore, 0, &swapchain_image_index)

	// Specials result sfrom AcquireNextImageKHR:
	// - VK_SUBOPTIMAL_KHR: A swapchain no longer matches the surface properties exactly, but can still be used to present to the surface successfully.
	// - VK_ERROR_OUT_OF_DATE_KHR: (usually when the window is resized) A surface has changed in such a way that it is no longer compatible with the swapchain, and further presentation requests using the swapchain will fail. Applications must query the new surface properties and recreate their swapchain if they wish to continue presenting to the surface.
	if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
		// Swap chain needs recreation needed
		return swapchain_image_index, true
	} else if result != .SUCCESS {
		vk_check(result, "Failed to acquire next image!")
	}

	// We need to manually reset the fence to the unsignaled state because a fence do not automatically reset.
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
		sType                = vk.StructureType.SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &local_acquire_semaphore,
		pWaitDstStageMask    = &wait_dest_stages,
		commandBufferCount   = 1,
		pCommandBuffers      = &local_command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &local_render_finish_semaphore,
	}

	vk_check(vk.QueueSubmit(graphics_queue, 1, &submit_info, draw_fence), "Failed to submit command buffer!")
}

queue_present :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR, render_finish_semaphore: vk.Semaphore, graphics_queue: vk.Queue, swapchain_image_index: u32) -> bool {
	local_swap_chain := swap_chain
	local_render_finish_semaphore := render_finish_semaphore
	local_swapchain_image_index := swapchain_image_index

	present_info := vk.PresentInfoKHR {
		sType              = vk.StructureType.PRESENT_INFO_KHR,
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
		vk_check(result, "Failed to queue to presentation!")
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
		sType       = vk.StructureType.BUFFER_CREATE_INFO,
		size        = vk.DeviceSize(size),
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	buffer: vk.Buffer
	vk_check(vk.CreateBuffer(device, &buffer_info, nil, &buffer), "Failed to create buffer!")

	// Memory allocation
	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(device, buffer, &mem_requirements)

	// Find the memory type based on mem requirements and asked properties.
	memory_type_index, ok := find_memory_type(physical_device, mem_requirements.memoryTypeBits, properties)
	if !ok {
		fmt.eprintfln("Failed to find memory type.")
		os.exit(1)
	}

	// Allocate...
	alloc_info := vk.MemoryAllocateInfo {
		sType           = vk.StructureType.MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type_index,
	}

	buffer_memory: vk.DeviceMemory
	vk_check(vk.AllocateMemory(device, &alloc_info, nil, &buffer_memory), "Failed to allocate memory!")

	// Bind the memory to the buffer
	vk_check(vk.BindBufferMemory(device, buffer, buffer_memory, 0), "Failed to bind buffer memory!")

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
	dest_data: [^]u8

	vk_check(vk.MapMemory(device, buffer_memory, 0, vk.DeviceSize(size), {}, cast(^rawptr)&dest_data), "Failed to map memory!")

	mem.copy(dest_data[0:], raw_data(data), size)

	vk.UnmapMemory(device, buffer_memory)

}

main :: proc() {
	fmt.println("Vulkan initialization")
	fmt.println("-------------------------------------------")

	// We need to initialize GLFW so the glfw.GetInstanceProcAddress() method returns a valid callback to load Vulkan function addresses.
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	// Create Vulkan instance...
	instance := create_instance()
	fmt.println("Create instance... OK")

	// Create window
	window := create_window()
	fmt.println("Window... OK")

	// Create surface
	surface := create_surface(instance, window)
	fmt.println("Surface... OK")

	// Pick physical device
	physical_device := pick_physical_device(instance, surface)
	fmt.println("Physical device... OK")

	// Create logical device
	device, graphics_queue := create_logical_device(physical_device, surface)
	fmt.println("Logical device... OK")

	// Create swap chain
	swap_chain, swap_chain_extent, swap_chain_format := create_swap_chain(physical_device, device, surface, window)
	fmt.println("Swap chain... OK")

	// Get swap chain images
	swap_chain_images := get_swap_chain_images(device, swap_chain)
	fmt.printfln("Swap chain images [%d]... OK", len(swap_chain_images))

	// Create image views
	swap_chain_image_views := create_image_views(device, swap_chain_images, swap_chain_format)
	fmt.println("Swap chain images views... OK")

	// Create shader module
	shader_module := create_shader_module(device, "shader.slang", {"vertMain", "fragMain"})
	fmt.println("Shader module... OK")

	// Create graphics pipeline
	graphics_pipeline, pipeline_layout := create_graphics_pipeline(device, shader_module, "vertMain", "fragMain", swap_chain_format)
	fmt.println("Graphics pipeline... OK")

	// Command pool
	command_pool := create_command_pool(device, physical_device)
	fmt.println("Command pool... OK")

	// Command buffer
	command_buffers: [NB_FRAMES_IN_FLIGHT]vk.CommandBuffer
	create_command_buffers(device, command_pool, command_buffers[:])
	fmt.println("Command buffer... OK")

	// Semaphore to signal that an image has been acquired from the swapchain and is ready for rendering
	acquire_semaphores: [NB_FRAMES_IN_FLIGHT]vk.Semaphore
	create_semaphores(device, acquire_semaphores[:])
	fmt.println("Acquire complete semaphore... OK")

	// Semaphores that are waited on by QueuePresent are buffered based on the number of swapchain images
	// NOTE: I adjusted the code from the official Vulkan Tutorial to follow guidelines for semaphore
	//       which suggest a semaphore per swap chain image.
	//       See: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
	submit_semaphores := make([]vk.Semaphore, len(swap_chain_images))
	defer delete(submit_semaphores)
	create_semaphores(device, submit_semaphores[:])
	fmt.printfln("Submit finish semaphores (%d)... OK", len(submit_semaphores))

	// Fence to make sure only one frame is rendered at a time
	draw_fences: [NB_FRAMES_IN_FLIGHT]vk.Fence
	create_fences(device, draw_fences[:])
	fmt.println("Draw fence... OK")

	// Vertex buffer creation...
    // odinfmt: disable
	vertices := []Vertex{
        {pos = {0.0, -0.5}, color = {1.0, 0.0, 0.0}},
        {pos = {0.5, 0.5}, color = {0.0, 1.0, 0.0}},
        {pos = {-0.5, 0.5}, color= {0.0, 0.0, 1.0}},
    }
    // odinfmt: enable
	vertex_buffer, vertex_buffer_memory := create_buffer(physical_device, device, u64(size_of(Vertex) * len(vertices)), {.VERTEX_BUFFER}, {.HOST_VISIBLE, .HOST_COHERENT})
	fmt.println("Vertex buffer... OK")

	// Copy vertex data to memory
	mem_copy_to_buffer(device, vertex_buffer_memory, vertices)
	fmt.println("Vertex copied to buffer... OK")


	fmt.println()
	fmt.println("Vulkan initialization completed with success!")
	fmt.println("Press Escape to quit.")

	//---------------------
	// Event loop — keep the window open until the user closes it or hits Escape.
	key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
		if key == glfw.KEY_ESCAPE {
			g_running = false
		}
	}
	glfw.SetKeyCallback(window, key_callback)

	// Window resize
	framebuffer_resize_callback :: proc "c" (window: glfw.WindowHandle, width: i32, height: i32) {
		g_framebuffer_resized = true
	}
	glfw.SetFramebufferSizeCallback(window, framebuffer_resize_callback)

	frame_index: u32 = 0
	for !glfw.WindowShouldClose(window) && g_running {
		glfw.PollEvents()

		//Acquire next image.
		swap_chain_image_index, swap_chain_recreation_needed := acquire_next_image(device, swap_chain, draw_fences[frame_index], acquire_semaphores[frame_index])

		if !swap_chain_recreation_needed {
			// Record command buffer
			record_command_buffer(
				command_buffers[frame_index],
				swap_chain_images[swap_chain_image_index],
				swap_chain_image_views[swap_chain_image_index],
				swap_chain_extent,
				graphics_pipeline,
				vertex_buffer,
			)

			// Submit the command buffer to the graphics queue
			submit_command_buffer(
				device,
				command_buffers[frame_index],
				draw_fences[frame_index],
				acquire_semaphores[frame_index],
				submit_semaphores[swap_chain_image_index],
				graphics_queue,
			)

			// Present the image to the user
			swap_chain_recreation_needed = queue_present(device, swap_chain, submit_semaphores[swap_chain_image_index], graphics_queue, swap_chain_image_index)
		}

		// Swap chain recreation?
		if swap_chain_recreation_needed || g_framebuffer_resized {
			fmt.println("Swap chain recreation...")

			// Manage minimized window, we will simply pause the process
			width, height := glfw.GetFramebufferSize(window)
			for width == 0 && height == 0 {
				glfw.WaitEvents()
				width, height = glfw.GetFramebufferSize(window)
			}

			g_framebuffer_resized = false
			wait_idle_device(device)

			destroy_swap_chain_image_views(device, swap_chain_image_views)
			destroy_swap_chain_images(device, swap_chain_images)
			destroy_swap_chain(device, swap_chain)

			swap_chain, swap_chain_extent, swap_chain_format = create_swap_chain(physical_device, device, surface, window)
			swap_chain_images = get_swap_chain_images(device, swap_chain)
			swap_chain_image_views = create_image_views(device, swap_chain_images, swap_chain_format)

			fmt.println("Swap chain recreation... OK")
		}

		// Next frame
		frame_index = (frame_index + 1) % NB_FRAMES_IN_FLIGHT
	}

	// Prevent error fence is currently in use.
	wait_idle_device(device)

	//---------------------

	// Cleanup
	if vertex_buffer_memory != 0 {
		vk.FreeMemory(device, vertex_buffer_memory, nil)
	}
	if vertex_buffer != 0 {
		vk.DestroyBuffer(device, vertex_buffer, nil)
	}
	for draw_fence in draw_fences {
		if draw_fence != 0 {
			vk.DestroyFence(device, draw_fence, nil)
		}
	}
	for acquire_semaphore in acquire_semaphores {
		if acquire_semaphore != 0 {
			vk.DestroySemaphore(device, acquire_semaphore, nil)
		}
	}
	for submit_semaphore in submit_semaphores {
		if submit_semaphore != 0 {
			vk.DestroySemaphore(device, submit_semaphore, nil)
		}
	}
	if command_pool != 0 {
		vk.DestroyCommandPool(device, command_pool, nil)
	}
	if pipeline_layout != 0 {
		vk.DestroyPipelineLayout(device, pipeline_layout, nil)
	}
	if graphics_pipeline != 0 {
		vk.DestroyPipeline(device, graphics_pipeline, nil)
	}
	if shader_module != 0 {
		vk.DestroyShaderModule(device, shader_module, nil)
	}

	destroy_swap_chain_image_views(device, swap_chain_image_views)
	destroy_swap_chain_images(device, swap_chain_images)
	destroy_swap_chain(device, swap_chain)

	if device != nil {
		vk.DestroyDevice(device, nil)
	}
	if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
		vk.DestroyDebugUtilsMessengerEXT(instance, g_debug_messenger, nil)
	}
	if surface != 0 {
		vk.DestroySurfaceKHR(instance, surface, nil)
	}
	if instance != nil {
		vk.DestroyInstance(instance, nil)
	}
	if window != nil {
		glfw.DestroyWindow(window)
	}
	glfw.Terminate()
}
