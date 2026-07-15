---
title: 13 - Command Buffers
nav_order: 15
---

# 13 – Command Buffers
Now that we have a pipeline, it's time to create the commands that will tell the GPU how to render. The commands need to be recorded into a **CommandBuffer**, which lives inside a **CommandPool**.

On every frame, in the next step, we will recreate the CommandBuffer and run it. For now I've just put a single `record_command_buffer` call at startup in main, but this method will be called on every frame.

The full source for this step lives in [src/13_command_buffers/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/13_command_buffers/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/03_Drawing/01_Command_buffers.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Command_buffers>

---

## What's new, in one glance

- `create_command_pool` - allocates the `vk.CommandPool` the command buffers will come from.
- `create_command_buffer` - allocates one primary `vk.CommandBuffer` out of the pool.
- `record_command_buffer` - the orchestrator. Begins the buffer, transitions the image to `COLOR_ATTACHMENT_OPTIMAL`, begins dynamic rendering, binds the pipeline, sets viewport/scissor, draws 3 vertices, ends rendering, transitions the image to `PRESENT_SRC_KHR`, ends the buffer.
- Helpers: `begin_command_buffer`, `end_command_buffer`, `transition_image_layout`, `begin_rendering`, `end_rendering`, `set_viewport`, `set_scissor`.
- Device selection now also requires the **`synchronization2`** feature from Vulkan 1.3, because `transition_image_layout` uses `vk.CmdPipelineBarrier2` and the `*2` barrier/dependency structs.
- `create_swap_chain`'s `swap_chain_extent` is no longer discarded - it's threaded down to the recording so the viewport and scissor match the chosen resolution.

---

## Command pools and command buffers

A **command pool** is a memory arena for a given queue family. You don't allocate command buffers out of thin air; you allocate them out of a pool, and the pool is tied to a queue family index. That's why `create_command_pool` re-runs `find_queue_families` with `{.GRAPHICS}` - the pool has to belong to the same family that will eventually submit these commands.

```c
command_pool_create_info := vk.CommandPoolCreateInfo {
	sType            = .COMMAND_POOL_CREATE_INFO,
	flags            = {.RESET_COMMAND_BUFFER},
	queueFamilyIndex = queue_index,
}
```

The `.RESET_COMMAND_BUFFER` flag lets us call `vk.BeginCommandBuffer` on the same buffer more than once. Without it, the buffer is one-shot and has to be freed after a single use. For a tutorial that records the same draw every frame, allowing reset is the simpler choice.

`vk.CreateCommandPool` is the standard object-creation shape. The pool must be destroyed with `vk.DestroyCommandPool` and it implicitly frees every command buffer allocated from it - we don't have to track the buffers individually at cleanup.

The command buffer itself comes from `vk.AllocateCommandBuffers`:

```c
command_buffers := make([]vk.CommandBuffer, 1)
vk_check(vk.AllocateCommandBuffers(device, &alloc_info, raw_data(command_buffers)), "Failed to create command buffer!")
```

Note that we don't need to call `vk.FreeCommandBuffers` here, because command buffers are freed automatically when the CommandPool is destroyed. That works fine since we reuse the same CommandBuffer every frame. On the other hand, if you create a CommandBuffer for a one-shot use, you'll have to free the CommandBuffer yourself. We'll use that technique later on.

---

## Recording, in one sentence each

`record_command_buffer` is intentionally written as a flat sequence of helper calls so the order is readable as a recipe:

1. `begin_command_buffer` - puts the buffer into the recording state with `vk.BeginCommandBuffer`. Empty flags means "no inheritance, no one-timeSubmit" - the defaults that let us re-record later.
2. `transition_image_layout` to `.COLOR_ATTACHMENT_OPTIMAL` - the swapchain image starts in `.UNDEFINED`; the GPU can only write to it as a color attachment once it's in the right layout.
3. `begin_rendering` - opens a dynamic rendering pass through `vk.CmdBeginRendering` with one color attachment (clear to opaque black on load, store the result).
4. `vk.CmdBindPipeline` with `.GRAPHICS` - from this point on, draws use our pipeline.
5. `set_viewport` / `set_scissor` - the dynamic state we declared in step 12. These are commands, not pipeline state; they take effect in the order they're recorded.
6. `vk.CmdDraw` - 3 vertices, 1 instance, first vertex 0, first instance 0. The hardcoded triangle from the vertex shader.
7. `end_rendering` - `vk.CmdEndRendering`, closes the pass.
8. `transition_image_layout` to `.PRESENT_SRC_KHR` - hands the image back to the presentation engine in the layout it expects.
9. `end_command_buffer` - finalizes the recording with `vk.EndCommandBuffer`.

That's the full skeleton of a Vulkan frame, minus the actual submit/present. The dynamic-rendering flavor keeps the whole thing short - no subpass dependencies, no clear ops declared in a separate render pass object.

---

## Image layout transitions, the synchronization2 way

```c
image_barrier := vk.ImageMemoryBarrier2 { ... }
dependency_info := vk.DependencyInfo { ... }
vk.CmdPipelineBarrier2(command_buffer, &dependency_info)
```

The original tutorial uses the older `vk.CmdPipelineBarrier` with a `vk.ImageMemoryBarrier` where stage masks and access masks live in separate arguments. We use the `*2` variants (`ImageMemoryBarrier2`, `DependencyInfo`, `CmdPipelineBarrier2`) instead. They are part of `VK_KHR_synchronization2`, which was promoted to core in Vulkan 1.3.

The advantage is that stage and access masks travel together on each barrier - you express "this access at this stage must happen before that access at that stage" per barrier, instead of globally for the whole call. For two transitions it doesn't change much, but it scales better and is the model Vulkan itself recommends going forward. You'll see the real payoff later, at the texturing step.

This is also why `score_device` and `create_logical_device` grew a `synchronization2 = true` requirement this step. Without the feature enabled at device creation, the `*2` calls are unavailable. Same pattern as `dynamicRendering` in the previous steps: enable the feature up front, then you're allowed to use the calls that depend on it.

---

## Dynamic rendering begins where the render pass used to be

```c
attachment_info := vk.RenderingAttachmentInfo {
	sType       = .RENDERING_ATTACHMENT_INFO,
	imageView   = image_view,
	imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
	loadOp      = .CLEAR,
	storeOp     = .STORE,
	clearValue  = {color = {float32 = {0.0, 0.0, 0.0, 1.0}}},
}

render_info := vk.RenderingInfo {
	sType              = .RENDERING_INFO,
	layerCount         = 1,
	renderArea         = {extent = swap_chain_extent},
	pColorAttachments  = &attachment_info,
	colorAttachmentCount = 1,
}
vk.CmdBeginRendering(command_buffer, &render_info)
```

This is the runtime counterpart of the `vk.PipelineRenderingCreateInfo` we chained into the pipeline in step 12. The pipeline was told "one color attachment with this format"; the render begin now says "here is that attachment, here is the view, here is what to do with it". Both sides have to agree on the format chain, which is exactly why `swap_chain_format` is threaded through both.

`loadOp = .CLEAR` with the black `clearValue` is the "start every frame from a clean slate" choice (black in our example). `storeOp = .STORE` keeps the rendered result so it can be presented. The `clearValue` is a tagged union over `color` / `depthStencil`, and the `float32` field is itself a `[4]f32` - this nested-union literal style is the idiomatic way to fill these in Odin.

The `renderArea` is a `vk.Rect2D` built with `{extent = swap_chain_extent}` - the offset defaults to zero, the extent is the whole swapchain image. That's also why `swap_chain_extent` got promoted from a `_` discard in `main` to a real threaded value this step: the render area and the dynamic viewport/scissor all need it.

---

## Why the window is still blank

Nothing in this step submits the command buffer to a queue, and nothing presents an image. Recording a command buffer is purely a CPU-side action: it fills the buffer with commands, but those commands don't execute until a `vk.QueueSubmit` call sends them off. That's the next step's job - allocation here buys us a ready-to-go buffer we can submit on demand.

---

## Cleanup

```c
if command_pool != 0 {
	vk.DestroyCommandPool(device, command_pool, nil)
}
```

Destroying the pool frees the command buffer allocated from it, so there's no separate `vk.FreeCommandBuffers` call. As with everything else, it has to happen before the device is destroyed. Placed first in cleanup, ahead of the pipeline and pipeline layout, which is the reverse-of-creation order Vulkan expects.

---

## Test it

Run the executable from the `src/13_command_buffers` directory. The window opens and stays blank - that's expected, we're not submitting yet, of course! Wait just a bit longer, we are almost there.

What you want to look for is the terminal: the usual setup chain should run to completion, now with three new lines:

```
Command pool... OK
Command buffer... OK
Record command buffer... OK
```

followed by `Vulkan initialization completed with success!`. If validation prints a `synchronization2`-related message, double-check that both `score_device` and `create_logical_device` enable the feature - the recording will fail on devices that don't advertise it.

---

## What's next

The buffer is recorded, but it's sitting idle. The next step wires up the main loop: acquire a swapchain image, submit the command buffer with semaphores to keep the GPU and the presentation engine in sync, present the image, and finally see the triangle. That's [14 - Presentation and First Triangle](./14_presentation_first_triangle.md).