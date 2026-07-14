package main

import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"

main :: proc() {
	fmt.println("Test setup")
	fmt.println("--------------------------")

	// Test GLFW...
	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	fmt.println("GLFW... OK!")

	// Test Vulkan SDK...
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = "Test setup",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName        = "No Engine",
		engineVersion      = vk.MAKE_VERSION(1, 0, 0),
		apiVersion         = vk.API_VERSION_1_0,
	}

	create_info := vk.InstanceCreateInfo {
		sType             = .INSTANCE_CREATE_INFO,
		pApplicationInfo  = &app_info,
		enabledLayerCount = 0,
	}

	instance: vk.Instance
	result := vk.CreateInstance(&create_info, nil, &instance)
	if result != vk.Result.SUCCESS {
		fmt.eprintln("Failed to create Vulkan instance. Check if your hardware supports Vulkan and your Graphics Card drvier installation.")
		os.exit(1)
	}
	vk.load_proc_addresses_instance(instance)
	fmt.println("Vulkan... OK!")

	// Check to find VULKAN_SDK path
	vulkan_sdk, found := os.lookup_env("VULKAN_SDK", context.allocator)
	defer delete(vulkan_sdk)
	if !found || vulkan_sdk == "" {
		fmt.eprintln("VULKAN_SDK environment variable is not set. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest")
		os.exit(1)
	}
	fmt.println("Vulkan SDK path... OK!")

	// Vulkan SDK validation layers...
	if !check_validation_layer_support() {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
		os.exit(1)
	}
	fmt.println("Vulkan validation layers... OK!")

	// Check to find the slang compiler (slangc)
	slangc_path := fmt.tprintf("%s/bin/slangc", vulkan_sdk)
	if !os.exists(slangc_path) {
		fmt.eprintfln(
			"slangc executable not found: '%q'. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SDK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
			slangc_path,
		)
		os.exit(1)
	}
	fmt.println("Slang compiler found... OK!")

	fmt.println()
	fmt.println("Good job, everything is setup correctly!")

}


check_validation_layer_support :: proc() -> b32 {
	layer_count: u32
	vk.EnumerateInstanceLayerProperties(&layer_count, nil)
	available_layers := make([]vk.LayerProperties, layer_count)
	defer delete(available_layers)
	vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

	for &layer in available_layers {
		if cstring(&layer.layerName[0]) == "VK_LAYER_KHRONOS_validation" {
			return true
		}
	}
	return false
}
