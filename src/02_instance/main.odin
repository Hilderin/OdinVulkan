package main

import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"


create_instance :: proc() -> (vk.Instance, bool) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	app_info := vk.ApplicationInfo {
		sType = vk.StructureType.APPLICATION_INFO,
		pApplicationName = "Instance creation",
		applicationVersion = vk.MAKE_VERSION(1, 0, 0),
		pEngineName = "No Engine",
		engineVersion = vk.MAKE_VERSION(1, 0, 0),
		apiVersion = vk.API_VERSION_1_4,
	}

	extensions := glfw.GetRequiredInstanceExtensions()
	create_info := vk.InstanceCreateInfo {
		sType = vk.StructureType.INSTANCE_CREATE_INFO,
		pApplicationInfo = &app_info,
		enabledExtensionCount = u32(len(extensions)),
		ppEnabledExtensionNames = raw_data(extensions),
		enabledLayerCount = 0,
	}

	instance: vk.Instance
	result := vk.CreateInstance(&create_info, nil, &instance)
	if result != vk.Result.SUCCESS {
		fmt.eprintln("failed to create instance!")
		return nil, false
	}
	vk.load_proc_addresses_instance(instance)

	return instance, true
}


main :: proc() {
	fmt.println("Instance creation")
	fmt.println("-------------------------------------------")

	if !glfw.Init() {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	instance, ok := create_instance()
	if !ok {
		fmt.eprintln("Create instance failed.")
		os.exit(1)
	}
	fmt.println("Create instance... OK")

	fmt.println()
	fmt.println("Instance creation completed with success!")

	if instance != nil {
		vk.DestroyInstance(instance, nil)
	}
}
