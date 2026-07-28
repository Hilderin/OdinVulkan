package ovk

import "core:fmt"

import vk "vendor:vulkan"

Descriptor_Set :: struct {
	descriptor_pool:   ^Descriptor_Pool,
	descriptor_layout: ^Descriptor_Set_Layout,
	vk_descriptor_set: vk.DescriptorSet,
}

Create_Descriptor_Sets_Args :: struct {
	descriptor_pool:       ^Descriptor_Pool,
	descriptor_set_layout: ^Descriptor_Set_Layout,
}

// Create one descriptor set
create_descriptor_set :: proc(args: Create_Descriptor_Sets_Args) -> (descriptor_set: Descriptor_Set, err: Error) {

	descriptor_sets := create_descriptor_sets(args, 1) or_return
	descriptor_set = descriptor_sets[0]
	delete(descriptor_sets)

	return
}

// Create descriptor sets
create_descriptor_sets :: proc(args: Create_Descriptor_Sets_Args, descriptor_count: u32) -> (descriptor_sets: []Descriptor_Set, err: Error) {
	descriptor_layouts := make([]vk.DescriptorSetLayout, descriptor_count)
	defer delete(descriptor_layouts)

	local_descriptor_sets := make([]vk.DescriptorSet, descriptor_count)

	// Same descriptor layout for each
	for i in 0 ..< descriptor_count {
		descriptor_layouts[i] = args.descriptor_set_layout.vk_descriptor_set_layout
	}

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = args.descriptor_pool.vk_descriptor_pool,
		descriptorSetCount = descriptor_count,
		pSetLayouts        = raw_data(descriptor_layouts),
	}

	check(vk.AllocateDescriptorSets(args.descriptor_pool.device.vk_device, &alloc_info, raw_data(local_descriptor_sets)), "Failed to allocate descriptor sets!") or_return

	descriptor_sets = make([]Descriptor_Set, descriptor_count)
	for i in 0 ..< descriptor_count {
		descriptor_sets[i].descriptor_pool = args.descriptor_pool
		descriptor_sets[i].descriptor_layout = args.descriptor_set_layout
		descriptor_sets[i].vk_descriptor_set = local_descriptor_sets[i]
	}

	return
}


// Destroy a descriptor set. Not necessary if you plan to free descriptor set pool.
destroy_descriptor_set :: proc(descriptor_set: ^Descriptor_Set) {
	if descriptor_set == nil || descriptor_set.descriptor_pool == nil || descriptor_set.descriptor_pool.device == nil || descriptor_set.descriptor_pool.device.vk_device == nil {
		return
	}

	if .FREE_DESCRIPTOR_SET in descriptor_set.descriptor_pool.flags {
		vk.FreeDescriptorSets(descriptor_set.descriptor_pool.device.vk_device, descriptor_set.descriptor_pool.vk_descriptor_pool, 1, &descriptor_set.vk_descriptor_set)
	}
}

// Destroy descriptor sets
destroy_descriptor_sets :: proc(descriptor_sets: []Descriptor_Set) {
	for &descriptor_set in descriptor_sets {
		destroy_descriptor_set(&descriptor_set)
	}

	delete(descriptor_sets)
}

Descriptor_Write :: struct {
	binding: u32,
	type:    vk.DescriptorType,
	image:   ^Image,
	sampler: ^Sampler,
	buffer:  ^Buffer,
	offset:  u64,
	size:    u64,
}

// Update a descriptor set with a buffer.
update_descriptor_set :: proc(descriptor_set: ^Descriptor_Set, descriptor_writes: []Descriptor_Write) -> (err: Error) {
	if len(descriptor_writes) == 0 {
		return
	}

	vk_descriptor_writes := make([]vk.WriteDescriptorSet, u32(len(descriptor_writes)))
	defer delete(vk_descriptor_writes)

	buffer_infos: [dynamic]vk.DescriptorBufferInfo
	defer delete(buffer_infos)

	image_infos: [dynamic]vk.DescriptorImageInfo
	defer delete(image_infos)

	for &write, i in descriptor_writes {

		if write.type == .UNIFORM_BUFFER {
			// Buffer
			assert(write.buffer != nil, "Missing buffer for write type %s", write.type) or_return

			append(
				&buffer_infos,
				vk.DescriptorBufferInfo {
					buffer = write.buffer.vk_buffer,
					offset = vk.DeviceSize(write.offset),
					range = vk.DeviceSize(write.size > 0 ? write.size : write.buffer.size),
				},
			)

			vk_descriptor_writes[i] = {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = descriptor_set.vk_descriptor_set,
				dstBinding      = write.binding,
				dstArrayElement = 0,
				descriptorType  = write.type,
				descriptorCount = 1,
				pBufferInfo     = &buffer_infos[len(buffer_infos) - 1],
			}
		} else if write.type == .COMBINED_IMAGE_SAMPLER {
			// Combined image and sampler
			assert(write.image != nil, "Missing image for write type %s", write.type) or_return
			assert(write.sampler != nil, "Missing sampler for write type %s", write.type) or_return

			append(&image_infos, vk.DescriptorImageInfo{imageLayout = .SHADER_READ_ONLY_OPTIMAL, imageView = write.image.vk_image_view, sampler = write.sampler.vk_sampler})

			vk_descriptor_writes[i] = {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = descriptor_set.vk_descriptor_set,
				dstBinding      = write.binding,
				dstArrayElement = 0,
				descriptorType  = write.type,
				descriptorCount = 1,
				pImageInfo      = &image_infos[len(image_infos) - 1],
			}
		} else {
			err = General_Error{fmt.tprintf("Write type not supported: %s", write.type)}
			return
		}

	}

	vk.UpdateDescriptorSets(descriptor_set.descriptor_pool.device.vk_device, u32(len(descriptor_writes)), raw_data(vk_descriptor_writes), 0, nil)

	return

}
