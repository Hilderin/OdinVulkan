package ovk

import "core:strings"

import vk "vendor:vulkan"

// Set the debug name for a Vulkan object
set_debug_name :: proc {
	set_debug_name_device,
	set_debug_name_instance,
	set_debug_name_physical_device,
	set_debug_name_queue,
	set_debug_name_buffer,
	set_debug_name_image,
	set_debug_name_sampler,
	set_debug_name_shader,
	set_debug_name_command_buffer,
	set_debug_name_command_pool,
	set_debug_name_fence,
	set_debug_name_semaphore,
	set_debug_name_descriptor_set_layout,
	set_debug_name_descriptor_pool,
	set_debug_name_descriptor_set,
	set_debug_name_pipeline_cache,
	set_debug_name_graphics_pipeline,
	set_debug_name_swap_chain,
	set_debug_name_window,
}

// Add a debug label in the command buffer
cmd_begin_debug_label :: proc(command_buffer: ^Command_Buffer, label_name: string, color: color4) {

	cname := strings.clone_to_cstring(label_name)
	defer delete(cname)

	begin_info := vk.DebugUtilsLabelEXT {
		sType      = .DEBUG_UTILS_LABEL_EXT,
		pLabelName = cname,
		color      = color,
	}

	vk.CmdBeginDebugUtilsLabelEXT(command_buffer.vk_command_buffer, &begin_info)
}

// End a debug label in the command buffer
cmd_end_debug_label :: proc(command_buffer: ^Command_Buffer) {
	vk.CmdEndDebugUtilsLabelEXT(command_buffer.vk_command_buffer)
}

// Internal helper method to set a debug name
@(private = "file")
set_debug_name_internal :: proc(device: vk.Device, object_handle: u64, object_type: vk.ObjectType, object_name: string) -> (err: Error) {

	cname := strings.clone_to_cstring(object_name)
	defer delete(cname)

	debug_info := vk.DebugUtilsObjectNameInfoEXT {
		sType        = .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
		objectHandle = object_handle,
		objectType   = object_type,
		pObjectName  = cname,
	}

	check(vk.SetDebugUtilsObjectNameEXT(device, &debug_info), "Failed to set the debug object name") or_return

	return
}

@(private = "file")
set_debug_name_device :: proc(device: ^Device, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(uintptr(device.vk_device)), .DEVICE, object_name)
}

@(private = "file")
set_debug_name_instance :: proc(device: ^Device, instance: ^Instance, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(uintptr(instance.vk_instance)), .INSTANCE, object_name)
}

@(private = "file")
set_debug_name_physical_device :: proc(device: ^Device, physical_device: ^Physical_Device, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(uintptr(physical_device.vk_physical_device)), .PHYSICAL_DEVICE, object_name)
}

@(private = "file")
set_debug_name_queue :: proc(device: ^Device, queue: ^Queue, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(uintptr(queue.vk_queue)), .QUEUE, object_name)
}

@(private = "file")
set_debug_name_buffer :: proc(device: ^Device, buffer: ^Buffer, object_name: string) -> (err: Error) {
	set_debug_name_internal(device.vk_device, u64(buffer.vk_buffer), .BUFFER, object_name) or_return

	if buffer.vk_device_memory != 0 {
		memory_name := strings.concatenate({object_name, " (memory)"})
		defer delete(memory_name)
		set_debug_name_internal(device.vk_device, u64(buffer.vk_device_memory), .DEVICE_MEMORY, memory_name) or_return
	}

	return
}

@(private = "file")
set_debug_name_image :: proc(device: ^Device, image: ^Image, object_name: string) -> (err: Error) {
	set_debug_name_internal(device.vk_device, u64(image.vk_image), .IMAGE, object_name) or_return

	if image.vk_image_view != 0 {
		image_view_name := strings.concatenate({object_name, " (view)"})
		defer delete(image_view_name)
		set_debug_name_internal(device.vk_device, u64(image.vk_image_view), .IMAGE_VIEW, image_view_name) or_return
	}

	if image.vk_device_memory != 0 {
		memory_name := strings.concatenate({object_name, " (memory)"})
		defer delete(memory_name)
		set_debug_name_internal(device.vk_device, u64(image.vk_device_memory), .DEVICE_MEMORY, memory_name) or_return
	}

	return
}

@(private = "file")
set_debug_name_sampler :: proc(device: ^Device, sampler: ^Sampler, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(sampler.vk_sampler), .SAMPLER, object_name)
}

@(private = "file")
set_debug_name_shader :: proc(device: ^Device, shader: ^Shader, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(shader.vk_shader_module), .SHADER_MODULE, object_name)
}

@(private = "file")
set_debug_name_command_buffer :: proc(device: ^Device, command_buffer: ^Command_Buffer, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(uintptr(command_buffer.vk_command_buffer)), .COMMAND_BUFFER, object_name)
}

@(private = "file")
set_debug_name_command_pool :: proc(device: ^Device, command_pool: ^Command_Pool, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(command_pool.vk_command_pool), .COMMAND_POOL, object_name)
}

@(private = "file")
set_debug_name_fence :: proc(device: ^Device, fence: ^Fence, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(fence.vk_fence), .FENCE, object_name)
}

@(private = "file")
set_debug_name_semaphore :: proc(device: ^Device, semaphore: ^Semaphore, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(semaphore.vk_semaphore), .SEMAPHORE, object_name)
}

@(private = "file")
set_debug_name_descriptor_set_layout :: proc(device: ^Device, descriptor_set_layout: ^Descriptor_Set_Layout, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(descriptor_set_layout.vk_descriptor_set_layout), .DESCRIPTOR_SET_LAYOUT, object_name)
}

@(private = "file")
set_debug_name_descriptor_pool :: proc(device: ^Device, descriptor_pool: ^Descriptor_Pool, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(descriptor_pool.vk_descriptor_pool), .DESCRIPTOR_POOL, object_name)
}

@(private = "file")
set_debug_name_descriptor_set :: proc(device: ^Device, descriptor_set: ^Descriptor_Set, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(descriptor_set.vk_descriptor_set), .DESCRIPTOR_SET, object_name)
}

@(private = "file")
set_debug_name_pipeline_cache :: proc(device: ^Device, pipeline_cache: ^Pipeline_Cache, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(pipeline_cache.vk_pipeline_cache), .PIPELINE_CACHE, object_name)
}

@(private = "file")
set_debug_name_graphics_pipeline :: proc(device: ^Device, graphics_pipeline: ^Graphics_Pipeline, object_name: string) -> (err: Error) {
	set_debug_name_internal(device.vk_device, u64(graphics_pipeline.vk_pipeline), .PIPELINE, object_name) or_return

	layout_name := strings.concatenate({object_name, " (layout)"})
	defer delete(layout_name)
	set_debug_name_internal(device.vk_device, u64(graphics_pipeline.vk_pipeline_layout), .PIPELINE_LAYOUT, layout_name) or_return

	return
}

@(private = "file")
set_debug_name_swap_chain :: proc(device: ^Device, swap_chain: ^Swap_Chain, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(swap_chain.vk_swap_chain), .SWAPCHAIN_KHR, object_name)
}

@(private = "file")
set_debug_name_window :: proc(device: ^Device, window: ^Window, object_name: string) -> (err: Error) {
	return set_debug_name_internal(device.vk_device, u64(window.surface), .SURFACE_KHR, object_name)
}
