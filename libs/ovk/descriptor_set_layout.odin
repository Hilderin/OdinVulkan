package ovk

import vk "vendor:vulkan"


Descriptor_Set_Layout :: struct {
	device:                   ^Device,
	vk_descriptor_set_layout: vk.DescriptorSetLayout,
}

Create_Descriptor_Set_Layout_Args :: struct {
	device:   ^Device,
	bindings: []vk.DescriptorSetLayoutBinding,
}

// Create descriptor set layout
create_descriptor_set_layout :: proc(args: Create_Descriptor_Set_Layout_Args) -> (descriptor_set_layout: Descriptor_Set_Layout, err: Error) {
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = u32(len(args.bindings)),
		pBindings    = raw_data(args.bindings),
	}

	check(
		vk.CreateDescriptorSetLayout(args.device.vk_device, &layout_info, nil, &descriptor_set_layout.vk_descriptor_set_layout),
		"Failed to create descriptor set layout!",
	) or_return

	descriptor_set_layout.device = args.device

	return
}

// Destroy a descriptor set layout
destroy_descriptor_set_layout :: proc(descriptor_set_layout: ^Descriptor_Set_Layout) {
	if descriptor_set_layout == nil {
		return
	}

	if descriptor_set_layout.device != nil && descriptor_set_layout.device.vk_device != nil && descriptor_set_layout.vk_descriptor_set_layout != 0 {
		vk.DestroyDescriptorSetLayout(descriptor_set_layout.device.vk_device, descriptor_set_layout.vk_descriptor_set_layout, nil)
	}
}
