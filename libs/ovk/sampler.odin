package ovk

import vk "vendor:vulkan"

Sampler :: struct {
	device:     ^Device,
	vk_sampler: vk.Sampler,
}

Create_Sampler_Args :: struct {
	device: ^Device,
}

// Create a sampler
create_sampler :: proc(args: Create_Sampler_Args) -> (sampler: Sampler, err: Error) {

	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(args.device.physical_device.vk_physical_device, &props)

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		anisotropyEnable        = true,
		maxAnisotropy           = props.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0.0,
		minLod                  = 0.0,
		maxLod                  = vk.LOD_CLAMP_NONE,
	}

	check(vk.CreateSampler(args.device.vk_device, &sampler_info, nil, &sampler.vk_sampler), "Failed to create sampler!") or_return

	// Complete the struct
	sampler.device = args.device

	return
}

// Destroy the sampler
destroy_sampler :: proc(sampler: ^Sampler) {
	if sampler == nil || sampler.device == nil || sampler.device.vk_device == nil {
		return
	}

	if sampler.vk_sampler != 0 {
		vk.DestroySampler(sampler.device.vk_device, sampler.vk_sampler, nil)
	}
}
