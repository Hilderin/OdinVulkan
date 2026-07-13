package main

import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"


createInstance :: proc() -> (vk.Instance, bool) {
	vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))

	appInfo: vk.ApplicationInfo
	appInfo.sType = vk.StructureType.APPLICATION_INFO
	appInfo.pApplicationName = "Instance creation"
	appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.pEngineName = "No Engine"
	appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
	appInfo.apiVersion = vk.API_VERSION_1_4

	createInfo: vk.InstanceCreateInfo
	createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO
	createInfo.pApplicationInfo = &appInfo

	extensions := glfw.GetRequiredInstanceExtensions()
	createInfo.enabledExtensionCount = u32(len(extensions))
	createInfo.ppEnabledExtensionNames = raw_data(extensions)

	createInfo.enabledLayerCount = 0

	result: vk.Result
	instance: vk.Instance
	result = vk.CreateInstance(&createInfo, nil, &instance)
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

	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	if (!glfw.Init()) {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}

	instance: vk.Instance
	result: bool
	instance, result = createInstance()
	if (!result) {
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
