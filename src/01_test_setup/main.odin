package main

import "core:fmt"
import "core:os"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

main :: proc() {
	fmt.println("Test setup")
	fmt.println("--------------------------")


	// Test GLFW...
	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	if (!glfw.Init()) {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	fmt.println("GLFW... OK!")

	// Test Vulkan SDK...
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	appInfo: vk.ApplicationInfo
	appInfo.sType = vk.StructureType.APPLICATION_INFO
	appInfo.pApplicationName = "Test setup"
	appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.pEngineName = "No Engine"
	appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.apiVersion = vk.API_VERSION_1_0

	createInfo: vk.InstanceCreateInfo
	createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO
	createInfo.pApplicationInfo = &appInfo
	createInfo.enabledLayerCount = 0
	result: vk.Result

	instance: vk.Instance
	result = vk.CreateInstance(&createInfo, nil, &instance)
	if result != vk.Result.SUCCESS {
		fmt.eprintln(
			"Failed to create Vulkan instance. Check if your hardware supports Vulkan and your Graphics Card drvier installation.",
		)
		os.exit(1)
	}
	vk.load_proc_addresses_instance(instance)
	fmt.println("Vulkan... OK!")

	// Vulkan SDK...
	if !check_ValidationLayerSupport() {
		fmt.eprintln(
			"Vulkan validation layers not available. The Vulkan SDK is not correctly installed. Be sure the 'VULKAN_SDK' environment variable is correctly. Refer to the Vulkan SFK installation procedure: https://vulkan.lunarg.com/doc/sdk/latest",
		)
	}
	fmt.println("Vulkan SDK... OK!")

	fmt.println()
	fmt.println("Good job, everything is setup correctly!")

}


check_ValidationLayerSupport :: proc() -> b32 {

	layerCount: u32
	vk.EnumerateInstanceLayerProperties(&layerCount, nil)
	availableLayers := make([]vk.LayerProperties, layerCount)
	vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))

	compare_strings :: proc(
		layerProperties: vk.LayerProperties,
		validation_string: cstring,
	) -> bool {
		// Cannot directly slice from "layerProperties.layerName
		bytes: [256]u8 = layerProperties.layerName
		builder := strings.clone_from_bytes(bytes[:])
		cbuilder := strings.clone_to_cstring(builder)
		return cbuilder == validation_string
	}

	for layerProperties in availableLayers {
		if compare_strings(layerProperties, "VK_LAYER_KHRONOS_validation") == true do return true
	}
	return false
}
