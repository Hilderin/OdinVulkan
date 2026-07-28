package ovk

import vk "vendor:vulkan"

Fence :: struct {
	device:   ^Device,
	vk_fence: vk.Fence,
}

Create_Fences_Args :: struct {
	device: ^Device,
	flags:  vk.FenceCreateFlags,
}

// Create one fence
create_fence :: proc(args: Create_Fences_Args) -> (fence: Fence, err: Error) {

	fence_create_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = args.flags,
	}

	check(vk.CreateFence(args.device.vk_device, &fence_create_info, nil, &fence.vk_fence), "Failed to create a fence!") or_return

	// Complete struct
	fence.device = args.device

	return
}

// Create fences
create_fences :: proc(args: Create_Fences_Args, fence_count: u32) -> (fences: []Fence, err: Error) {
	fences = make([]Fence, fence_count)

	for i in 0 ..< fence_count {
		fences[i] = create_fence(args) or_return
	}

	return
}


// Destroy a fence. Not necessary if you plan to free fence pool.
destroy_fence :: proc(fence: ^Fence) {
	if fence == nil || fence.device == nil || fence.device.vk_device == nil {
		return
	}

	if fence.vk_fence != 0 {
		vk.DestroyFence(fence.device.vk_device, fence.vk_fence, nil)
	}
}

// Destroy fences
destroy_fences :: proc(fences: []Fence) {
	for &fence in fences {
		destroy_fence(&fence)
	}

	delete(fences)
}

// Wait for fence
wait_for_fence :: proc(fence: ^Fence) -> (err: Error) {

	check(vk.WaitForFences(fence.device.vk_device, 1, &fence.vk_fence, true, max(u64)), "Failed to wait for fence!") or_return

	return
}

// Reset the fence to a non signaled state.
reset_fence :: proc(fence: ^Fence) -> (err: Error) {

	check(vk.ResetFences(fence.device.vk_device, 1, &fence.vk_fence), "Failed to reset fence!") or_return

	return
}
