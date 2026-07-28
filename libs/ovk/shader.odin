package ovk

import "core:slice"

import vk "vendor:vulkan"

Shader :: struct {
	device:           ^Device,
	vk_shader_module: vk.ShaderModule,
	entry_points:     []string,
}


Create_Shader_Args :: struct {
	device:       ^Device,
	slang_path:   string,
	entry_points: []string,
}


// Create a shader
create_shader :: proc(args: Create_Shader_Args) -> (shader: Shader, err: Error) {
	spv := compile_slang_shader(args.slang_path, args.entry_points) or_return
	defer delete(spv)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(spv),
		pCode    = raw_data(slice.reinterpret([]u32, spv)), // Needs to be a pointer to u32
	}

	check(vk.CreateShaderModule(args.device.vk_device, &create_info, nil, &shader.vk_shader_module), "Failed to create shader module!") or_return

	// Complete the struct
	shader.device = args.device
	shader.entry_points = args.entry_points

	return
}

destroy_shader :: proc(shader: ^Shader) {
	if shader == nil {
		return
	}

	if shader.device != nil && shader.device.vk_device != nil && shader.vk_shader_module != 0 {
		vk.DestroyShaderModule(shader.device.vk_device, shader.vk_shader_module, nil)
	}
}
