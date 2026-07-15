package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:reflect"

import "vendor:glfw"
import vk "vendor:vulkan"

// Globals needed for debug messenger cleanup.
debug_messenger: vk.DebugUtilsMessengerEXT = {}

// Debug level - controls which severities are enabled and printed.
debug_level: vk.DebugUtilsMessageSeverityFlagsEXT = {.WARNING, .ERROR}

// Required validation layers.
validation_layers := []cstring{"VK_LAYER_KHRONOS_validation"}

// Required extensions
required_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}

// Manage the escape key exit.
running: bool = true


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
	if .ERROR in messageSeverity && .ERROR in debug_level {
		fmt.eprintfln("[validation ERROR] %s", pCallbackData.pMessage)
	} else if .WARNING in messageSeverity && .WARNING in debug_level {
		fmt.eprintfln("[validation WARNING] %s", pCallbackData.pMessage)
	} else if .INFO in messageSeverity && .INFO in debug_level {
		fmt.println("[validation INFO]", pCallbackData.pMessage)
	} else if .VERBOSE in messageSeverity && .VERBOSE in debug_level {
		fmt.printfln("[validation VERBOSE] %s", pCallbackData.pMessage)
	}
	return false
}


create_instance :: proc() -> vk.Instance {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
	if !are_layers_supported(validation_layers) {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		os.exit(1)
	}

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Odin Vulkan Tutorial",
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
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = debug_level,
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = debug_callback,
		pUserData       = nil,
	}

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = u32(len(ext_names)),
		ppEnabledExtensionNames = raw_data(ext_names[:]),
		enabledLayerCount       = u32(len(validation_layers)),
		ppEnabledLayerNames     = raw_data(validation_layers),
		pNext                   = &debug_create_info,
	}

	instance: vk.Instance
	vk_check(vk.CreateInstance(&create_info, nil, &instance), "failed to create instance!")
	vk.load_proc_addresses_instance(instance)

	if vk.CreateDebugUtilsMessengerEXT != nil {
		vk_check(vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &debug_messenger), "failed to create debug messenger!")
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
		sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
	}
	extended_dynamic_state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
	}
	vulkan13_features.pNext = &extended_dynamic_state_features

	vulkan11_features := vk.PhysicalDeviceVulkan11Features {
		sType = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext = &vulkan13_features,
	}

	features2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
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
			"  %q - apiVersion=%d.%d.%d, < 1.4 (skipped)",
			name,
			vk.API_VERSION_MAJOR(props.apiVersion),
			vk.API_VERSION_MINOR(props.apiVersion),
			vk.API_VERSION_PATCH(props.apiVersion),
		)
		return -1
	}

	// Must have at least a graphics queue family.
	if _, ok := find_queue_families(device, {.GRAPHICS}, surface); !ok {
		fmt.printfln("  %q - no graphics queue (skipped)", name)
		return -1
	}

	// Must support all required device extensions.
	ext_count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, nil)
	available_exts := make([]vk.ExtensionProperties, ext_count)
	defer delete(available_exts)
	vk.EnumerateDeviceExtensionProperties(device, nil, &ext_count, raw_data(available_exts))

	for req_ext in required_extensions {
		found := false
		for &ext in available_exts {
			if cstring(&ext.extensionName[0]) == req_ext {
				found = true
				break
			}
		}
		if !found {
			fmt.printfln("  %q - missing required extension %s (skipped)", name, req_ext)
			return -1
		}
	}

	vulkan11_f, vulkan13_f, ext_dynamic_f, _ := get_device_features(device)

	if !vulkan11_f.shaderDrawParameters {
		fmt.printfln("  %q - missing shaderDrawParameters (skipped)", name)
		return -1
	}
	if !vulkan13_f.dynamicRendering {
		fmt.printfln("  %q - missing dynamicRendering (skipped)", name)
		return -1
	}
	if !ext_dynamic_f.extendedDynamicState {
		fmt.printfln("  %q - missing extendedDynamicState (skipped)", name)
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

	fmt.printfln("  %q - type=%v, score=%d", name, props.deviceType, score)
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
		sType            = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = queue_index,
		queueCount       = 1,
		pQueuePriorities = &queue_priority,
	}

	device_feature_extended_dynamic_state := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType                = .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		extendedDynamicState = true,
	}

	device_feature_vulkan13 := vk.PhysicalDeviceVulkan13Features {
		sType            = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
		dynamicRendering = true,
		pNext            = &device_feature_extended_dynamic_state,
	}

	device_feature_vulkan11 := vk.PhysicalDeviceVulkan11Features {
		sType                = .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		shaderDrawParameters = true,
		pNext                = &device_feature_vulkan13,
	}

	device_feature_2 := vk.PhysicalDeviceFeatures2 {
		sType = .PHYSICAL_DEVICE_FEATURES_2,
		pNext = &device_feature_vulkan11,
	}

	create_info := vk.DeviceCreateInfo {
		sType                   = .DEVICE_CREATE_INFO,
		pQueueCreateInfos       = &queue_create_info,
		queueCreateInfoCount    = 1,
		enabledExtensionCount   = u32(len(required_extensions)),
		ppEnabledExtensionNames = raw_data(required_extensions),
		pNext                   = &device_feature_2,
	}

	device: vk.Device
	vk_check(vk.CreateDevice(physical_device, &create_info, nil, &device), "Failed to create logical device!")

	queue: vk.Queue
	vk.GetDeviceQueue(device, queue_index, 0, &queue)

	return device, queue
}


create_window :: proc() -> glfw.WindowHandle {
	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(512, 512, "My first window", nil, nil)
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
	if 0 < capabilities.maxImageCount && capabilities.maxImageCount < min_image_count {
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


create_swap_chain :: proc(physical_device: vk.PhysicalDevice, device: vk.Device, surface: vk.SurfaceKHR, window: glfw.WindowHandle) -> vk.SwapchainKHR {
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
	vk_check(vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain), "Failed to create swap chain!")

	return swap_chain
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

main :: proc() {
	fmt.println("Odin Vulkan Tutorial")
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
	device, _ := create_logical_device(physical_device, surface)
	fmt.println("Logical device... OK")

	// Create swap chain
	swap_chain := create_swap_chain(physical_device, device, surface, window)
	fmt.println("Swap chain... OK")

	// Get swap chain images
	swap_chain_images := get_swap_chain_images(device, swap_chain)
	defer delete(swap_chain_images)
	fmt.printfln("Swap chain images [%d]... OK", len(swap_chain_images))

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
	glfw.SetKeyCallback(window, key_callback)
	for !glfw.WindowShouldClose(window) && running {
		glfw.PollEvents()
	}
	//---------------------

	// Cleanup
	if swap_chain != 0 {
		vk.DestroySwapchainKHR(device, swap_chain, nil)
	}
	if device != nil {
		vk.DestroyDevice(device, nil)
	}
	if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
		vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
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
