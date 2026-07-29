---
title: 32 - ovk Framework Helpers
nav_order: 34
---

# 32 - ovk Framework Helpers

Step 31 finished moving every Vulkan object and every command-recording helper into `libs/ovk/`. At that point `main.odin` was down to about 626 lines, but a lot of what remained was still boilerplate that every Vulkan application needs: swap chain creation tied to a color image and a depth image, the acquire/submit/present trio with its semaphores and fences, swap chain recreation on resize, and the texture loading code that loads a PNG, stages it, transitions the layout, copies, and generates mipmaps.

This step moves all of that into ovk too. The goal stays the same - ovk is a thin abstraction over Vulkan, not an engine. We're not hiding the concepts, we're just grouping the repetitive parts so `main.odin` reads like an application instead of a tutorial chapter.

The full source for this step lives in [src/32_ovk_framework_helpers/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/32_ovk_framework_helpers/main.odin) and [libs/ovk/](https://github.com/Hilderin/OdinVulkan/tree/main/libs/ovk).


## What we want to prove

Nothing changes on screen - the viking room still rotates, MSAA and depth are still there. What we want to prove is that a full Vulkan application (instance, device, swap chain, pipeline, mesh, texture, mipmap, depth, multisampling, frames in flight, resize handling) can fit in a `main.odin` of about 435 lines, with the rest living in a reusable library that stays close to Vulkan's own concepts.

Concretely, three new things land in ovk:

- `Swap_Chain_Helper` in `libs/ovk/swap_chain_helper.odin` - bundles the swap chain, the color and depth images, the semaphores, the fences, and the frame/image indices, and exposes `acquire_next_image`, `submit_and_queue_present`, and automatic recreation.
- `Bitmap` and `load_bitmap_from_file` in `libs/ovk/bitmap.odin` - a small wrapper around `core:image` so the rest of ovk doesn't have to deal with the image loading API directly.
- `create_image_from_file` in `libs/ovk/image.odin` - moves the old `create_texture_image` from `main.odin` into the library and makes the mipmaps optional.

Plus two smaller additions that follow from those:

- `Image` gains a `mip_levels` field, so the image knows its own mip count.
- `mem_copy_to_mapped_buffer` in `buffer.odin` - a typed helper to write into a mapped buffer, which replaces the raw `cast(^T)` pattern in the uniform buffer update.
- `required_extensions` is now exported by `instance.odin` instead of being redeclared in `main.odin`.

And `main.odin`:

- `App` loses `color_image`, `depth_image`, `acquire_semaphores`, `submit_semaphores`, `draw_fences`, and `framebuffer_resized`. The `swap_chain` field is now a `Swap_Chain_Helper` instead of a bare `Swap_Chain`. `samples` and `depth_format` stay on `App` because they're computed from the physical device before the helper exists, and the graphics pipeline needs them too.
- `create_swap_chain`, `destroy_swap_chain`, and `create_texture_image` are gone from `main.odin`.
- The `NB_FRAMES_IN_FLIGHT` constant is gone from `main.odin`; the helper owns it.
- The render loop no longer keeps a local `frame_index`, and the `framebuffer_resize_callback` is gone - recreation is driven by the return value of `acquire_next_image` / `queue_present` and handled inside the helper.
- The application code drops from about 626 lines to about 435.


## The Swap_Chain_Helper

The biggest addition. The swap chain in a real application is never just a `vk.SwapchainKHR`. It drags along a color (multisample resolve) image, a depth image, one acquire semaphore per frame in flight, one submit semaphore per swap chain image, one draw fence per frame in flight, and the two indices that track which frame we're on and which image we're rendering to. Step 31 had all of that spread across the `App` struct and three procs in `main.odin`. Now it's one struct:

```c
Swap_Chain_Helper :: struct {
	device:              ^Device,
	window:              ^Window,
	swap_chain_args:     Create_Swap_Chain_Args,
	samples:             vk.SampleCountFlags,
	depth_format:        vk.Format,
	acquire_semaphores:  []Semaphore,
	draw_fences:         []Fence,
	nb_frames_in_flight: u32,
	frame_index:         u32, // Frame in flight to render
	image_index:         u32, // Image index in the swap chain to render to	

	// Elements recreated when the swap chain needs recreation
	swap_chain:          Swap_Chain,
	color_image:         Image,
	depth_image:         Image,
	submit_semaphores:   []Semaphore,
	extent:              vk.Extent2D,
	format:              vk.Format,
	color_space:         vk.ColorSpaceKHR,
	images:              []Image,
}
```

The split is deliberate. Everything above the comment is created once and lives for the lifetime of the helper. Everything below the comment is recreated when the swap chain goes out of date. `acquire_semaphores` and `draw_fences` are indexed by `frame_index` (frames in flight), `submit_semaphores` is indexed by `image_index` (swap chain images). That's also why `submit_semaphores` is recreated with the swap chain while `acquire_semaphores` and `draw_fences` are not - see the note in `create_swap_chain_internal` about the [swap chain semaphore reuse guideline](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).

### Creation

`create_swap_chain_helper` takes a single args struct and returns the helper. The samples and depth format have to be provided up front because they drive the color and depth image formats, and they depend on the physical device - the application computes them with `get_max_usable_sample_count` and `find_depth_format` before building the helper:

```c
app.swap_chain = ovk.create_swap_chain_helper(
    {swap_chain_args = {device = &app.device, window = &app.window}, samples = app.samples, depth_format = app.depth_format},
) or_return
```

Internally it stores everything, then calls a `@(private = "file")` proc, `create_swap_chain_internal`, which builds the `Swap_Chain`, the color image, the depth image, and the `submit_semaphores`. The samples and depth format are part of the args and not auto-detected because they're properties of the physical device, not of the swap chain - the whole point of ovk is to keep Vulkan concepts visible, not to guess for you.

`nb_frames_in_flight` defaults to `DEFAULT_NB_FRAMES_IN_FLIGHT` (= 2) when 0 is passed:

```c
swap_chain_helper.nb_frames_in_flight = args.nb_frames_in_flight > 0 ? args.nb_frames_in_flight : DEFAULT_NB_FRAMES_IN_FLIGHT
```

This is why `main.odin` doesn't need its own `NB_FRAMES_IN_FLIGHT` constant anymore. Everything that used to reference `NB_FRAMES_IN_FLIGHT` now references `app.swap_chain.nb_frames_in_flight`:

```c
app.descriptor_pool = ovk.create_descriptor_pool(
    {
        device = &app.device,
        pool_sizes = {
            {type = .UNIFORM_BUFFER, descriptorCount = app.swap_chain.nb_frames_in_flight},
            {type = .COMBINED_IMAGE_SAMPLER, descriptorCount = app.swap_chain.nb_frames_in_flight},
        },
        max_sets = app.swap_chain.nb_frames_in_flight,
    },
) or_return
```

### Acquire, submit, present

The three operations the render loop used to do by hand now have one-liners:

```c
swap_chain_helper_acquire_next_image :: proc(swap_chain_helper: ^Swap_Chain_Helper) -> (acquired: bool, err: Error)
swap_chain_helper_submit_and_queue_present :: proc(swap_chain_helper: ^Swap_Chain_Helper, command_buffer: ^Command_Buffer) -> (err: Error)
```

`acquire_next_image` returns an `acquired` bool instead of an image index. When the swap chain is out of date (resize, suboptimal) it recreates the swap chain internally and returns `acquired = false`, so the application can `continue` to the next iteration of the event loop without trying to record into a stale image. The current image index is kept in `swap_chain_helper.image_index` for the caller to read.

`submit_and_queue_present` does the `submit_command_buffer` call (signaling the per-image submit semaphore and waiting on the per-frame acquire semaphore), then `queue_present`, then advances `frame_index`. If `queue_present` reports the swap chain as out of date it recreates it before returning. The whole render loop in `main.odin` shrinks to:

```c
for !ovk.window_should_close(&app.window) && app.running {
    ovk.poll_events()

    if acquired := ovk.swap_chain_helper_acquire_next_image(&app.swap_chain) or_return; !acquired {
        continue
    }

    update_uniform_buffer(start_time, &app.ubo_mapped_buffers[app.swap_chain.frame_index], app.swap_chain.extent)

    record_command_buffer(
        &app.graphics_command_buffers[app.swap_chain.frame_index],
        &app.swap_chain.images[app.swap_chain.image_index],
        app.swap_chain.extent,
        &app.graphics_pipeline,
        &app.vertex_buffer,
        &app.index_buffer,
        u32(app.index_buffer.size / size_of(u32)),
        &app.descriptor_sets[app.swap_chain.frame_index],
        &app.swap_chain.depth_image,
        &app.swap_chain.color_image,
    )

    ovk.swap_chain_helper_submit_and_queue_present(&app.swap_chain, &app.graphics_command_buffers[app.swap_chain.frame_index]) or_return
}
```

Notice that `frame_index` and `image_index` are no longer local variables in the loop - they live on the helper and are read through `app.swap_chain.frame_index` / `app.swap_chain.image_index`. There's one source of truth for "which frame are we on", and the helper is the one advancing it.

### Recreation, and the resize callback that disappeared

In step 31 the recreation path was hand-written inside the loop:

```c
if swap_chain_recreation_needed || app.framebuffer_resized {
    fmt.println("Swap chain recreation...")
    width, height := ovk.get_window_size(&app.window)
    for width == 0 && height == 0 { ... }
    app.framebuffer_resized = false
    ovk.wait_idle_device(&app.device)
    destroy_swap_chain(app)
    create_swap_chain(app) or_return
}
```

That whole block is gone. The helper has a private `swap_chain_helper_recreate_swap_chain` proc that handles the minimized-window loop (waiting on `wait_events` until the window has a non-zero size), calls `wait_idle_device`, destroys, and recreates. It's called automatically from `acquire_next_image` and `submit_and_queue_present` whenever Vulkan reports `SUBOPTIMAL_KHR` or `ERROR_OUT_OF_DATE_KHR`.

The consequence is that the `framebuffer_resize_callback` and the `framebuffer_resized` flag are gone. In step 31 the callback was a way to recreate the swap chain proactively on resize, but it pulls a global-ish flag into the `App` struct and complicates the loop with an extra branch. Instead, everything now relies on the return values of `vkAcquireNextImageKHR` and `vkQueuePresentKHR` to signal a stale swap chain - and in practice that's enough. Resizing the window works fine: the next `acquire` (or the next `present`) reports `SUBOPTIMAL_KHR` or `ERROR_OUT_OF_DATE_KHR`, the helper recreates the swap chain, and rendering continues. It's simpler to manage, it all lives inside the helper, and it removes the callback from `main.odin` entirely.

One thing to keep in mind: because recreation now happens *inside* `acquire_next_image`, a frame where the swap chain was out of date returns `acquired = false` and the loop skips straight to the next iteration. There's no half-recorded command buffer, no submit with a recycled semaphore - the helper recreates everything cleanly before the next attempt.


## Bitmap

`bitmap.odin` is a small file. It exists so `image.odin` (and any future texture helper) doesn't talk to `core:image` directly. The struct:

```c
Bitmap :: struct {
    width:     u32,
    height:    u32,
    channels:  u32,
    depth:     u32,
    pixels:    []u8,
    src_image: ^img.Image,
}
```

`load_bitmap_from_file` calls `img.load` with the given options and copies the dimensions and a `[]u8` view of the pixels into the struct. `destroy_bitmap` calls `img.destroy` on the source image. The caller carries the `Bitmap` around (or, like `create_image_from_file`, defers its destruction) and reads from `pixels`.

There's the usual Odin quirk in this file: `core:image/png` and `core:image/jpeg` need to be imported so that `img.load` actually understands those formats, but the imports themselves aren't used by name. The file handles it the same way `main.odin` did in step 31:

```c
import img "core:image"
import "core:image/jpeg"
import "core:image/png"

_ :: png
_ :: jpeg
```

`Options` is just re-exported from `core:image` so callers can write `ovk.load_bitmap_from_file(path, {.alpha_add_if_missing})` without having to import `core:image` themselves.

The `Bitmap` carries a `depth` field even though we only ever deal with 2D textures. It's there because `img.Image` has it and it costs nothing to pass through; if you ever load something unusual you'll want it.


## create_image_from_file

The old `create_texture_image` proc that lived in `main.odin` is now `create_image_from_file` in `image.odin`. Same logic, two differences worth noting.

First, it takes a `mipmaps: bool` parameter instead of always generating them:

```c
create_image_from_file :: proc(path: string, mipmaps: bool, command_pool: ^Command_Pool, queue: ^Queue) -> (image: Image, err: Error)
```

When `mipmaps` is false, `mip_levels` is forced to 1 and the `cmd_generate_mipmaps` call is skipped. The mip level count, when enabled, is computed the same way as before - `floor(log2(max(width, height))) + 1`. The call site passes `true` for the viking room texture, so the behaviour is unchanged, but a flat 2D UI texture could now be loaded with `mipmaps = false` and avoid the blit barrier overhead.

Second, it uses the new `Bitmap` instead of dealing with `img.Image` and `bytes.buffer_to_bytes` directly:

```c
src_bitmap := load_bitmap_from_file(path, {.alpha_add_if_missing}) or_return
defer destroy_bitmap(&src_bitmap)

assert(src_bitmap.channels == 4, "Image should have 4 channels (rgba).") or_return

size := u64(src_bitmap.width) * u64(src_bitmap.height) * u64(src_bitmap.channels)
```

Because `bitmap.pixels` is already a `[]u8`, `mem_copy_to_buffer` no longer needs the `bytes.buffer_to_bytes` dance from step 31. The bitmap is destroyed with `defer` right after the staging copy, which is cleaner than the old `img.destroy(src_image)` sitting in the middle of the proc.

The staging -> transition -> copy -> (mipmaps) -> submit sequence is unchanged. The interesting bit, and the reason this proc is a good fit for ovk, is that it composes four existing helpers - `create_buffer`, `create_one_time_command_buffer`, `cmd_transition_image_layout`, `cmd_copy_buffer_to_image`, and `cmd_generate_mipmaps` - into one operation without exposing any new Vulkan concept. It's a recipe, not an abstraction.

In `main.odin` the whole thing collapses to:

```c
app.texture = ovk.create_image_from_file("../../assets/models/viking_room/viking_room.png", true, &app.graphics_command_pool, &app.device.graphics_queue) or_return
```

## mem_copy_to_mapped_buffer

Step 31's `update_uniform_buffer` ended with a raw cast:

```c
ubo := Uniform_Buffer_Object { ... }
mapped_ubo := cast(^Uniform_Buffer_Object)ubo_map_memory_ptr
mapped_ubo^ = ubo
```

That works, but it leans on the caller knowing the mapped pointer's true type. `buffer.odin` now exposes a typed helper that hides the cast:

```c
mem_copy_to_mapped_buffer :: proc(data: $T, dest_mapped_buffer: ^Mapped_Buffer) {
    mapped_data := cast(^T)dest_mapped_buffer.ptr
    mapped_data^ = data
}
```

It's generic on `T`, so the assignment still does a plain Odin value copy (no extra allocation, no memcpy). The call in `update_uniform_buffer` becomes:

```c
ovk.mem_copy_to_mapped_buffer(
    Uniform_Buffer_Object {
        model = la.matrix4_rotate(angle, vec3{0.0, 0.0, 1.0}),
        view  = la.matrix4_look_at(vec3{2.0, 2.0, 2.0}, vec3{0.0, 0.0, 0.0}, vec3{0.0, 0.0, 1.0}),
        proj  = ovk.matrix4_perspective_vulkan(math.to_radians_f32(45.0), aspect, 0.1, 10.0),
    },
    ubo_mapped_buffer,
)
```

It's a one-line win in readability, but more importantly it keeps the unsafe `cast` inside the library and out of application code. The application passes a value of type `T` and a `^Mapped_Buffer`; the library handles the type punning.


## required_extensions moved into ovk

In step 31, `main.odin` declared:

```c
required_extensions := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
```

and passed it to both `get_physical_device` and `create_logical_device`. With ovk wrapping more of the device setup, it made sense to move that constant into `instance.odin`:

```c
required_extensions :: []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
```

It's exported, so `main.odin` just writes `ovk.required_extensions`. The swap chain extension is a property of "we want to present to a window", which is exactly the kind of shared knowledge that belongs in the library rather than the application. If ovk ever grows a "headless render" path it'll be the natural place to vary this list.


## The App struct, after

With the helper owning the swap chain and its dependencies, the `App` struct in `main.odin` shrinks noticeably. Compare the swap chain related fields:

```c
// Step 31:
swap_chain:               ovk.Swap_Chain,
samples:                  vk.SampleCountFlags,
color_image:              ovk.Image,
depth_format:             vk.Format,
depth_image:              ovk.Image,
acquire_semaphores:       []ovk.Semaphore,
submit_semaphores:        []ovk.Semaphore,
draw_fences:              []ovk.Fence,
framebuffer_resized:      bool,

// Step 32:
swap_chain:               ovk.Swap_Chain_Helper,
samples:                  vk.SampleCountFlags,
depth_format:             vk.Format,
```

`samples` and `depth_format` are still on `App` because they're computed from the physical device before the helper exists, and the graphics pipeline needs them too. But the color image, the depth image, the three semaphore/fence slices, and the `framebuffer_resized` flag are all gone - they live on the helper now. The `destroy_app` cleanup loses the corresponding six lines and just calls `ovk.destroy_swap_chain_helper(&app.swap_chain)`.

The render loop in `run_app` no longer keeps a local `frame_index` either; it reads `app.swap_chain.frame_index` and `app.swap_chain.image_index` directly, and the helper advances `frame_index` inside `submit_and_queue_present`.


## destroy_app is now one line of ovk calls, in reverse order

Nothing clever here, but worth noting that the cleanup order is unchanged from step 31, just shorter. The application-owned resources (ubo buffers, sampler, texture, vertex/index buffers, command buffers, command pool, pipeline, descriptor sets) are torn down first, then the helper, then the device, window, instance:

```c
destroy_app :: proc(app: ^App) {
    ovk.destroy_mapped_buffers(app.ubo_mapped_buffers)
    ovk.destroy_buffers(app.ubo_buffers)
    ovk.destroy_sampler(&app.sampler)
    ovk.destroy_image(&app.texture)
    ovk.destroy_buffer(&app.index_buffer)
    ovk.destroy_buffer(&app.vertex_buffer)
    ovk.destroy_command_buffers(app.graphics_command_buffers)
    ovk.destroy_command_pool(&app.graphics_command_pool)
    ovk.destroy_graphics_pipeline(&app.graphics_pipeline)
    ovk.destroy_descriptor_sets(app.descriptor_sets)
    ovk.destroy_descriptor_pool(&app.descriptor_pool)
    ovk.destroy_descriptor_set_layout(&app.descriptor_set_layout)
    ovk.destroy_shader(&app.shader)
    ovk.destroy_swap_chain_helper(&app.swap_chain)
    ovk.destroy_logical_device(&app.device)
    ovk.destroy_window(&app.window)
    ovk.destroy_instance(&app.instance)
    ovk.destroy_glfw()
}
```

The order matters because the helper still owns GPU resources (color image, depth image, submit semaphores) that were created with the device, so the device has to outlive the helper, and the instance has to outlive the device, and GLFW last.


## Test it

The window should show the rotating viking room with MSAA still on. Resize the window: the rendering should keep going without artifacts, no stutter, no validation errors. Minimize then restore: the helper blocks on `wait_events` until the window has a non-zero size, then recreates and continues - again, no crash, no validation error about presenting to a zero-sized surface. The recreation happens silently now - there's no console output for it anymore, so the only way to tell it happened is that the window keeps rendering correctly.

A few things to watch for:

- **`Image should have 4 channels (rgba)`** - means the texture you passed to `create_image_from_file` isn't RGBA. The assert is in ovk now, but the fix is the same: convert the source image, or load it with the `{.alpha_add_if_missing}` option (which `create_image_from_file` already does internally).
- **Validation error about a semaphore in use during recreation** - this was the whole reason `submit_semaphores` is per-swap-chain-image and recreated with the swap chain. If you ever see it, double-check that nothing is holding on to a `submit_semaphores` element after `destroy_swap_chain_internal` has run.
- **Stale `frame_index` after recreation** - shouldn't happen, because the helper doesn't reset `frame_index` on recreation (frames in flight count doesn't change), but if you ever swap the helper for something that varies `nb_frames_in_flight` per recreation, watch the modulo.

And the usual sanity check from previous steps still applies: comment out a `destroy_*` call in `destroy_app`, run, exit, and the validation layers should complain about a leaked object before the process terminates.


## What's next

The refactoring that started in step 29 is now well past "move the boilerplate". ovk covers instance, device, swap chain (with the whole acquire/submit/present/recreation cycle), command buffers and recording, buffers and transfers, images and textures (with mipmaps), samplers, descriptors, the graphics pipeline, models, and windowing. `main.odin` is application code: the vertex layout, the UBO struct, the per-frame command buffer recording, and the event loop.

What's left is whatever you actually want to render. The obvious candidates from here: push constants for small per-draw data instead of uniform buffers, multiple meshes with their own descriptor sets and model matrices, a proper scene graph, or going the other direction and exploring compute shaders using the same `Command_Pool` / `Command_Buffer` helpers we already have.