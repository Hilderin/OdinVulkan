---
title: 21 - Images
nav_order: 23
---

# 21 - Images

Il est maintenant le temps de parler image afin de se préparer à transformer notre quad multicolor en un quad qui affiche une texture.

A texture on the GPU is just an *image* - a 2D (or 3D) block of pixels living in GPU memory, with rules about how it can be accessed. This step just creates a Vulkan image from a JPEG file and gets its pixels into GPU-local memory.

The full source for this step lives in [src/21_images/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/21_images/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/06_Texture_mapping/00_Images.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Texture_mapping/Images>

---

## What's new, in one glance

- `create_image` - the image counterpart to `create_buffer`: `vk.CreateImage`, `vk.GetImageMemoryRequirements`, allocate, `vk.BindImageMemory`. Returns a `(vk.Image, vk.DeviceMemory)` pair.
- `create_texture_image` - orchestrates the whole texture upload: load a JPEG, push its pixels into a staging buffer, create the destination image, transition its layout, copy the buffer into it, transition again into a shader-readable layout.
- `transfer_buffer_to_image` - wraps `vk.CmdCopyBufferToImage` and its `vk.BufferImageCopy` region, the image equivalent of the `vk.CmdCopyBuffer` we've used since step 18.
- `begin_single_time_commands` / `end_single_time_commands` - the one-shot command buffer pattern we'd been inlining since step 18, finally refactored for more reuability. `transfer_to_buffer` now takes a `command_pool` argument instead of creating and destroying its own.
- Two new imports: `core:image` and `core:image/jpeg`, to decode the JPEG without pulling in stb_image.

---

## Buffers vs images

A buffer is a flat row of bytes. An image is a 2D (or 3D, or layered) grid of texels with a format, a tiling mode and a *layout*. The big difference is that an image always carries a current layout - `UNDEFINED`, `TRANSFER_DST_OPTIMAL`, `SHADER_READ_ONLY_OPTIMAL`, and so on - that tells the GPU what kinds of operations are legal on it right now. You cannot just `vk.CmdCopyBufferToImage` into an image that's in the wrong layout, and you cannot just sample an image that's still in `TRANSFER_DST_OPTIMAL`. Every change of intent on an image is a *layout transition*, recorded as a pipeline barrier in the command buffer.

That's why `create_texture_image` does three things in one command buffer, in order:

1. Transition the freshly created image from `UNDEFINED` to `TRANSFER_DST_OPTIMAL` - "I'm about to write into this image from a transfer command".
2. `vk.CmdCopyBufferToImage` - actually upload the staging buffer's pixels.
3. Transition from `TRANSFER_DST_OPTIMAL` to `SHADER_READ_ONLY_OPTIMAL` - "writes are done, this image is now meant to be read by a shader".

The barriers in between synchronize those steps so a single command buffer can hold all three. We already had `transition_image_layout` from step 14 (it drives the swapchain image from `UNDEFINED` to `COLOR_ATTACHMENT_OPTIMAL` at the start of the frame and to `PRESENT_SRC_KHR` at the end); this step just reuses it for a texture.

---

## transition_image_layout takes its masks as parameters

The tutorial's `transitionImageLayout` hardcodes the access masks and pipeline stages inside the proc, behind a ladder of `if / else if` on the `(oldLayout, newLayout)` pair. It covers exactly two transitions and throws on anything else:

```c
if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED && newLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    sourceStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    destinationStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
} else if (oldLayout == VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL && newLayout == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
    // ...
} else {
    throw std::invalid_argument("unsupported layout transition!");
}
```

That works for the tutorial because the tutorial only ever does those two transitions. We already use `transition_image_layout` in `record_command_buffer` for the swapchain image (two more transitions: `UNDEFINED -> COLOR_ATTACHMENT_OPTIMAL` and `COLOR_ATTACHMENT_OPTIMAL -> PRESENT_SRC_KHR`), and we're about to use it twice more here for the texture. Each new pair would mean another `else if` branch, and the proc would slowly turn into a hand-written lookup table difficult to comprehend and upgrade.

So instead, `transition_image_layout` takes the four masks as explicit parameters: `src_access_mask`, `dst_access_mask`, `src_stage_mask`, `dst_stage_mask`. The proc just packs them into an `ImageMemoryBarrier2` and calls `vk.CmdPipelineBarrier2`.

Every call site says out loud what it needs and what it does:

```c
transition_image_layout(
    command_buffer,
    image,
    .UNDEFINED, //old_layout
    .TRANSFER_DST_OPTIMAL, //new_layout
    {}, // src_access_mask
    {.TRANSFER_WRITE}, // dst_access_mask
    {.TOP_OF_PIPE}, // src_stage
    {.TRANSFER}, // dst_stage
)
```

Read that as: "this image has never been touched (`TOP_OF_PIPE`, no prior access), and the next thing that happens is a transfer write (`TRANSFER` stage, `TRANSFER_WRITE` access)."

---

## Creating an image is a lot like creating a buffer

`create_image` is the mirror of `create_buffer`, with three name swaps:

```c
vk.CreateImage        instead of vk.CreateBuffer
vk.GetImageMemoryRequirements instead of vk.GetBufferMemoryRequirements
vk.BindImageMemory    instead of vk.BindBufferMemory
```

The `vk.ImageCreateInfo` is where the image-specific bits live: `imageType = .D2`, an `extent` with `width / height / depth`, `mipLevels = 1`, `arrayLayers = 1`, a `format` (`.R8G8B8A8_SRGB` here, matching the 4-channel JPEG), `tiling = .OPTIMAL` (GPU-friendly texel arrangement, opaque to us), `samples = {._1}` (no multisampling for a texture), and an `initialLayout` of `.UNDEFINED` because we're going to transition it ourselves before any use.

The memory side is identical to what we've done for buffers: ask the image what it needs, find a memory type that satisfies both those requirements and our `properties` flags, allocate, bind. `create_texture_image` asks for `DEVICE_LOCAL` memory with `{.TRANSFER_DST, .SAMPLED}` usage - the image has to accept transfer writes (during upload) and shader sampling (for next step).

---

## The staging dance, image edition

The upload path reuses the staging pattern from step 18, just with an image at the end instead of a buffer:

```c
staging_buffer, staging_buffer_memory := create_buffer(physical_device, device, size, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT})
defer vk.DestroyBuffer(device, staging_buffer, nil)
defer vk.FreeMemory(device, staging_buffer_memory, nil)

mem_copy_to_buffer(device, staging_buffer_memory, bytes.buffer_to_bytes(&src_image.pixels))

image, image_memory := create_image(physical_device, device, width, height, 1, .R8G8B8A8_SRGB, {.TRANSFER_DST, .SAMPLED}, {.DEVICE_LOCAL})
```

Pixels go into a host-visible staging buffer the same way vertices did. Then we create the destination image in `DEVICE_LOCAL` memory, and we'll ask the GPU to copy from the staging buffer into that image.


---

## vk.CmdCopyBufferToImage and vk.BufferImageCopy

The actual upload to the GPU is one command:

```c
copy_region := vk.BufferImageCopy {
	bufferOffset         = 0,
	bufferRowLength      = 0,
	bufferImageHeight    = 0,
	imageSubresource     = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
	imageOffset          = {0, 0, 0},
	imageExtent          = {width, height, 1},
}
vk.CmdCopyBufferToImage(command_buffer, src_buffer, dest_image, .TRANSFER_DST_OPTIMAL, 1, &copy_region)
```

A few of those fields look redundant but they aren't. `bufferRowLength` and `bufferImageHeight` are for the case where your pixels in the staging buffer have a different row pitch than the image - useful for alignment or sub-rect uploads. Leave them at 0 and Vulkan uses `imageExtent` to figure out the row length. `imageSubresource.aspectMask = {.COLOR}` says we're writing the color aspect of the image (as opposed to depth, stencil, etc.). `imageExtent` is the size of the region being copied. The third argument to `vk.CmdCopyBufferToImage` is the *layout the image is currently in* - which is why the layout transition into `TRANSFER_DST_OPTIMAL` had to happen first. Get this wrong and validation yells that the image isn't in the expected layout.

---

## Loading a JPEG without stb_image

The tutorial uses stb_image, which is a C header. On Linux it sometimes needs extra setup, and Odin has a perfectly good image library in `core`, so we use that:

```c
import img "core:image"
import "core:image/jpeg"

// Avoids 'unused import' error: "core:image/jpeg" needs to be imported in order
// to make `img.load` understand jpeg format.
_ :: jpeg
```

`core:image/jpeg` registers the JPEG decoder with `img.load` through an `init` that runs on import. The catch is that we never *name* `jpeg` directly after that, so a strict-style build would flag the import as unused. The `_ :: jpeg` line is the idiomatic Odin escape hatch: it references the package just enough to keep the import, without doing anything with it. You'll see this pattern whenever a package is imported for its side effects - codec registration, allocator registration, and so on.

`img.load(path, {.alpha_add_if_missing})` decodes the file and, because JPEG has no alpha channel, forces one in (the SRGB format we picked is `R8G8B8A8`, four channels). Without that flag we'd get a 3-channel image and the `assert(src_image.channels == 4)` right below would trip. Note that this is a *non-zero* extra cost: the added alpha is just padding. The shader-facing path expects 4 bytes per texel, so we pay it once at load time.

---

## One command pool for the whole upload

In step 18, `transfer_to_buffer` created its own command pool and command buffer, did the copy, submitted, waited, and tore it all down through `defer`. That was the simplest way to introduce the pattern, but it was wasteful: a brand new command pool every time we upload something.

This step finally does the refactor. Two small procs factor the one-shot lifecycle:

```c
begin_single_time_commands :: proc(device: vk.Device, command_pool: vk.CommandPool) -> vk.CommandBuffer
end_single_time_commands   :: proc(device: vk.Device, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer, queue: vk.Queue)
```

`begin_single_time_commands` allocates a command buffer from the *passed-in* pool and begins it with `ONE_TIME_SUBMIT`. `end_single_time_commands` ends it, submits it on the queue, waits for it to complete with `vk.QueueWaitIdle`, and frees the command buffer back to the pool. The pool stays alive as long as the caller wants.

That's the key change for `create_texture_image`: it needs a single command buffer to host the transition -> copy -> transition sequence, because the barriers between them have to be ordered within one recording. If each step allocated and submitted its own command buffer (the old `transfer_to_buffer` style) we'd be paying three separate submit-and-wait round trips and serializing a job that the GPU could otherwise pipeline. Recording all three into one buffer and submitting once is both simpler and faster.

`transfer_to_buffer` itself was rewritten to take a `command_pool` argument and use the two new helpers, so the index and vertex uploads at startup now share the same one-shot plumbing as the texture upload. Less duplicated code, no per-call command pool creation.

---

## Test it

Run the executable from the `src/21_images` directory. The startup log is the same as step 20 up to the index copy line, then prints an `Image loaded 512 x 512, channels: 4` line (the exact dimensions depend on the JPEG), followed by `Texture image loaded... OK`, before continuing into the uniform buffer setup and the usual `Vulkan initialization completed with success!`.

The window shows the same rotating quad from step 20. That's expected: this step only puts the image in GPU memory, it doesn't wire it into the pipeline, doesn't allocate a descriptor for it, doesn't change the shader. The picture can't change because the shader has no way to reach the new image yet.

If validation complains about an image not being in the expected layout, double-check that the first `transition_image_layout` call uses `TRANSFER_DST_OPTIMAL` as the *new* layout and `TOP_OF_PIPE` as the source stage (we've never touched the image before, so there's no prior access to wait on). If the JPEG fails to load, check the path: `create_texture_image` looks for `../../assets/images/statue.jpg` relative to the working directory, so it has to be run from `src/21_images` like the other steps.

---

## What's next

The image is sitting in GPU memory in `SHADER_READ_ONLY_OPTIMAL` layout but nothing reads it. To actually texture the quad, the shader needs a way to fetch a texel from the image, and that requires two more Vulkan objects: an *image view* (so the shader can look at the image with a specific format and aspect) and a *sampler* (which defines how filtering, addressing and mip behavior happen). The next step wires those up and binds them through a second descriptor. That's [22 - Image view and sampler](./22_image_view_sampler.md).