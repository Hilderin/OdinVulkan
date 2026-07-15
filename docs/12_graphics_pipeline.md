---
title: 12 - Graphics Pipeline
nav_order: 14
---

# 12 – Graphics Pipeline

With a `vk.ShaderModule` now available on the GPU, the next step is to create a **graphics pipeline** - the object that ties the fixed-function stages together with our shaders to turn vertices into pixels on screen. A pipeline in Vulkan is immutable once created: the moment you want to change anything in it, you have to rebuild the whole pipeline. This is what lets Vulkan compile the pipeline down to GPU-specific code as efficiently as possible up front.

The full source for this step lives in [src/12_graphics_pipeline/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/12_graphics_pipeline/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version:
  - <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/02_Graphics_pipeline_basics/02_Fixed_functions.html>
  - <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/02_Graphics_pipeline_basics/03_Dynamic_rendering.html>
  - <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/02_Graphics_pipeline_basics/04_Conclusion.html>
- vulkan-tutorial.com version:
  - <https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Fixed_functions>
  - <https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Render_passes>
  - <https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Conclusion>

> A note on the scope: compared to the original tutorial, I rolled several of its sub-steps into one here. Splitting them into separate steps would have produced code that did nothing on its own, and after going through it I didn't find this step to be the size the tutorial makes it look. The one thing worth flagging if you compare with the original: **we don't create a render pass anymore**. With dynamic rendering (Vulkan 1.3, which we require from the device), that step is optional and simplifies pipeline creation a fair amount. We'll come back to render passes later; for now, just be thankful the API grew that shortcut.

---

## What's new, in one glance

- `create_graphics_pipeline` - the big one. Takes the shader module, the two entry-point names, and the swapchain format. Returns the `vk.Pipeline` and the `vk.PipelineLayout` that goes with it.
- `create_swap_chain` now also returns the `vk.Extent2D` it picked - not strictly needed in this step, but threaded out so the pipeline (and later the dynamic viewport) can reuse it. `main` discards it with `_` for now.
- Cleanup gets `vk.DestroyPipeline` and `vk.DestroyPipelineLayout`, both before the shader module they reference.

---

## Stages and state, in one object

A graphics pipeline in Vulkan is two categories glued together:

- **Programmable stages** - here, vertex and fragment. Each is a `vk.PipelineShaderStageCreateInfo` that points at the same `vk.ShaderModule` we built in step 11 and just selects a different entry point by name. One module, two stages - that's the SlangSetup from the previous steps paying off.
- **Fixed-function state** - everything Vulkan still wants you to be explicit about even when there's nothing fancy going on: vertex input layout, input assembly topology, viewport/scissor counts, rasterizer, multisampling, color blend, dynamic state. Each of those is its own `*StateCreateInfo` struct, and one pointer to each gets wired into the final `vk.GraphicsPipelineCreateInfo`.

If a state you don't care about yet still has to be filled, that's normal - Vulkan has no "use defaults" mode. You spell out even the boring pieces.

---

## Dynamic state, or "why the viewport isn't here"

```c
dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
```

Anything listed here can be set at draw time through `vk.CmdSetViewport` / `vk.CmdSetScissor` instead of being baked into the pipeline. The big win: the pipeline doesn't need to be rebuilt when the window resizes.

The device enrolling in `extendedDynamicState` (step 04) opens the door to pushing even more state into this list later. For now, viewport and scissor are the two that actually move.

---

## The fixed-function pieces, briefly

- **Vertex input** - all-zero. Our triangle's positions and colors are hard-coded in the vertex shader, so there's no vertex buffer to describe. We'll come back to this when vertex buffers enter the picture.
- **Input assembly** - `.TRIANGLE_LIST`, no primitive restart. The default "draw independent triangles" mode.
- **Rasterizer** - `.FILL` polygons, back-face culling, `lineWidth = 1`. Note `frontFace = .CLOCKWISE`: the tutorial uses `.COUNTER_CLOCKWISE`, but our hardcoded vertex order goes clockwise in clip space, so we flip the convention to match. Get this wrong and the triangle gets culled and you see nothing - a classic "blank window for no obvious reason" pitfall.
- **Multisampling** - off. We'll turn it on for anti-aliasing much later.
- **Depth/stencil** - skipped entirely; we have no depth attachment yet.
- **Color blend** - alpha blending enabled with standard `SRC_ALPHA / ONE_MINUS_SRC_ALPHA` factors. The result is the usual `out = newAlpha * newColor + (1 - newAlpha) * oldColor`. The tutorial ships with blending off (just overwrites); I left it on because it's the more useful default to grow into, and one attachment is cheap.
- **Pipeline layout** - empty. No descriptors, no push constants yet, so `setLayoutCount = 0` and `pushConstantRangeCount = 0`. The pipeline *layout* still has to exist even when it describes nothing.

---

## Dynamic rendering: the `pNext` instead of a render pass

```c
pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
	sType                   = .PIPELINE_RENDERING_CREATE_INFO,
	colorAttachmentCount    = 1,
	pColorAttachmentFormats = &format,
}
```

This is the bit that replaces the entire "render pass" chapter of the original tutorial. Instead of building a `vk.RenderPass` object that describes attachment formats, load/store ops and subpasses, you hand the same format information to the pipeline through a `vk.PipelineRenderingCreateInfo` chained into `GraphicsPipelineCreateInfo.pNext`, and you leave `renderPass = 0` in the main create info.

When we actually start recording draw commands, the same `vk.PipelineRenderingCreateInfo` shape will show up again as part of `vk.BeginRendering` (chained into the command buffer begin info). The pipeline and the render begin have to agree on attachment formats - that's the contract dynamic rendering asks for, in exchange for not needing a render pass object.

`swap_chain_format` is the one we picked in step 08 out of `create_swap_chain`. The pipeline needs it because the color blend and the attachment format are tied together: the driver validates the blend configuration against the format you declare here.

---

## vk.CreateGraphicsPipelines, plural

```c
vk_check(vk.CreateGraphicsPipelines(device, 0, 1, &pipeline_create_info, nil, &graphics_pipeline), "Failed to create graphics pipeline!")
```

The call is plural on purpose - it takes a count and a pointer to an array, so you can build several pipelines in one shot (a pipeline cache as the second argument can speed up later rebuilds by reusing compiled internal state). We pass `1` and the address of our single create info, which is the usual "one of an N-capable call" pattern in Vulkan. The `0` for the cache means "no cache, compile fresh".

Pipeline creation is one of the heavier Vulkan calls - the driver actually compiles shaders down to GPU-specific code here. That's why pipeline caches matter once you have more than a handful of pipelines, and it's also why creating pipelines up front (or on a background thread) instead of at first draw is a real-world thing.

---

## Cleanup

```c
if pipeline_layout != 0 {
	vk.DestroyPipelineLayout(device, pipeline_layout, nil)
}
if graphics_pipeline != 0 {
	vk.DestroyPipeline(device, graphics_pipeline, nil)
}
```

Same defensive `0` checks as everywhere else. The pipeline references the pipeline layout, and the pipeline stages reference the shader module, so destruction order is pipeline first, then layout, then module - exactly the reverse of creation. Placed at the top of cleanup, ahead of the shader module and the rest.

---

## Test it

The window is still blank - we have a fully constructed pipeline object now, but nothing has issued a single draw command yet. What you should see is the usual setup chain running to completion, ending with a new `Graphics pipeline... OK` line after the shader module line, then `Vulkan initialization completed with success!`. If validation complains about a mismatch between the rendering info format and the swapchain, double-check that `create_swap_chain` returns the same format you're passing into `create_graphics_pipeline`.

---

## What's next

The pipeline exists, but it has no input yet and no rendering loop to drive it. The next step starts recording commands to be sent to the GPU to do the actual rendering. That's [13_command_buffers](./13_command_buffers.md).