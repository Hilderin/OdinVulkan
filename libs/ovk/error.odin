package ovk

import "base:runtime"

import vk "vendor:vulkan"

General_Error :: struct {
	message: string,
}

Vulkan_Error :: struct {
	result:  vk.Result,
	message: string,
	loc:     runtime.Source_Code_Location,
}


Error :: union {
	General_Error,
	Vulkan_Error,
}
