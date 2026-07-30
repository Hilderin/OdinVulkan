---
title: 33 - Pipeline Cache
nav_order: 35
---

# 33 - Pipeline Cache

The graphics pipeline is one of the heaviest Vulkan objects to create. Internally the driver compiles your shaders, optimizes the fixed-function state against the GPU's instruction set, and runs whatever heuristics it has for laying out registers and threads. On a cold start that work happens from scratch. The **pipeline cache** gives you a way to serialize the driver's internal representation to disk so the next run can skip most of that work and go straight to "load the compiled blob".

The full source for this step lives in [src/33_pipeline_cache/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/33_pipeline_cache/main.odin).

---

## Objectives

- Create a `vk.PipelineCache` object, optionally seeded with data from a previous run.
- Pass it to `CreateGraphicsPipelines` so the driver can reuse previously compiled state.
- Read the cache data back after pipeline creation and write it to disk for the next launch.
- Measure pipeline creation time with and without a warm cache so you can see the difference.

---

## Concepts

### What the cache stores

A pipeline cache is an opaque blob of driver-specific data. It caches the internal compilation results of pipeline creation: shader compilation, state optimization, and hardware-specific layout decisions. The same cache can speed up creation of multiple pipelines if they share shaders or state.

The cache is **not portable** between driver versions, GPU models, or even different driver releases. If the cache data is stale or invalid, Vulkan silently ignores it and starts fresh. There's no error, no validation warning - the driver just treats it as an empty cache. This is why the code saves the cache back to disk after every pipeline creation: the new data always reflects the current driver.

### The two Vulkan calls

- `vkCreatePipelineCache` - creates a cache object. You give it an optional `initialData` blob from a previous save. Pass `0` / `nil` for a cold start.
- `vkGetPipelineCacheData` - reads the cache data back as a `[]u8` that you can write to disk. You call it once to get the size, allocate, and call it again to fill the buffer.
- `vkDestroyPipelineCache` - standard cleanup for the cache handle.
- `vkCreateGraphicsPipelines` (and `vkCreateComputePipelines`) take an optional `VkPipelineCache` handle. Pass `0` to skip caching.

You don't *need* a pipeline cache for correctness. Pipelines work fine without one. The cache is purely a performance optimization for startup time.

---

## Implementation

### `libs/ovk/pipeline_cache.odin`

This is the `ovk` wrapper. It's a small file because the Vulkan API for pipeline caches is straightforward.

```c
Pipeline_Cache :: struct {
    device:            ^Device,
    vk_pipeline_cache: vk.PipelineCache,
}
```

`create_pipeline_cache :: proc(args: Create_Pipeline_Cache_Args) -> (Pipeline_Cache, Error)` builds a `VkPipelineCacheCreateInfo`. The `initial_data` field is `[]u8`; when it's nil or empty (first run, no disk cache), `len` is zero and `raw_data` is null, which Vulkan accepts as "no seed data".

`get_pipeline_cache_data` does the two-call pattern you've seen elsewhere in Vulkan: first call with `pData = nil` to get the size, allocate with `make`, second call to fill the buffer. The caller is responsible for `delete`-ing the returned slice.

`destroy_pipeline_cache` guards against nil handles the same as every other `ovk` destroy proc.

### Integration in `create_graphics_pipeline`

The `Create_Graphics_Pipeline_Args` struct (`libs/ovk/graphics_pipeline.odin:25`) has a `pipeline_cache: ^Pipeline_Cache` field. Inside the proc the handle is extracted:

```c
pipeline_cache := args.pipeline_cache != nil ? args.pipeline_cache.vk_pipeline_cache : 0
```

If no cache is provided (nil pointer), the fallback is `0` (VK_NULL_HANDLE), which tells the driver to skip caching.

### Loading and saving in `init_app`

The code in `main.odin:127-168` follows a save/load cycle:

1. **Check if a cache file exists on disk.** If it does, read it into a `[]u8` using the temp allocator - we only need the data until the cache object is created, so temp is fine.

2. **Create the pipeline cache** seeded with that data (or nil for the first run).

3. **Create the graphics pipeline**, passing `&app.pipeline_cache` as the cache. This is the same `create_graphics_pipeline` call from previous steps; the only difference is that the driver now has a cache to work with.

4. **Read the cache data back** with `get_pipeline_cache_data`. The driver may have added new entries or updated existing ones.

5. **Write the data to `bin/pipeline_cache.bin`**. Next launch, step 1 will find this file and the cycle repeats.

The timing measurement around pipeline creation lets you compare first-run (cold cache) vs subsequent runs (warm cache).

```c
start_time := time.tick_now()
app.graphics_pipeline = ovk.create_graphics_pipeline(...) or_return
fmt.printfln("Pipeline creation time: %s", time.tick_since(start_time))
```

---

## Results

The first time you run the executable, the pipeline cache file doesn't exist, so the driver compiles everything from scratch. Pipeline creation time will be whatever it was before this step (typically a few ms). The cache data is then saved to disk.

On the second run, the cache file is found and loaded. The driver reads the cached blob and skips the compilation. Depending on your GPU and driver, pipeline creation drops to about 1/3 to 1/10 of the cold time. With a warm cache you might see numbers like `2.3ms` vs `1.0ms`.

The cache file (`bin/pipeline_cache.bin`) is an opaque binary data - you can't inspect it, but you can verify it was written correctly by checking its size and confirming the pipeline still works.

If you delete the cache file between runs, creation goes back to cold-start speed. If you update the shader or change pipeline state (different formats, different vertex layout), the driver detects the mismatch internally, discards the stale cache entries, and compiles whatever doesn't match. The saved cache is updated at the end of that run to reflect the new state.

### Common pitfalls

- **The `bin/` directory must exist** before the first write to `bin/pipeline_cache.bin`. The build command creates `bin/debug/` (the executable output goes there), so `bin/` is usually present. If you get a file write error, check that the working directory has a `bin/` folder.
- **The `delete(cache_data)` after `get_pipeline_cache_data` is easy to forget.** `get_pipeline_cache_data` allocates with `make`, so the returned slice must be freed. The code uses `defer delete(cache_data)` right after declaring the variable.
