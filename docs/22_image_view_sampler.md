---
title: 22 - Image view and sampler
nav_order: 24
---

# 22 - Image view and sampler

The texture pixels are now sitting in a Vulkan image in GPU memory, but a raw `vk.Image` can't be sampled by a shader. Two more objects are needed: an *image view* (so the shader knows which part of the image to read, with which format) and a *sampler* (which controls how texels are fetched and filtered). This step creates both, but doesn't wire them into the pipeline yet - that's for the next step.

The full source for this step lives in [src/22_image_view_sampler/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/22_image_view_sampler/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/06_Texture_mapping/01_Image_view_and_sampler.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Texture_mapping/Image_view_and_sampler>

---

## What's new, in one glance

- `create_image_view` (singular) - refactored out of `create_image_views` so a single image view can be created without looping. `create_image_views` now just calls it in a loop.
- `create_sampler` - builds a `vk.Sampler` with linear filtering, repeat addressing and anisotropy enabled.
- `samplerAnisotropy` is now a required device feature, queried in `score_device` and enabled in `create_logical_device`.
- The main function loads the texture image, then creates its image view and a sampler, ready to be wired up next step.
- Cleanup for `vk.Sampler`, `vk.ImageView`, the texture image and its memory.

---

## Image view, refactored

An image view tells the GPU how to interpret the raw pixels of an image: which format, which mip levels and array layers, which aspect (color or depth). A `vk.Image` can't be bound to a descriptor or used as a render target on its own - you always go through a view.

Until now, image views were built by `create_image_views` (plural): one proc that took the swap chain images, looped, and filled a `[]vk.ImageView`. That was fine when every view belonged to the swap chain, but the texture is a single image and creating a one-element slice just to call a plural proc felt wrong. So the singular case is now its own proc, and the plural one delegates to it:

```c
create_image_view :: proc(device: vk.Device, image: vk.Image, format: vk.Format) -> vk.ImageView {
	create_info := vk.ImageViewCreateInfo {
		sType            = .IMAGE_VIEW_CREATE_INFO,
		viewType         = .D2,
		format           = format,
		subresourceRange = {{.COLOR}, 0, 1, 0, 1},
		image            = image,
	}
	image_view: vk.ImageView
	vk_check(vk.CreateImageView(device, &create_info, nil, &image_view), "Failed to create image view!")
	return image_view
}

create_image_views :: proc(device: vk.Device, images: []vk.Image, format: vk.Format) -> []vk.ImageView {
	image_views := make([]vk.ImageView, len(images))
	for image, i in images {
		image_views[i] = create_image_view(device, image, format)
	}
	return image_views
}
```

---

## Sampler

The image holds the raw texels, but the sampler is what decides *how* the shader reads them: linear or nearest filtering, repeat or clamp addressing, anisotropy, mip behavior. With a sampler bound, the shader's `Texture2D.Sample()` call knows what to do for each pixel it computes.

```c
create_sampler :: proc(physical_device: vk.PhysicalDevice, device: vk.Device) -> vk.Sampler {
	props: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(physical_device, &props)

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		anisotropyEnable        = true,
		maxAnisotropy           = props.limits.maxSamplerAnisotropy,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = .LINEAR,
		mipLodBias              = 0.0,
		minLod                  = 0.0,
		maxLod                  = 0.0,
	}

	sampler: vk.Sampler
	vk_check(vk.CreateSampler(device, &sampler_info, nil, &sampler), "Failed to create texture sampler!")
	return sampler
}
```

The interesting bits: `magFilter` and `minFilter` are both `.LINEAR`, so texels get bilinearly interpolated instead of snapping to the nearest one (that's the pixel-art look, not what we want for a photo). `addressModeU/V/W` are `.REPEAT`, which wraps coordinates outside `[0, 1]` around the image - the intuitive default for tiling textures. `unnormalizedCoordinates = false` means the shader uses `[0, 1]` UVs instead of raw texel indices, which is almost always what you want. The mip and compare fields are left at their defaults since we have no mip chain and no shadow mapping.

Anisotropy deserves a paragraph. `anisotropyEnable = true` with `maxAnisotropy` set to the device's limit (queried from `props.limits.maxSamplerAnisotropy`) gives us anisotropic filtering, which reduces the blur you get when a surface is viewed at a grazing angle. The driver picks the actual sample count per fragment based on the viewing angle. The catch is that anisotropy is an *optional* device feature in Vulkan - you have to query it and explicitly enable it before using it. So this step also adds a check in `score_device`:

```c
if !base_f.samplerAnisotropy {
	fmt.printfln("  %q - missing samplerAnisotropy (skipped)", name)
	return -1
}
```

And flips the feature on in `create_logical_device`:

```c
device_feature_2 := vk.PhysicalDeviceFeatures2 {
	sType  = .PHYSICAL_DEVICE_FEATURES_2,
	pNext  = &device_feature_vulkan11,
	features = {samplerAnisotropy = true},
}
```

Nearly every GPU made in the last decade supports it, but Vulkan still makes you ask.

---

## Pipeline still unchanged

The shader hasn't moved from step 20/21 - it still outputs vertex colors and multiplies by the MVP matrices. The descriptor set layout still only declares a `UNIFORM_BUFFER` binding. Nothing in `record_command_buffer` references the texture, the view or the sampler.

That's on purpose: this step is just about creating the objects and keeping them around. The pipeline wiring comes next.

---

## Test it

The startup log mirrors step 21's up to the `Texture image loaded... OK` line, then prints two new lines - `Texture image view... OK` and `Sampler... OK` - before continuing into the uniform buffer setup and the usual `Vulkan initialization completed with success!`.

The window shows the same rotating quad with vertex colors as step 21. The texture is loaded, its view and sampler exist, but nothing uses them yet, so the picture can't change.

If validation complains about `samplerAnisotropy`, double-check that `PhysicalDeviceFeatures2.features` has `samplerAnisotropy = true` and that `score_device` actually checks the feature. If the image fails to load, the path `../../assets/images/statue.jpg` is relative to the working directory, so run from `src/22_image_view_sampler` like the other steps.

---

## What's next

The image view and sampler are ready, but the shader can't reach them yet. The next step adds a combined image sampler descriptor binding, updates the shader to actually sample the texture, and finally displays the statue on the quad. That's [23 - Combined image sampler](./23_combined_image_sampler.md).