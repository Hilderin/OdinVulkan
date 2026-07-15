---
title: 18 - Staging Buffer
nav_order: 20
---

# 18 - Staging Buffer

Step 17 got the triangle out of the shader and into a buffer, but the buffer we used was `HOST_VISIBLE | HOST_COHERENT` - memory the CPU can write to directly. That's the easy option, and it's also the slow one: every time the GPU reads a vertex, it pulls from system RAM across the PCIe bus. For a triangle it doesn't matter; for a real mesh it does. This step keeps the same triangle on screen but moves the vertex data into `DEVICE_LOCAL` memory - the GPU's own fast memory, which the CPU can't access directly. We need to go through a temporary buffer the CPU can write to and then ask the GPU to copy that into a `DEVICE_LOCAL` buffer. That temporary buffer is called a *staging buffer*.

The staging pattern is the standard Vulkan answer to "how do I get data into GPU-only memory". It shows up for buffers, for images, for anything the GPU wants local and the host can't touch. Learn it once here, reuse it forever.

The full source for this step lives in [src/18_staging_buffer/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/18_staging_buffer/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/02_Staging_buffer.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Vertex_buffers/Staging_buffer>

---

## What's new, in one glance

- `transfer_to_buffer` - a new generic proc that does the whole staging dance: create a host-visible staging buffer, copy CPU data into it, record a `vk.CmdCopyBuffer` into the destination buffer, submit it on the graphics queue, and wait for it to finish.
- The vertex buffer is now created with `{.VERTEX_BUFFER, .TRANSFER_DST}` usage and `.DEVICE_LOCAL` memory, instead of `HOST_VISIBLE` like before. The GPU keeps the hot data on its own side.
- `begin_command_buffer` grew a `flags` parameter (defaulting to `{}`), so the same proc can record a frame's command buffer and a one-shot transfer command buffer.

---

## The staging pattern

The idea is simple, because every Vulkan resource dealing with GPU-local memory reuses it:

1. Create a *staging buffer* in `HOST_VISIBLE` memory. That's the only kind we can `memcpy` into from the CPU.
2. Write our data into it, exactly the way step 17 wrote straight into the vertex buffer.
3. Create the *real* buffer in `DEVICE_LOCAL` memory, with `TRANSFER_DST` usage (it needs that flag to accept a transfer command as a destination).
4. Record a `vk.CmdCopyBuffer` command from the staging buffer to the real buffer, submit it, wait for it.
5. Throw the staging buffer away - its only purpose was to ferry the data across.

After that, the GPU reads vertices out of fast local memory and never touches host memory again. We pay the slow copy once at upload time; every draw after that is cheap.

`transfer_to_buffer` packages that whole sequence:

```c
transfer_to_buffer :: proc(physical_device: vk.PhysicalDevice, device: vk.Device, queue: vk.Queue, data: []$T, dest_buffer: vk.Buffer) {
	size := u64(size_of(T) * len(data))

	staging_buffer, staging_buffer_memory := create_buffer(physical_device, device, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
	defer vk.DestroyBuffer(device, staging_buffer, nil)
	defer vk.FreeMemory(device, staging_buffer_memory, nil)

	mem_copy_to_buffer(device, staging_buffer_memory, data)

	command_pool := create_command_pool(device, physical_device)
	defer vk.DestroyCommandPool(device, command_pool, nil)
	command_buffers: [1]vk.CommandBuffer
	create_command_buffers(device, command_pool, command_buffers[:])
	command_buffer := command_buffers[0]

	begin_command_buffer(command_buffer, {.ONE_TIME_SUBMIT})

	copy_region := vk.BufferCopy {
		srcOffset = 0,
		dstOffset = 0,
		size      = vk.DeviceSize(size),
	}
	vk.CmdCopyBuffer(command_buffer, staging_buffer, dest_buffer, 1, &copy_region)

	end_command_buffer(command_buffer)

	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = &command_buffer,
	}
	vk_check(vk.QueueSubmit(queue, 1, &submit_info, 0), "Failed to submit command buffer!")
	vk_check(vk.QueueWaitIdle(queue), "Failed to wait on queue completion.")
}
```

Like `mem_copy_to_buffer` in step 17, the proc is generic over `$T` so `size_of(T)` resolves to `Vertex` when we pass a `[]Vertex` in - no manual element size, no separate "count" parameter. That's the only Odin-specific bit; the rest is straight Vulkan.

The staging buffer and its memory are torn down with `defer`, in reverse order, before `transfer_to_buffer` returns. That's only safe because of the `vk.QueueWaitIdle` at the bottom - we block the host until the copy is done, so the staging buffer is genuinely free by the time `defer` runs. Without that wait we'd be destroying a buffer the GPU might still be reading from. For a one-shot upload at startup this blocking wait is fine. For data that changes every frame (a dynamic vertex buffer, a uniform buffer) you'd want a fence and a per-frame staging buffer pool instead, so the upload can overlap the next frame's work. We're not there yet.

We create our own command pool and command buffer inside the proc, throwaway style. The reason is isolation and simplicity for now, but in a real-life application you should reuse your command pools at least, and even pool your command buffers. We will refactor some of this later.

---

## `ONE_TIME_SUBMIT`, and why `begin_command_buffer` grew a parameter

Until now every command buffer we recorded was a frame buffer: many commands, submitted once per frame, reset and reused the next. Vulkan lets you hint that a command buffer is going to be submitted exactly once and then discarded, with the `ONE_TIME_SUBMIT` flag.

That's why `begin_command_buffer` picked up a `flags` argument:

```c
begin_command_buffer :: proc(command_buffer: vk.CommandBuffer, flags: vk.CommandBufferUsageFlags = {}) {
	begin_info := vk.CommandBufferBeginInfo {
		sType            = .COMMAND_BUFFER_BEGIN_INFO,
		flags            = flags,
		pInheritanceInfo = nil,
	}
	// ...
}
```

---

## vk.CmdCopyBuffer and vk.BufferCopy

The actual data movement is one command:

```c
copy_region := vk.BufferCopy {
	srcOffset = 0,
	dstOffset = 0,
	size      = vk.DeviceSize(size),
}
vk.CmdCopyBuffer(command_buffer, staging_buffer, dest_buffer, 1, &copy_region)
```

`vk.CmdCopyBuffer` takes a *slice* of `BufferCopy` regions, so you can copy several ranges in one command - here we copy one range covering the whole buffer. `srcOffset` and `dstOffset` are byte offsets inside the source and destination buffers; both zero here because we want the full buffer at the start. Same idea as `vk.BindBufferMemory`'s offset argument from step 17: the API expects you might want to copy into a sub-region of a larger allocation, and we just don't.

> Notice that nothing here knows about `Vertex`. The copy is a raw byte transfer from one buffer to another.

---

## Submitting and waiting

The end of the proc is the simplest possible submit:

```c
submit_info := vk.SubmitInfo {
	sType              = .SUBMIT_INFO,
	commandBufferCount = 1,
	pCommandBuffers    = &command_buffer,
}
vk_check(vk.QueueSubmit(queue, 1, &submit_info, 0), "Failed to submit command buffer!")
vk_check(vk.QueueWaitIdle(queue), "Failed to wait on queue completion.")
```

We pass `0` as the fence argument - we're not interested in a fence because we're going to block on the queue anyway. `QueueWaitIdle` puts the host to sleep until everything submitted to that queue has finished. That's the same sledgehammer we used for swapchain recreation. It's fine for a tutorial or at application startup, but there's a better way to do it, which we'll see later.

Worth noting we use the *graphics* queue (`transfer_to_buffer` receives `graphics_queue` from `main`). Some GPUs expose a dedicated transfer queue that's better suited for this kind of work; we picked a single graphics queue back in step 5 and we're sticking with it. The graphics queue always supports transfer operations, so it works, and not having to pick a second queue family keeps the device setup simple. When this stops being a triangle we can revisit.

---

## Where it's called from

The change in `main` is tiny, which is the point of putting all the staging logic behind one proc:

```c
vertex_buffer, vertex_buffer_memory := create_buffer(physical_device, device, u64(size_of(Vertex) * len(vertices)), {.VERTEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL})
fmt.println("Vertex buffer... OK")

transfer_to_buffer(physical_device, device, graphics_queue, vertices, vertex_buffer)
fmt.println("Vertex copied to buffer using staging buffer... OK")
```

Two things moved. The vertex buffer's usage flags gained `.TRANSFER_DST` - without it, `vk.CmdCopyBuffer` would refuse to write into the buffer and validation would yell about a missing usage flag. Its memory type went from `{.HOST_VISIBLE, .HOST_COHERENT}` to `.DEVICE_LOCAL`, which is the entire reason this step exists. And the direct `mem_copy_to_buffer` call is gone, replaced by `transfer_to_buffer`, because the CPU can no longer reach the vertex buffer's memory.

If you ever forget the `.TRANSFER_DST` flag, expect a validation message like *"vkCmdCopyBuffer called on buffer 0x... which does not have VK_BUFFER_USAGE_TRANSFER_DST_BIT set."* Same idea if you flip it the other way around and the staging buffer is missing `.TRANSFER_SRC`.

There's no cleanup change. `transfer_to_buffer` cleans up its own staging buffer, command pool and command buffer through `defer`; the vertex buffer and its memory are still destroyed in `main`'s cleanup block, exactly like step 17.

---

## Test it

Run the executable from the `src/18_staging_buffer` directory. The startup log goes the same way as step 17 up to the vertex buffer line, then prints `Vertex copied to buffer using staging buffer... OK` instead of the old `Vertex copied to buffer... OK` - that's the only visible difference. The window shows the same colored triangle, still resizable, still framing the same three vertices.

The change is invisible on screen and that's the right outcome: we wanted the same picture, just backed by faster memory. If validation complains about a transfer usage flag, check that the vertex buffer has `.TRANSFER_DST` and the staging buffer has `.TRANSFER_SRC`. If validation complains about writing to memory that isn't host-visible, you've accidentally called `mem_copy_to_buffer` against a `.DEVICE_LOCAL` buffer - the whole point of the staging step is to keep that call pointed at the staging buffer only.

---

## What's next

The vertex data is now in GPU-local memory, uploaded through a staging buffer and a one-shot transfer command. Usually a 3D model reuses the same vertex more than once, so to save space in GPU memory we use an index buffer to avoid duplicating vertex data. That's [19 - Index Buffer](./19_index_buffer.md).