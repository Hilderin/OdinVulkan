---
title: 15 - Frames In Flight
nav_order: 17
---

# 15 - Frames In Flight

The previous step got us our triangle, but the loop was running one frame at a time: the CPU records a command buffer, hands it to the GPU, waits for the GPU to finish, then moves on. That means the GPU sits idle while the CPU works, and the CPU sits idle while the GPU renders. For a triangle it doesn't matter, but it scales badly - every frame pays the full round-trip latency.

This step changes that shape by allowing several frames to be in flight at once. While the GPU is rendering frame N, the CPU is already recording frame N+1, and so on. Nothing visible changes on screen; this is purely a structural change so the CPU and the GPU can overlap. The classic number to keep in flight is two - the CPU is never more than one frame ahead of the GPU, which keeps latency low while still keeping both busy.

The full source for this step lives in [src/15_frames_in_flight/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/15_frames_in_flight/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/03_Drawing/03_Frames_in_flight.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Drawing/Frames_in_flight>

---

## What's new, in one glance

- `NB_FRAMES_IN_FLIGHT :: 2` - the named constant that drives everything. Two is the usual choice; we keep it that way.
- `create_command_buffers`, `create_semaphores`, `create_fences` - the per-frame versions of the singletons from step 14. Each takes a slice and fills it.
- Fixed-size arrays backed by `NB_FRAMES_IN_FLIGHT` for command buffers, acquire semaphores and draw fences, while `submit_semaphores` stays sliced on the swapchain image count.
- A `frame_index` counter walked with `% NB_FRAMES_IN_FLIGHT` so each iteration picks the right per-frame set, then advances to the next.
- The cleanup loops now iterate over the arrays instead of destroying one handle.

---

## Why frames need their own everything

In step 14 we had one command buffer, one draw fence, one acquire semaphore. Reusing the same command buffer while the GPU is still executing it would be a use-after-free of command recording state; reusing the same fence before it's signaled would mean waiting on the wrong frame; reusing the same acquire semaphore before it's been waited on can deadlock (the Khronos guide on swapchain semaphore reuse, linked in step 14, covers that one in detail).

The fix is the boring one: give each frame its own copy of every object that gets touched by the GPU in a frame, and only reuse a copy once the GPU has handed it back. With `NB_FRAMES_IN_FLIGHT` frames in flight, we need `NB_FRAMES_IN_FLIGHT` command buffers, draw fences and acquire semaphores.

> Note the exception: `submit_semaphores` stays indexed by swapchain image count, not by frame. That one is waited on by `vk.QueuePresent`, which cares about which image is being shown, not which frame produced it - so it stays per-image.

---

## The loop body - acquire/submit/present in sync

The main loop is now driven by a `frame_index`:

```c
frame_index: u32 = 0
for !glfw.WindowShouldClose(window) && running {
	glfw.PollEvents()

	swap_chain_image_index := acquire_next_image(device, swap_chain, draw_fences[frame_index], acquire_semaphores[frame_index])

	record_command_buffer(
		command_buffers[frame_index],
		swap_chain_images[swap_chain_image_index],
		swap_chain_image_views[swap_chain_image_index],
		swap_chain_extent,
		graphics_pipeline,
	)

	submit_command_buffer(
		device,
		command_buffers[frame_index],
		draw_fences[frame_index],
		acquire_semaphores[frame_index],
		submit_semaphores[swap_chain_image_index],
		graphics_queue,
	)

	queue_present(device, swap_chain, submit_semaphores[swap_chain_image_index], graphics_queue, swap_chain_image_index)

	frame_index = (frame_index + 1) % NB_FRAMES_IN_FLIGHT
}
```

Every per-frame object is indexed with `frame_index`, and every per-image object stays indexed with `swap_chain_image_index` - those two are not the same thing and it's easy to slip up. `frame_index` walks 0, 1, 0, 1, ... while the image index jumps around based on what `vk.AcquireNextImageKHR` happens to hand us.

The actual acquire/submit/present logic is unchanged, `acquire_next_image` still waits on the draw fence, and that's where the magic happens: because the fence we wait on is `draw_fences[frame_index]`, we're only blocking on the same frame we're about to reuse, not the whole pipeline. On frame index 0 the first time through, the pre-signaled fence lets us sail past; on frame index 0 the second time, we wait for frame index 0's previous submit to finish, by which point frame index 1 has already been submitted and is likely still on the GPU. That overlap is the whole point.

---

## Cleanup mirrors the new arrays

Nothing surprising, just loops instead of single `vk.Destroy*` calls:

```c
for draw_fence in draw_fences {
	if draw_fence != 0 {
		vk.DestroyFence(device, draw_fence, nil)
	}
}
for acquire_semaphore in acquire_semaphores {
	if acquire_semaphore != 0 {
		vk.DestroySemaphore(device, acquire_semaphore, nil)
	}
}
```

The fixed arrays don't need a `defer delete` - they live on the stack of `main`, so they go away on their own. The `submit_semaphores` slice keeps its `defer delete` from step 14. `wait_idle_device` still runs before any of this, same as before.

---

## Test it

The difference is invisible: with two frames in flight the GPU is no longer waiting on the CPU between frames, so frame pacing is smoother and a frame that takes a while to record no longer stalls the whole pipeline. There's no FPS counter in this project, so you won't see numbers; the point of this step is the structure, not a visible change.

If validation complains about a fence or command buffer being in use when destroyed, double-check that `wait_idle_device` is still being called before the cleanup loops - it's the only thing keeping the GPU from referencing the per-frame sets during teardown.

---

## What's next

We now draw smoothly with two frames in flight, but we can't resize the window. Step 16 is about recreating the swapchain on the fly - tearing down the old one and building a new one that matches the new surface size. That's [16 - Swap Chain Recreation](./16_swap_chain_recreation.md).