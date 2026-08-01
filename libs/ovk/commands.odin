package ovk

import vk "vendor:vulkan"


// Record a CmdPipelineBarrier2 command to transition a image layout
cmd_transition_image_layout :: proc(
	command_buffer: ^Command_Buffer,
	image: ^Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	src_access_mask: vk.AccessFlags2,
	dst_access_mask: vk.AccessFlags2,
	src_stage_mask: vk.PipelineStageFlags2,
	dst_stage_mask: vk.PipelineStageFlags2,
	image_aspect_flags: vk.ImageAspectFlags,
	mip_levels: u32,
) {

	image_barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage_mask,
		srcAccessMask = src_access_mask,
		dstStageMask = dst_stage_mask,
		dstAccessMask = dst_access_mask,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image.vk_image,
		subresourceRange = vk.ImageSubresourceRange{aspectMask = image_aspect_flags, baseMipLevel = 0, levelCount = mip_levels, baseArrayLayer = 0, layerCount = 1},
	}

	dependency_info := vk.DependencyInfo {
		sType                    = .DEPENDENCY_INFO,
		dependencyFlags          = {},
		memoryBarrierCount       = 0,
		pMemoryBarriers          = nil,
		bufferMemoryBarrierCount = 0,
		pBufferMemoryBarriers    = nil,
		imageMemoryBarrierCount  = 1,
		pImageMemoryBarriers     = &image_barrier,
	}

	vk.CmdPipelineBarrier2(command_buffer.vk_command_buffer, &dependency_info)
}

// Record a CmdBeginRendering command
cmd_begin_rendering :: proc(command_buffer: ^Command_Buffer, color_image: ^Image, resolve_image: ^Image, swap_chain_extent: vk.Extent2D, depth_image: ^Image) {

	attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = color_image.vk_image_view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		// The multisampled color image is resolved (averaged) into the swapchain
		// image view at the end of rendering.
		resolveMode = {.AVERAGE},
		resolveImageView = resolve_image.vk_image_view,
		resolveImageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .STORE,
		clearValue = {color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
	}

	depth_attachment_info := vk.RenderingAttachmentInfo {
		sType = .RENDERING_ATTACHMENT_INFO,
		imageView = depth_image.vk_image_view,
		imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		loadOp = .CLEAR,
		storeOp = .DONT_CARE,
		clearValue = {depthStencil = {1.0, 0}},
	}

	render_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		layerCount = 1,
		renderArea = {extent = swap_chain_extent},
		pColorAttachments = &attachment_info,
		colorAttachmentCount = 1,
		pDepthAttachment = &depth_attachment_info,
	}
	vk.CmdBeginRendering(command_buffer.vk_command_buffer, &render_info)
}

// End the rendering
cmd_end_rendering :: proc(command_buffer: ^Command_Buffer) {
	vk.CmdEndRendering(command_buffer.vk_command_buffer)
}

// Record a CmdBindPipeline for a Graphics pipeline
cmd_bind_graphics_pipeline :: proc(command_buffer: ^Command_Buffer, pipeline: ^Graphics_Pipeline) {
	vk.CmdBindPipeline(command_buffer.vk_command_buffer, .GRAPHICS, pipeline.vk_pipeline)
}

// Record a CmdSetViewport
cmd_set_viewport :: proc(command_buffer: ^Command_Buffer, width: f32, height: f32) {
	viewport := vk.Viewport {
		x        = 0,
		y        = 0,
		width    = width,
		height   = height,
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(command_buffer.vk_command_buffer, 0, 1, &viewport)
}

// Record a CmdSetScissor
cmd_set_scissor :: proc(command_buffer: ^Command_Buffer, width: u32, height: u32) {
	scissor := vk.Rect2D {
		offset = {x = 0, y = 0},
		extent = {width, height},
	}
	vk.CmdSetScissor(command_buffer.vk_command_buffer, 0, 1, &scissor)
}

// Record a CmdBindVertexBuffers for one buffer
cmd_bind_vertex_buffer :: proc(command_buffer: ^Command_Buffer, first_binding: u32, binding_count: u32, vertex_buffer: ^Buffer, offset: u64) {
	offsets := vk.DeviceSize(offset)
	vk.CmdBindVertexBuffers(command_buffer.vk_command_buffer, first_binding, binding_count, &vertex_buffer.vk_buffer, &offsets)
}

// Record a CmdBindIndexBuffer for one buffer
cmd_bind_index_buffer :: proc(command_buffer: ^Command_Buffer, index_buffer: ^Buffer, offset: u64, index_type: vk.IndexType) {
	vk.CmdBindIndexBuffer(command_buffer.vk_command_buffer, index_buffer.vk_buffer, vk.DeviceSize(offset), index_type)
}

// Record a CmdBindDescriptorSets for one descriptorset
cmd_bind_graphics_descriptor_set :: proc(command_buffer: ^Command_Buffer, graphics_pipeline: ^Graphics_Pipeline, descriptor_set: ^Descriptor_Set) {
	vk.CmdBindDescriptorSets(command_buffer.vk_command_buffer, .GRAPHICS, graphics_pipeline.vk_pipeline_layout, 0, 1, &descriptor_set.vk_descriptor_set, 0, nil)
}

// Record a CmdDrawIndexed
cmd_draw_indexed :: proc(command_buffer: ^Command_Buffer, index_count: u32, instance_count: u32, first_index: u32, vertex_offset: i32, first_instance: u32) {
	vk.CmdDrawIndexed(command_buffer.vk_command_buffer, index_count, instance_count, first_index, vertex_offset, first_instance)
}

// Record a CmdCopyBuffer
cmd_copy_buffer :: proc(command_buffer: ^Command_Buffer, src_buffer: ^Buffer, src_offset: u64, dest_buffer: ^Buffer, dest_offset: u64, size: u64) {
	// Command to copy from staging buffer to destination buffer
	copy_region := vk.BufferCopy {
		srcOffset = vk.DeviceSize(src_offset),
		dstOffset = vk.DeviceSize(dest_offset),
		size      = vk.DeviceSize(size),
	}
	vk.CmdCopyBuffer(command_buffer.vk_command_buffer, src_buffer.vk_buffer, dest_buffer.vk_buffer, 1, &copy_region)
}

// Record a CmdCopyBufferToImage
cmd_copy_buffer_to_image :: proc(command_buffer: ^Command_Buffer, src_buffer: ^Buffer, dest_image: ^Image) {
	// Command to copy from staging buffer to destination buffer
	copy_region := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
		imageOffset = {0, 0, 0},
		imageExtent = {dest_image.width, dest_image.height, 1},
	}
	vk.CmdCopyBufferToImage(command_buffer.vk_command_buffer, src_buffer.vk_buffer, dest_image.vk_image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)
}

// Record CmdPipelineBarrier2 commands to generate mipmaps
cmd_generate_mipmaps :: proc(command_buffer: ^Command_Buffer, image: ^Image, format: vk.Format, width: u32, height: u32, mip_levels: u32) -> (err: Error) {

	// Check if image format supports linear blitting
	format_props: vk.FormatProperties
	vk.GetPhysicalDeviceFormatProperties(command_buffer.command_pool.device.physical_device.vk_physical_device, format, &format_props)

	assert(
		(format_props.optimalTilingFeatures & {.SAMPLED_IMAGE_FILTER_LINEAR}) == {.SAMPLED_IMAGE_FILTER_LINEAR},
		"Texture image format does not support linear blitting!",
	) or_return

	barrier := vk.ImageMemoryBarrier2 {
		sType               = .IMAGE_MEMORY_BARRIER_2,
		image               = image.vk_image,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		subresourceRange    = {{.COLOR}, 0, 1, 0, 1},
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}

	mip_width := width
	mip_height := height

	for i in 1 ..< mip_levels {
		barrier.subresourceRange.baseMipLevel = i - 1
		barrier.oldLayout = .TRANSFER_DST_OPTIMAL
		barrier.newLayout = .TRANSFER_SRC_OPTIMAL
		barrier.srcStageMask = {.TRANSFER}
		barrier.dstStageMask = {.TRANSFER}
		barrier.srcAccessMask = {.TRANSFER_WRITE}
		barrier.dstAccessMask = {.TRANSFER_READ}

		vk.CmdPipelineBarrier2(command_buffer.vk_command_buffer, &dependency_info)

		blit := vk.ImageBlit {
			srcOffsets     = {{0, 0, 0}, {i32(mip_width), i32(mip_height), 1}},
			srcSubresource = {{.COLOR}, i - 1, 0, 1},
			dstOffsets     = {{0, 0, 0}, {i32(mip_width > 1 ? mip_width / 2 : 1), i32(mip_height > 1 ? mip_height / 2 : 1), 1}},
			dstSubresource = {{.COLOR}, i, 0, 1},
		}


		vk.CmdBlitImage(command_buffer.vk_command_buffer, image.vk_image, .TRANSFER_SRC_OPTIMAL, image.vk_image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

		barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
		barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
		barrier.srcStageMask = {.TRANSFER}
		barrier.dstStageMask = {.FRAGMENT_SHADER}
		barrier.srcAccessMask = {.TRANSFER_READ}
		barrier.dstAccessMask = {.SHADER_READ}

		vk.CmdPipelineBarrier2(command_buffer.vk_command_buffer, &dependency_info)

		if mip_width > 1 {
			mip_width /= 2
		}
		if mip_height > 1 {
			mip_height /= 2
		}
	}

	barrier.subresourceRange.baseMipLevel = mip_levels - 1
	barrier.oldLayout = .TRANSFER_DST_OPTIMAL
	barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
	barrier.srcStageMask = {.TRANSFER}
	barrier.dstStageMask = {.FRAGMENT_SHADER}
	barrier.srcAccessMask = {.TRANSFER_WRITE}
	barrier.dstAccessMask = {.SHADER_READ}

	vk.CmdPipelineBarrier2(command_buffer.vk_command_buffer, &dependency_info)

	return
}
