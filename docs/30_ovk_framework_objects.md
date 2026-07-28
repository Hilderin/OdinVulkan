---
title: 30 - ovk Framework Objects
nav_order: 32
---

# 30 - ovk Framework Objects

Step 29 extracted the foundation layer (instance, device, window, physical device) into `libs/ovk/`. This step goes further and wraps the remaining Vulkan objects: swap chain, buffers, images, shader modules, graphics pipelines, descriptor set layouts, descriptor pools and descriptor sets.

The full source for this step lives in [src/30_ovk_framework_objects/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/30_ovk_framework_objects/main.odin) and [libs/ovk/](https://github.com/Hilderin/OdinVulkan/tree/main/libs/ovk).


## What we're doing

Same viking room with MSAA, same rendering loop. Nothing changes visually. What changes is the code organisation:

- **libs/ovk/buffer.odin** - wraps `vk.Buffer` + `vk.DeviceMemory` into a `Buffer` struct.
- **libs/ovk/image.odin** - wraps `vk.Image` + `vk.DeviceMemory` + `vk.ImageView` into an `Image` struct.
- **libs/ovk/swap_chain.odin** - wraps the swap chain, its images, and image views into a `Swap_Chain` struct.
- **libs/ovk/shader.odin** - wraps shader compilation and module creation into a `Shader` struct.
- **libs/ovk/shader_compiler.odin** - moved out of `main.odin` into the library.
- **libs/ovk/graphics_pipeline.odin** - wraps the pipeline + pipeline layout into a `Graphics_Pipeline` struct.
- **libs/ovk/descriptor_set_layout.odin / descriptor_pool.odin / descriptor_set.odin** - each wrapper owns its Vulkan handle and knows how to destroy it.
- **libs/ovk/descriptor_set.odin** also introduces a pattern that will appear elsewhere: two creation methods - `create_descriptor_set` (singular, returns one `Descriptor_Set`) and `create_descriptor_sets` (plural, takes a count and returns `[]Descriptor_Set`).

The pattern is the same for every object: a struct that bundles the Vulkan handle with a back-reference to the parent `Device`, a `create_*` function that takes a `Create_*_Args` struct, and a `destroy_*` function that checks for nil handles before calling Vulkan.

The main.odin went from about 1960 lines (step 29) to about 1248 lines - roughly 700 lines removed, all of them raw Vulkan boilerplate that is now in the library.


## The pattern: struct + args + create/destroy

Every wrapper follows the same shape. Here is `Buffer` as an example:

```c
Buffer :: struct {
    device:           ^Device,    // back-reference for destroy
    vk_buffer:        vk.Buffer,
    vk_device_memory: vk.DeviceMemory,
}

Create_Buffer_Args :: struct {
    device:         ^Device,
    size:           u64,
    usage:          vk.BufferUsageFlags,
    mem_properties: vk.MemoryPropertyFlags,
}

create_buffer :: proc(args: Create_Buffer_Args) -> (buffer: Buffer, err: Error) {
    // ... create vk.Buffer, allocate memory, bind ...
    buffer.device = args.device
    return
}

destroy_buffer :: proc(buffer: ^Buffer) {
    if buffer == nil || buffer.device == nil || buffer.device.vk_device == nil {
        return
    }
    if buffer.vk_device_memory != 0 { vk.FreeMemory(...) }
    if buffer.vk_buffer != 0 { vk.DestroyBuffer(...) }
}
```

Three design decisions worth calling out:

1. **The `args` struct pattern**. Instead of a 7-parameter function, you get a struct with named fields. Odin doesn't have default arguments, but struct literal fields can be omitted if they have a zero default. If a new field is added later, existing callers don't break.

2. **Every wrapper stores a `device` pointer**. This is what makes `destroy_*` self-contained - no need to pass the device every time you want to clean up. The downside is that the device must outlive the objects that reference it, but since destruction happens in reverse creation order, that's guaranteed as long as you're careful.

3. **Safe destruction**. Every `destroy_*` function checks for nil devices and zero handles. Calling `destroy_buffer` on a zero-initialized `Buffer` is a no-op. This makes cleanup code simpler - no need to guard every call with a nil check.

`Image` follows the same pattern but goes one step further: `create_image` also creates the image view internally. The `Create_Image_Args` struct has an `aspect_flags` field specifically for the view. This means every `Image` wrapper always carries a view, which is practical (most images are sampled or rendered to through a view) but means you can't create an image-only object without also getting a view.

```c
Image :: struct {
    device:           ^Device,
    vk_image:         vk.Image,
    vk_device_memory: vk.DeviceMemory,
    vk_image_view:    vk.ImageView,
}

Create_Image_Args :: struct {
    device:         ^Device,
    width:          u32,
    height:         u32,
    mip_levels:     u32,
    samples:        vk.SampleCountFlags,
    format:         vk.Format,
    usage:          vk.ImageUsageFlags,
    mem_properties: vk.MemoryPropertyFlags,
    aspect_flags:   vk.ImageAspectFlags,
}
```


## Single vs array: two creation methods

Most ovk objects are one-to-one with a Vulkan handle - one `Buffer` wraps one `vk.Buffer`. But some objects, like descriptor sets, are commonly created in batches. Vulkan's `AllocateDescriptorSets` already works this way: you pass a count and get an array back.

`descriptor_set.odin` exposes both paths:

```c
Create_Descriptor_Sets_Args :: struct {
    descriptor_pool:       ^Descriptor_Pool,
    descriptor_set_layout: ^Descriptor_Set_Layout,
}

// Singular: returns a single Descriptor_Set value.
create_descriptor_set :: proc(args: Create_Descriptor_Sets_Args) -> (descriptor_set: Descriptor_Set, err: Error)

// Plural: takes a count, returns a slice.
create_descriptor_sets :: proc(args: Create_Descriptor_Sets_Args, descriptor_count: u32) -> (descriptor_sets: []Descriptor_Set, err: Error)
```

The singular version is a thin wrapper around the plural one - it calls `create_descriptor_sets(args, 1)`, takes the first element, frees the temporary slice, and returns a single `Descriptor_Set`.

The `Create_Descriptor_Sets_Args` struct holds the shared dependencies (pool and layout) but **not** the count. The count is a separate parameter on `create_descriptor_sets` only. This way the singular `create_descriptor_set` never receives a count at all - there's no risk of passing `1` to the wrong function.

This "args struct for dependencies, count as a separate parameter" will be the pattern for every ovk function that can create multiple objects at once. It keeps the singular API clean (no unused count parameter) and the plural API explicit (you always see how many you're creating).


## The swap chain owns everything

In step 29 the swap chain was a loose collection of local variables: `swap_chain`, `swap_chain_extent`, `swap_chain_format`, `swap_chain_images`, `swap_chain_image_views`. Creating and destroying them was done with separate functions that each had their own parameter list.

Now `Swap_Chain` bundles it all:

```c
Swap_Chain :: struct {
    device:        ^Device,
    vk_swap_chain: vk.SwapchainKHR,
    extent:        vk.Extent2D,
    format:        vk.Format,
    color_space:   vk.ColorSpaceKHR,
    images:        []Image,
}
```

The `create_swap_chain` function fills every field. The `destroy_swap_chain` function destroys image views, frees the slices, and destroys the swap chain handle. The main code no longer manages these individually.

The swap chain has its own `create_swap_chain` / `destroy_swap_chain` pair in `main.odin` rather than in the library, because it also creates the color and depth resources that depend on the swap chain extent. That's an application-level concern - ovk doesn't know about your multisampling setup or your depth format choice. The lib handles the raw swap chain creation (in `libs/ovk/swap_chain.odin`), and the app layer wraps it with the extra resources (in `main.odin`'s `create_swap_chain`).

```c
create_swap_chain :: proc(app: ^App) -> (err: ovk.Error) {
    app.swap_chain = ovk.create_swap_chain({...}) or_return

    app.samples = ovk.get_max_usable_sample_count(&app.physical_device)
    app.color_image = ovk.create_image({...}) or_return
    app.depth_format = ovk.find_depth_format(&app.physical_device) or_return
    app.depth_image = ovk.create_image({...}) or_return
    return
}
```


## Graphics pipeline: one proc, one struct

The old `create_graphics_pipeline` returned two values (a `vk.Pipeline` and a `vk.PipelineLayout`). The new one returns a `Graphics_Pipeline` struct:

```c
Graphics_Pipeline :: struct {
    device:             ^Device,
    vk_pipeline:        vk.Pipeline,
    vk_pipeline_layout: vk.PipelineLayout,
}
```

The vertex attributes are now passed as an argument instead of being hardcoded inside the function. The `Create_Graphics_Pipeline_Args` takes a `vertex_attributes_stride` and a `[]vk.VertexInputAttributeDescription` slice, letting the caller describe the vertex layout without the function knowing about `Vertex`:

```c
app.graphics_pipeline = ovk.create_graphics_pipeline({
    device                   = &app.device,
    shader                   = &app.shader,
    vertex_entry_point       = "vertMain",
    fragment_entry_point     = "fragMain",
    swap_chain_format        = app.swap_chain.format,
    descriptor_set_layout    = &app.descriptor_set_layout,
    vertex_attributes_stride = size_of(Vertex),
    vertex_attributes        = {
        {binding = 0, location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, pos))},
        {binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, color))},
        {binding = 0, location = 2, format = .R32G32_SFLOAT, offset = u32(offset_of(Vertex, texCoord))},
    },
    depth_format             = app.depth_format,
    samples                  = app.samples,
}) or_return
```

## What stayed in main.odin

The rendering-specific code is still in `main.odin`, and that's intentional. ovk wraps *objects* (buffers, images, pipelines, etc.) but not *operations* (recording command buffers, submitting work, presenting). Those are application-level concerns:

- `create_command_pool` / `create_command_buffers` / `begin_command_buffer` / `end_command_buffer`
- `begin_rendering` / `end_rendering`
- `record_command_buffer`
- `transition_image_layout` / `generate_mipmaps`
- `submit_command_buffer` / `acquire_next_image` / `queue_present`
- `mem_copy_to_buffer` / `transfer_to_buffer`
- `create_sampler` / `create_texture_image` / `load_model`
- `update_uniform_buffer` / `update_descriptor_set`
- `create_semaphore` / `create_fence` / `wait_for_fence` / `reset_fence`

These are the next candidates for the library. The pattern will be the same: a struct wrapper, an args struct, and a create/destroy pair. But the order matters - command pools depend on command buffers, which depend on the recording logic. That's the next step.


## The App struct grows

The `App` struct now owns every ovk object:

```c
App :: struct {
    instance:              ovk.Instance,
    window:                ovk.Window,
    physical_device:       ovk.Physical_Device,
    device:                ovk.Device,
    swap_chain:            ovk.Swap_Chain,
    shader:                ovk.Shader,
    descriptor_set_layout: ovk.Descriptor_Set_Layout,
    descriptor_pool:       ovk.Descriptor_Pool,
    descriptor_sets:       []ovk.Descriptor_Set,
    samples:               vk.SampleCountFlags,
    color_image:           ovk.Image,
    depth_format:          vk.Format,
    depth_image:           ovk.Image,
    graphics_pipeline:     ovk.Graphics_Pipeline,
}
```

And the cleanup in `destroy_app` reflects the creation order, reversed:

```c
destroy_app :: proc(app: ^App) {
    ovk.destroy_graphics_pipeline(&app.graphics_pipeline)
    ovk.destroy_descriptor_sets(app.descriptor_sets)
    ovk.destroy_descriptor_pool(&app.descriptor_pool)
    ovk.destroy_descriptor_set_layout(&app.descriptor_set_layout)
    ovk.destroy_shader(&app.shader)
    destroy_swap_chain(app)
    ovk.destroy_logical_device(&app.device)
    ovk.destroy_window(&app.window)
    ovk.destroy_instance(&app.instance)
    ovk.destroy_glfw()
}
```

`destroy_descriptor_sets` frees both the Odin slice and, if the pool was created with `{.FREE_DESCRIPTOR_SET}`, the individual Vulkan descriptor sets. The flags live on `Descriptor_Pool` - the set just reads them from its pool reference, which avoids storing the same flag on every `Descriptor_Set` struct. If the pool was created with `flags = {}` (the default), `vkFreeDescriptorSets` is skipped and the sets are cleaned up when `destroy_descriptor_pool` runs.


## What's next

This step gets ovk to the point where every major Vulkan object has a wrapper. The command buffer and rendering code is still raw - `begin_command_buffer`, `transition_image_layout`, `begin_rendering`, `end_rendering`, `submit_command_buffer`, and friends still live in `main.odin`. The [next step](./31_ovk_framework_commands.md) wraps command pools and command buffers, pulls the recording helpers into the library, and redistributes the remaining loose helpers into their proper files so the rendering loop becomes as clean as the initialisation path.
