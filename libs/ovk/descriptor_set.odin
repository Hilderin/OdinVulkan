package ovk


import vk "vendor:vulkan"

Descriptor_Set :: struct {
	descriptor_pool:   ^Descriptor_Pool,
	descriptor_layout: ^Descriptor_Set_Layout,
	vk_descriptor_set: vk.DescriptorSet,
}

Create_Descriptor_Sets_Args :: struct {
	descriptor_pool:       ^Descriptor_Pool,
	descriptor_set_layout: ^Descriptor_Set_Layout,
	descriptor_count:      u32,
}

// Create descriptor sets
create_descriptor_sets :: proc(args: Create_Descriptor_Sets_Args) -> (descriptor_sets: []Descriptor_Set, err: Error) {
	descriptor_layouts := make([]vk.DescriptorSetLayout, args.descriptor_count)
	defer delete(descriptor_layouts)

	local_descriptor_sets := make([]vk.DescriptorSet, args.descriptor_count)

	// Same descriptor layout for each
	for i in 0 ..< args.descriptor_count {
		descriptor_layouts[i] = args.descriptor_set_layout.vk_descriptor_set_layout
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = args.descriptor_pool.vk_descriptor_pool,
		descriptorSetCount = args.descriptor_count,
		pSetLayouts        = raw_data(descriptor_layouts),
	}

	check(vk.AllocateDescriptorSets(args.descriptor_pool.device.vk_device, &alloc_info, raw_data(local_descriptor_sets)), "Failed to allocate descriptor sets!") or_return

	descriptor_sets = make([]Descriptor_Set, args.descriptor_count)
	for i in 0 ..< args.descriptor_count {
		descriptor_sets[i].descriptor_pool = args.descriptor_pool
		descriptor_sets[i].descriptor_layout = args.descriptor_set_layout
		descriptor_sets[i].vk_descriptor_set = local_descriptor_sets[i]
	}

	return
}
