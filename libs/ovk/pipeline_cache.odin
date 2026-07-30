package ovk

import vk "vendor:vulkan"

Pipeline_Cache :: struct {
	device:            ^Device,
	vk_pipeline_cache: vk.PipelineCache,
}

Create_Pipeline_Cache_Args :: struct {
	device:       ^Device,
	initial_data: []u8,
}

// Create a pipeline cache
create_pipeline_cache :: proc(args: Create_Pipeline_Cache_Args) -> (pipeline_cache: Pipeline_Cache, err: Error) {

	create_cache_info := vk.PipelineCacheCreateInfo {
		sType           = .PIPELINE_CACHE_CREATE_INFO,
		initialDataSize = len(args.initial_data),
		pInitialData    = raw_data(args.initial_data),
	}

	check(vk.CreatePipelineCache(args.device.vk_device, &create_cache_info, nil, &pipeline_cache.vk_pipeline_cache), "Failed to create pipeline cache.") or_return

	// Complete the struct
	pipeline_cache.device = args.device

	return
}

// Destroy a pipeline cache
destroy_pipeline_cache :: proc(pipeline_cache: ^Pipeline_Cache) {
	if pipeline_cache == nil || pipeline_cache.device == nil || pipeline_cache.device.vk_device == nil {
		return
	}

	if pipeline_cache.vk_pipeline_cache != 0 {
		vk.DestroyPipelineCache(pipeline_cache.device.vk_device, pipeline_cache.vk_pipeline_cache, nil)
	}
}

// Get the data from the pipeline cache
get_pipeline_cache_data :: proc(pipeline_cache: ^Pipeline_Cache) -> (data: []u8, err: Error) {

	data_size: int
	check(
		vk.GetPipelineCacheData(pipeline_cache.device.vk_device, pipeline_cache.vk_pipeline_cache, &data_size, nil),
		"Failed to read the data size in the pipeline cache.",
	) or_return

	data = make([]u8, data_size)
	check(
		vk.GetPipelineCacheData(pipeline_cache.device.vk_device, pipeline_cache.vk_pipeline_cache, &data_size, raw_data(data)),
		"Failed to read the data in the pipeline cache.",
	) or_return

	return
}
