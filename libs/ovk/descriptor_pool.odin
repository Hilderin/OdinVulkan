package ovk

import vk "vendor:vulkan"


Descriptor_Pool :: struct {
	device:             ^Device,
	vk_descriptor_pool: vk.DescriptorPool,
	flags:              vk.DescriptorPoolCreateFlags,
}

Create_Descriptor_Pool_Args :: struct {
	device:     ^Device,
	pool_sizes: []vk.DescriptorPoolSize,
	max_sets:   u32,
	flags:      vk.DescriptorPoolCreateFlags,
}

// Create a descriptor pool
create_descriptor_pool :: proc(args: Create_Descriptor_Pool_Args) -> (descriptor_pool: Descriptor_Pool, err: Error) {
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		poolSizeCount = u32(len(args.pool_sizes)),
		pPoolSizes    = raw_data(args.pool_sizes),
		maxSets       = args.max_sets,
		flags         = args.flags,
	}

	check(vk.CreateDescriptorPool(args.device.vk_device, &pool_info, nil, &descriptor_pool.vk_descriptor_pool), "Failed to create descriptor pool!") or_return

	descriptor_pool.device = args.device
	descriptor_pool.flags = args.flags

	return
}

// Destroy a descriptor pool
destroy_descriptor_pool :: proc(descriptor_pool: ^Descriptor_Pool) {
	if descriptor_pool == nil {
		return
	}

	if descriptor_pool.device != nil && descriptor_pool.device.vk_device != nil && descriptor_pool.vk_descriptor_pool != 0 {
		vk.DestroyDescriptorPool(descriptor_pool.device.vk_device, descriptor_pool.vk_descriptor_pool, nil)
	}
}
