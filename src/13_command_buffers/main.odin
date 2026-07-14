package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

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


create_instance :: proc() -> (vk.Instance, bool) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	if !are_layers_supported(g_validation_layers) {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		return nil, false
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
	result := vk.CreateInstance(&create_info, nil, &instance)
	if result != vk.Result.SUCCESS {
		fmt.eprintln("failed to create instance!")
		return nil, false
	}
	vk.load_proc_addresses_instance(instance)

	if vk.CreateDebugUtilsMessengerEXT != nil {
		if vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &g_debug_messenger) != vk.Result.SUCCESS {
			fmt.eprintln("failed to create debug messenger!")
			return nil, false
		}
	}

	return instance, true
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


pick_physical_device :: proc(instance: vk.Instance, surface: vk.SurfaceKHR) -> (vk.PhysicalDevice, bool) {
	dev_count: u32
	vk.EnumeratePhysicalDevices(instance, &dev_count, nil)
	if dev_count == 0 {
		fmt.eprintln("failed to find GPUs with Vulkan support!")
		return nil, false
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
		return nil, false
	}

	fmt.printfln("Selected physical device (score=%d)", best_score)
	return best_device, true
}


create_logical_device :: proc(physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> (vk.Device, vk.Queue, bool) {
	queue_index, ok := find_queue_families(physical_device, {.GRAPHICS}, surface)
	if !ok {
		fmt.eprintfln("No graphics queue found on physical device.")
		return nil, nil, false
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
	if vk.CreateDevice(physical_device, &create_info, nil, &device) != vk.Result.SUCCESS {
		fmt.eprintln("Failed to create logical device!")
		return nil, nil, false
	}

	queue: vk.Queue
	vk.GetDeviceQueue(device, queue_index, 0, &queue)

	return device, queue, true
}


create_window :: proc() -> (glfw.WindowHandle, bool) {
	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(512, 512, "My first window", nil, nil)
	if window == nil {
		fmt.eprintln("Unable to create window")
		return nil, false
	}
	return window, true
}


create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> (vk.SurfaceKHR, bool) {
	surface: vk.SurfaceKHR
	result := glfw.CreateWindowSurface(instance, window, nil, &surface)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create surface! VkResult=%v", result)
		return 0, false
	}

	return surface, true
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


create_swap_chain :: proc(
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	surface: vk.SurfaceKHR,
	window: glfw.WindowHandle,
) -> (
	vk.SwapchainKHR,
	vk.Extent2D,
	vk.Format,
	bool,
) {
	surface_capabilities: vk.SurfaceCapabilitiesKHR
	result := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create swap chain! VkResult=%v", result)
		return 0, vk.Extent2D{}, .UNDEFINED, false
	}

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
	result = vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create swap chain. VkResult=%v", result)
		return 0, vk.Extent2D{}, .UNDEFINED, false
	}

	return swap_chain, swap_chain_extent, format.format, true
}


create_image_views :: proc(device: vk.Device, images: []vk.Image, swap_chain_format: vk.Format) -> ([]vk.ImageView, bool) {

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

		result := vk.CreateImageView(device, &create_info, nil, &image_views[i])
		if result != .SUCCESS {
			fmt.eprintfln("Failed to create image view. VkResult=%v", result)
			return nil, false
		}
	}

	return image_views, true
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

create_shader_module :: proc(device: vk.Device, slang_path: string, entry_points: []string) -> (vk.ShaderModule, bool) {
	spv, ok := compile_slang_shader(slang_path, entry_points)
	if !ok {
		fmt.eprintln("Shader compilation failed.")
		return 0, false
	}
	defer delete(spv)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = vk.StructureType.SHADER_MODULE_CREATE_INFO,
		codeSize = len(spv),
		pCode    = raw_data(slice.reinterpret([]u32, spv)), //Needs to be a pointer to u32
	}

	shader_module: vk.ShaderModule
	result := vk.CreateShaderModule(device, &create_info, nil, &shader_module)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create shader module. VkResult=%v", result)
		return 0, false
	}

	return shader_module, true

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
	bool,
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
	// Configure the data format of vertices
	// Because we're hard coding the vertex data directly in the vertex shader, we'll fill in this structure to specify that there is no vertex data to load for now. We'll get back to it in the vertex buffer chapter.
	vertex_input_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = vk.StructureType.PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 0,
		pVertexBindingDescriptions      = nil,
		vertexAttributeDescriptionCount = 0,
		pVertexAttributeDescriptions    = nil,
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
	result := vk.CreatePipelineLayout(device, &pipeline_layout_create_info, nil, &pipeline_layout)

	if result != .SUCCESS {
		fmt.eprintfln("Failed to create pipeline layout. VkResult=%v", result)
		return 0, 0, false
	}

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
	result = vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_create_info, nil, &graphics_pipeline)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create graphics pipeline. VkResult=%v", result)
		return 0, 0, false
	}

	return graphics_pipeline, pipeline_layout, true

}

create_command_pool :: proc(device: vk.Device, physical_device: vk.PhysicalDevice) -> (vk.CommandPool, bool) {

	queue_index, ok := find_queue_families(physical_device, {.GRAPHICS}, 0)
	if !ok {
		fmt.eprintfln("Impossible to find queue index for graphics.")
		return 0, false
	}
	command_pool_create_info := vk.CommandPoolCreateInfo {
		sType            = vk.StructureType.COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = queue_index,
	}

	command_pool: vk.CommandPool
	result := vk.CreateCommandPool(device, &command_pool_create_info, nil, &command_pool)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create command pool. VkResult=%v", result)
		return 0, false
	}

	return command_pool, true
}

create_command_buffer :: proc(device: vk.Device, command_pool: vk.CommandPool) -> (vk.CommandBuffer, bool) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = vk.StructureType.COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}

	// Here, Vulkan needs an allocated array of CommandBuffer.
	command_buffers := make([]vk.CommandBuffer, 1)
	result := vk.AllocateCommandBuffers(device, &alloc_info, raw_data(command_buffers))
	if result != .SUCCESS {
		fmt.eprintfln("Failed to create command pool. VkResult=%v", result)
		return nil, false
	}

	return command_buffers[0], true
}

begin_command_buffer :: proc(command_buffer: vk.CommandBuffer) -> bool {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = vk.StructureType.COMMAND_BUFFER_BEGIN_INFO,
		flags            = {},
		pInheritanceInfo = nil,
	}

	result := vk.BeginCommandBuffer(command_buffer, &begin_info)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to begin command buffer. VkResult=%v", result)
		return false
	}

	return true
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


end_command_buffer :: proc(command_buffer: vk.CommandBuffer) -> bool {
	result := vk.EndCommandBuffer(command_buffer)
	if result != .SUCCESS {
		fmt.eprintfln("Failed to end command buffer. VkResult=%v", result)
		return false
	}

	return true
}

record_command_buffer :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	image_view: vk.ImageView,
	swap_chain_extent: vk.Extent2D,
	graphics_pipeline: vk.Pipeline,
) -> bool {

	// Begin to start the recording...
	if !begin_command_buffer(command_buffer) {
		return false
	}

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

	// Draw 3 vertices
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
	if !end_command_buffer(command_buffer) {
		return false
	}

	return true
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
	instance, ok := create_instance()
	if !ok {
		fmt.eprintln("Create instance failed.")
		os.exit(1)
	}
	fmt.println("Create instance... OK")

	// Create window
	window: glfw.WindowHandle
	window, ok = create_window()
	if !ok {
		fmt.eprintln("Failed to create GLFW window.")
		os.exit(1)
	}
	fmt.println("Window... OK")

	// Create surface
	surface: vk.SurfaceKHR
	surface, ok = create_surface(instance, window)
	if !ok {
		fmt.eprintln("Failed to create surface.")
		os.exit(1)
	}
	fmt.println("Surface... OK")

	// Pick physical device
	physical_device: vk.PhysicalDevice
	physical_device, ok = pick_physical_device(instance, surface)
	if !ok {
		fmt.eprintln("Compatible physical device not found.")
		os.exit(1)
	}
	fmt.println("Physical device... OK")

	// Create logical device
	device: vk.Device
	device, _, ok = create_logical_device(physical_device, surface)
	if !ok {
		fmt.eprintln("Failed to create logical device.")
		os.exit(1)
	}
	fmt.println("Logical device... OK")

	// Create swap chain
	swap_chain: vk.SwapchainKHR
	swap_chain_extent: vk.Extent2D
	swap_chain_format: vk.Format
	swap_chain, swap_chain_extent, swap_chain_format, ok = create_swap_chain(physical_device, device, surface, window)
	if !ok {
		fmt.eprintln("Failed to create swap chain.")
		os.exit(1)
	}
	fmt.println("Swap chain... OK")

	// Get swap chain images
	swap_chain_images := get_swap_chain_images(device, swap_chain)
	defer delete(swap_chain_images)
	fmt.printfln("Swap chain images [%d]... OK", len(swap_chain_images))


	// Create image views
	swap_chain_image_views: []vk.ImageView
	swap_chain_image_views, ok = create_image_views(device, swap_chain_images, swap_chain_format)
	if !ok {
		fmt.eprintln("Failed to create swap chain images views.")
		os.exit(1)
	}
	fmt.println("Swap chain images views... OK")


	// Create shader module
	shader_module: vk.ShaderModule
	shader_module, ok = create_shader_module(device, "shader.slang", {"vertMain", "fragMain"})
	if !ok {
		fmt.eprintln("Failed to create shader module.")
		os.exit(1)
	}
	fmt.println("Shader module... OK")


	// Create graphics pipeline
	graphics_pipeline: vk.Pipeline
	pipeline_layout: vk.PipelineLayout
	graphics_pipeline, pipeline_layout, ok = create_graphics_pipeline(device, shader_module, "vertMain", "fragMain", swap_chain_format)
	if !ok {
		fmt.eprintln("Failed to create graphics pipeline.")
		os.exit(1)
	}
	fmt.println("Graphics pipeline... OK")


	// Command pool
	command_pool: vk.CommandPool
	command_pool, ok = create_command_pool(device, physical_device)
	if !ok {
		fmt.eprintln("Failed to create command pool.")
		os.exit(1)
	}
	fmt.println("Command pool... OK")


	// Command buffer
	command_buffer: vk.CommandBuffer
	command_buffer, ok = create_command_buffer(device, command_pool)
	if !ok {
		fmt.eprintln("Failed to create command buffer.")
		os.exit(1)
	}
	fmt.println("Command buffer... OK")


	// Record command bufffer
	ok = record_command_buffer(command_buffer, swap_chain_images[0], swap_chain_image_views[0], swap_chain_extent, graphics_pipeline)
	if !ok {
		fmt.eprintln("Failed to record commands into buffer.")
		os.exit(1)
	}
	fmt.println("Record command buffer... OK")


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
	for !glfw.WindowShouldClose(window) && g_running {
		glfw.PollEvents()
	}
	//---------------------

	// Cleanup
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
	if swap_chain_image_views != nil {
		for image_view in swap_chain_image_views {
			vk.DestroyImageView(device, image_view, nil)
		}
		delete(swap_chain_image_views)
	}
	if swap_chain != 0 {
		vk.DestroySwapchainKHR(device, swap_chain, nil)
	}
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
