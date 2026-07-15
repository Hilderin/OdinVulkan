---
title: 09 - Image Views
nav_order: 11
---

# 09 – Image Views

The swapchain now owns a pool of `vk.Image` handles, but you don't draw into raw images. Every operation that reads from or writes to an image - render passes, framebuffer attachments, descriptor bindings - goes through a `vk.ImageView`. An image view is the "lens" you put on top of an image: same pixels, but with an explicit interpretation (format, aspect, mip range, layer range).

This step wraps every swapchain image in its own view. Nothing visible changes yet - several steps still stand between us and the first triangle (shaders, the graphics pipeline, framebuffers), but the views are the last image-related piece of setup.

The full source for this step lives in [src/09_image_views/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/09_image_views/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/01_Presentation/02_Image_views.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Image_views>

---

## What's new, in one glance

- `create_swap_chain` now also returns the chosen `vk.Format` - the views need it, and we already picked it inside the proc.
- `create_image_views` - loops over the swapchain images and creates one `vk.ImageView` per image with `vk.CreateImageView`.
- Cleanup calls `vk.DestroyImageView` for each view before destroying the swapchain.

`main` threads the new format out of `create_swap_chain` and feeds it, along with the image slice, into `create_image_views`.

---

## The format, propagated

```c
create_swap_chain :: proc(...) -> (vk.SwapchainKHR, vk.Format) {
	// ...
	return swap_chain, format.format
}
```

In step 08 the format was an internal detail - we picked it, passed it to `vk.SwapchainCreateInfoKHR`, and forgot about it. Now we need it back in `main`, because the image views have to be created with the same format the swapchain was created with. The cleanest way to do that without re-querying anything is to return it from `create_swap_chain`.

This is a recurring Vulkan pattern: the values you used at creation time are the values you need at use time. There's no "what format is this swapchain?" query in the API - you're expected to remember.

---

## What an image view actually is

A `vk.ImageView` is *not* a copy of the image and *not* a sub-image. It's a small descriptor that says:

- **`viewType`** - how to interpret the image's dimensions: 1D, 2D, 3D, cube, array, etc. Our swapchain images are plain 2D, so `.D2`.
- **`format`** - how to interpret the texel layout. Must be compatible with the image's own format. We reuse the swapchain format, so they match by construction.
- **`subresourceRange`** - which mip levels and array layers this view exposes, and which aspect (color, depth, stencil). A swapchain image with one mip and one layer, viewed as color, is `{% raw %}{{.COLOR}, 0, 1, 0, 1}{% endraw %}` - aspect mask, base mip level, mip count, base layer, layer count.

That's the whole story. The view doesn't allocate memory, doesn't duplicate pixels, doesn't survive on its own - destroy it and the underlying image is untouched. You'll create views for many things over the program's lifetime; this first batch is just the most mechanical one.

---

## `vk.CreateImageView` and per-image `create_info`

{% raw %}
```c
create_info := vk.ImageViewCreateInfo {
	sType            = .IMAGE_VIEW_CREATE_INFO,
	viewType         = .D2,
	format           = swap_chain_format,
	subresourceRange = {{.COLOR}, 0, 1, 0, 1},
}

image_views := make([]vk.ImageView, len(images))
for image, i in images {
	create_info.image = image
	vk_check(vk.CreateImageView(device, &create_info, nil, &image_views[i]), "Failed to create image view!")
}
```
{% endraw %}

The create info is built *once* outside the loop, because every swapchain view shares the same type, format and subresource range - only the `image` field changes. Mutating a single struct in place instead of rebuilding it per iteration is the obvious move once you notice it, and it's how the C++ tutorial does it too. The only Odin-specific bit here is the slice pre-allocation: `make([]vk.ImageView, len(images))` gives us one contiguous block of handles, which is nicer to own and clean up than a `[dynamic]`.

---

## Cleanup, and a slice-of-handles gotcha

```c
if swap_chain_image_views != nil {
	for image_view in swap_chain_image_views {
		vk.DestroyImageView(device, image_view, nil)
	}
	delete(swap_chain_image_views)
}
```

Two things worth noting, both already seen in step 08 with the swapchain image slice:

- **`vk.DestroyImageView` per handle, then `delete` the slice.** The `delete` only frees the Odin slice's backing storage - it doesn't touch the Vulkan handles. Vulkan objects created with a ` vk.Create*` call need their matching `vk.Destroy*` call, always, manually. Order matters: the views must be destroyed *before* the device they were created from, and *before* the swapchain whose images they reference.
- **The `nil` guard** on the slice is the same defensive habit we keep elsewhere. An empty slice from `make` is technically not `nil`, so the guard only fires if `create_image_views` ever returns early - but again, it costs nothing.

There's no `defer` on the views slice in `main` because the per-handle destroy loop must run explicitly before the rest of cleanup; a bare `defer delete(swap_chain_image_views)` would free the storage and leave the Vulkan handles dangling. The pattern is: own the handles with an explicit loop, then free the storage.

---

## Test it

The window is still blank - no rendering yet - but every piece of plumbing a frame needs now exists: images, views, device, surface, swapchain. From here on, every step adds rendering work, not more setup.

---

## What's next

With image views in hand, the next step is creating shaders - the shaders and fixed-function state that turn "draw a triangle" into actual GPU work. First step for using shaders is compiling them, that's [10 - Shaders Compilation](./10_shaders_compilation.md).