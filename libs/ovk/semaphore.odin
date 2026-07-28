package ovk

import vk "vendor:vulkan"

Semaphore :: struct {
	device:       ^Device,
	vk_semaphore: vk.Semaphore,
}

Create_Semaphores_Args :: struct {
	device: ^Device,
}

// Create one semaphore
create_semaphore :: proc(args: Create_Semaphores_Args) -> (semaphore: Semaphore, err: Error) {

	semaphore_create_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
		flags = {},
	}

	check(vk.CreateSemaphore(args.device.vk_device, &semaphore_create_info, nil, &semaphore.vk_semaphore), "Failed to create a semaphore!") or_return

	// Complete struct
	semaphore.device = args.device

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
