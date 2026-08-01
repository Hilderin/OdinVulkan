package ovk

import vk "vendor:vulkan"

Semaphore :: struct {
	device:        ^Device,
	vk_semaphore:  vk.Semaphore,
	semaphore_type: vk.SemaphoreType,
}

Create_Semaphores_Args :: struct {
	device:        ^Device,
	semaphore_type: vk.SemaphoreType, // .BINARY by default, .TIMELINE for a timeline semaphore
}

// Create one semaphore
create_semaphore :: proc(args: Create_Semaphores_Args) -> (semaphore: Semaphore, err: Error) {

	// For timeline semaphores we must chain a SemaphoreTypeCreateInfo with the type and the initial value.
	semaphore_type_create_info := vk.SemaphoreTypeCreateInfo {
		sType         = .SEMAPHORE_TYPE_CREATE_INFO,
		semaphoreType = args.semaphore_type,
		initialValue  = 0,
	}

	semaphore_create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
		flags = {},
		pNext = &semaphore_type_create_info,
	}

	check(vk.CreateSemaphore(args.device.vk_device, &semaphore_create_info, nil, &semaphore.vk_semaphore), "Failed to create a semaphore!") or_return

	// Complete struct
	semaphore.device = args.device
	semaphore.semaphore_type = args.semaphore_type

	return
}

// Create semaphores
create_semaphores :: proc(args: Create_Semaphores_Args, semaphore_count: u32) -> (semaphores: []Semaphore, err: Error) {
	semaphores = make([]Semaphore, semaphore_count)

	for i in 0 ..< semaphore_count {
		semaphores[i] = create_semaphore(args) or_return
	}

	return
}


// Destroy a semaphore. Not necessary if you plan to free semaphore pool.
destroy_semaphore :: proc(semaphore: ^Semaphore) {
	if semaphore == nil || semaphore.device == nil || semaphore.device.vk_device == nil {
		return
	}

	if semaphore.vk_semaphore != 0 {
		vk.DestroySemaphore(semaphore.device.vk_device, semaphore.vk_semaphore, nil)
	}
}

// Destroy semaphores
destroy_semaphores :: proc(semaphores: []Semaphore) {
	for &semaphore in semaphores {
		destroy_semaphore(&semaphore)
	}

	delete(semaphores)
}

// Wait for a timeline semaphore to reach the given value.
// Only valid on a timeline semaphore, a binary semaphore has no counter.
wait_for_semaphore :: proc(semaphore: ^Semaphore, value: u64) -> (err: Error) {

	local_value := value

	wait_info := vk.SemaphoreWaitInfo {
		sType          = .SEMAPHORE_WAIT_INFO,
		semaphoreCount = 1,
		pSemaphores    = &semaphore.vk_semaphore,
		pValues        = &local_value,
	}

	check(vk.WaitSemaphores(semaphore.device.vk_device, &wait_info, max(u64)), "Failed to wait for semaphore!") or_return

	return
}

// Get the current counter value of a timeline semaphore.
// Only valid on a timeline semaphore, a binary semaphore has no counter.
get_semaphore_counter_value :: proc(semaphore: ^Semaphore) -> (value: u64, err: Error) {

	check(vk.GetSemaphoreCounterValue(semaphore.device.vk_device, semaphore.vk_semaphore, &value), "Failed to get the semaphore counter value!") or_return

	return
}
