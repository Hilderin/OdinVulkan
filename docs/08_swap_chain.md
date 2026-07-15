---
title: 08 — Swap Chain
nav_order: 10
---

# 08 – Swap Chain

The surface exists, but Vulkan still has nothing to draw into. The swapchain is the pool of images the presentation engine cycles through to put frames on the window. This step queries what the surface can actually do, picks sane values out of the answers, and creates the swapchain along with the images it owns.

The full source for this step lives in `src/08_swap_chain/main.odin`.

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/01_Presentation/01_Swap_chain.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Swap_chain>

I'd also suggest taking a look at the following pages:
- Choosing the right number of swapchain images: <https://docs.vulkan.org/samples/latest/samples/performance/swapchain_images/README.html>
- Swapchain Semaphore Reuse: <https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html>

---

## What's new, in one glance

- `choose_swap_extent` — resolves the resolution of the swapchain images.
- `choose_swap_min_image_count` — picks how many images we want, with a floor of 3.
- `get_surface_formats` / `choose_swap_surface_format` — query and pick a pixel format + color space.
- `get_present_modes` / `choose_present_mode` — query and pick a present mode.
- `create_swap_chain` — wires it all into `vk.CreateSwapchainKHR`.
- `get_swap_chain_images` — retrieves the `vk.Image` handles the swapchain created.

`main` calls `create_swap_chain` right after the logical device, then `get_swap_chain_images` to grab the actual images. Cleanup gets a `vkDestroySwapchainKHR` call before the device goes.

---

## The surface support trio

Before building anything, you have to ask the surface what it supports. Three `KHR` calls do the job, one per axis:

- `vkGetPhysicalDeviceSurfaceCapabilitiesKHR` — fills a single `vk.SurfaceCapabilitiesKHR` struct: image counts, extents, transforms, alpha compositing.
- `vkGetPhysicalDeviceSurfaceFormatsKHR` — the supported `(format, colorSpace)` pairs.
- `vkGetPhysicalDeviceSurfacePresentModesKHR` — the supported present modes.

The last two use the two-call pattern you've already seen in steps 04 and 07: ask for the count with `nil`, allocate, fill. In Odin we wrap each pair in its own proc:

```c
formats := make([]vk.SurfaceFormatKHR, surface_format_count)
vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, raw_data(formats))
```

`raw_data(formats)` is the Odin helper that turns a slice into a `rawptr` — what the Vulkan call wants for its array argument. The same trick is used in step 04 for enumeration. Get used to it: every Vulkan call that takes a buffer wants `raw_data(slice)`.

---

## Choosing a format and present mode

`choose_swap_surface_format` walks the list and prefers `B8G8R8A8_SRGB` with `SRGB_NONLINEAR` color space. SRGB for the final image is the sane default for most desktop rendering. If the pair isn't there, we take whatever the implementation declared first — usually a similar 8-bit SRGB format.

`choose_present_mode` looks for `MAILBOX` and falls back to `FIFO`. The difference matters:

- `FIFO` is vsync — first-in-first-out, guaranteed to be available, blocks when the queue is full.
- `MAILBOX` is triple-buffered with a "drop stale frames" twist: the latest submitted image replaces pending ones, so input latency stays low. Not always present, not always infinite-queued, but nice to grab when available.

Vulkan guarantees `FIFO` exists, so the fallback is always safe.

A note on this choice: Khronos's own material tends to recommend `FIFO` and to use `MAILBOX` with care — it can spin the GPU when there's nothing to do and burn power for no visible gain on some stacks. I picked `MAILBOX` anyway because this is a learning project on a desktop machine, and lower input latency is the more interesting behavior to feel early on. For a real application, `FIFO` is usually the safer default to ship with.

---

## The extent, and the `max(u32)` magic value

This is the one Vulkan quirk worth a paragraph.

```c
if capabilities.currentExtent.width != max(u32) {
	return capabilities.currentExtent
}
```

`currentExtent` is the resolution the surface reports as "just use this". If the window manager can't decide — common on some X11 setups — it fills `width` with `0xFFFFFFFF` (all bits set) instead of an actual number. That's the magic value for "you pick".

In Odin, `max(u32)` is the cleanest way to spell `0xFFFFFFFF`. Anything else needs to be clamped into the `[minImageExtent, maxImageExtent]` range ourselves, using the GLFW framebuffer size as input.

---

## How many images

```c
min_image_count := max(3, capabilities.minImageCount)
if 0 < capabilities.maxImageCount && capabilities.maxImageCount < min_image_count {
	min_image_count = capabilities.maxImageCount
}
```

The tutorial asks for `minImageCount + 1` to get one extra image and avoid waiting on the driver during rendering. Here I prefer a hard floor of 3 — triple buffering — then clamp down if the implementation caps us below that. `maxImageCount == 0` means "no upper limit", which is why we guard the clamp with the `0 <` check.

---

## Creating the swapchain

```c
create_info := vk.SwapchainCreateInfoKHR {
	sType            = .SWAPCHAIN_CREATE_INFO_KHR,
	surface          = surface,
	minImageCount    = min_image_count,
	imageFormat      = format.format,
	imageColorSpace  = format.colorSpace,
	imageExtent      = swap_chain_extent,
	imageArrayLayers = 1,
	imageUsage       = {.COLOR_ATTACHMENT},
	imageSharingMode = .EXCLUSIVE,
	preTransform     = surface_capabilities.currentTransform,
	compositeAlpha   = {.OPAQUE},
	presentMode      = present_mode,
	clipped          = true,
}
```

Most of these fields come straight from the queries we just did. A few are deliberately fixed and worth knowing:

- **`imageArrayLayers = 1`** — one layer per image. More than one is for stereoscopic rendering; nothing we need here.
- **`imageUsage = {.COLOR_ATTACHMENT}`** — we'll render color directly into these images. If we wanted to draw into a separate buffer and blit, we'd ask for `{.TRANSFER_DST}` instead. Color attachment is the common case.
- **`imageSharingMode = .EXCLUSIVE`** — the swapchain images are owned by one queue family at a time. Concurrent mode exists for cross-queue-family setups; since our graphics family and present family are the same one, exclusive is correct and simpler.
- **`preTransform = currentTransform`** — accept whatever rotation the surface currently applies. No fancy pre-transform here.
- **`compositeAlpha = {.OPAQUE}`** — no window-compositor alpha blending, the surface is opaque.
- **`clipped = true`** — pixels obscured by other windows can be discarded by the implementation. We don't care about their content.

`vk.CreateSwapchainKHR` is, again, a `KHR` call — the swapchain lives in the `VK_KHR_swapchain` extension, the same one we required from the physical device back in step 04.

---

## The swapchain owns its images

```c
get_swap_chain_images :: proc(device: vk.Device, swap_chain: vk.SwapchainKHR) -> []vk.Image {
	image_count: u32
	vk.GetSwapchainImagesKHR(device, swap_chain, &image_count, nil)
	images := make([]vk.Image, image_count)
	vk.GetSwapchainImagesKHR(device, swap_chain, &image_count, raw_data(images))
	return images
}
```

You don't allocate the swapchain images — the swapchain does. `vkGetSwapchainImagesKHR` is the way to ask "how many did you make, and what are their handles?". Two-call pattern again, `raw_data` again.

The images are owned by the swapchain. We don't `vkDestroyImage` them, ever — `vkDestroySwapchainKHR` cleans them up. That's the kind of ownership rule that's easy to get wrong; just remember: images that come out of a swapchain go away with the swapchain.

In `main`, the slice we get back is `defer delete`d, but that only frees the Odin slice — it doesn't touch the underlying images. Deleting the slice is enough because the storage is heap-allocated by `make`.

---

## Cleanup ordering

```c
if swap_chain != 0 {
	vk.DestroySwapchainKHR(device, swap_chain, nil)
}
if device != nil {
	vk.DestroyDevice(device, nil)
}
```

The swapchain is created from a `vk.Device`, so it must be destroyed before that device. The `0` guard is the same pattern we used for the surface and the instance — null-handle checks are cheap and make teardown order forgiving.

Everything else in cleanup is unchanged from step 07. Surface before instance, device before everything that came from the device.

---

## Test it

Nothing visible yet — the window is still blank. But we now have a real pool of images the GPU can render into and the present engine can show. The next step will wrap them in `VkImageView` so we can actually target them.

---

## What's next

[09 — Image Views](./09_image_views.md) wraps each swapchain image in a `VkImageView`, the standard way to say "I want to look at this image in *this* format, with *this* aspect". You don't draw into raw `VkImage` handles — you always go through an image view.