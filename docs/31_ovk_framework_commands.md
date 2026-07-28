---
title: 31 - ovk Framework Commands
nav_order: 33
---

# 31 - ovk Framework Commands

Step 30 wrapped every major Vulkan object in an ovk struct. But the command buffer and synchronisation code - `create_command_pool`, `begin_command_buffer`, `transition_image_layout`, `submit_command_buffer`, semaphore and fence helpers - was still in `main.odin`. This step finishes the refactoring by moving command recording, synchronisation primitives, buffer transfers, and the model loader into ovk. On top of that, `utils.odin` was split up: what was a single file mixing error helpers, physical device queries, and buffer transfers now lives where it belongs.

The full source for this step lives in [src/31_ovk_framework_commands/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/31_ovk_framework_commands/main.odin) and [libs/ovk/](https://github.com/Hilderin/OdinVulkan/tree/main/libs/ovk).


## What we're doing

Nothing changes visually. The viking room still rotates, MSAA is still there. What changes is where things live and how they're organised:

- **libs/ovk/command_pool.odin** - `Command_Pool` struct, create/destroy.
- **libs/ovk/command_buffer.odin** - `Command_Buffer` struct, lifecycle (create/destroy/begin/end/submit), and the one-time command buffer helpers (`create_one_time_command_buffer`, `end_one_time_command_buffer`).
- **libs/ovk/commands.odin** - all the `cmd_*` recording helpers (transition, rendering, binding, drawing, copy, mipmap generation). Previously mixed into `command_buffer.odin`.
- **libs/ovk/fence.odin** - `Fence` struct, create/destroy, wait, reset.
- **libs/ovk/semaphore.odin** - `Semaphore` struct, create/destroy.
- **libs/ovk/queue.odin** - `Queue` struct and `get_queue`.
- **libs/ovk/buffer.odin** - now also holds `Mapped_Buffer`, `create_mapped_buffers`, `destroy_mapped_buffers`, `mem_copy_to_buffer`, and `transfer_to_buffer`.
- **libs/ovk/sampler.odin** - `Sampler` struct, create/destroy.
- **libs/ovk/model.odin** - `Mesh` struct, `load_mesh`, `destroy_mesh`.
- **libs/ovk/math.odin** - `matrix4_perspective_vulkan` moved here.
- **libs/ovk/descriptor_set.odin** - added `update_descriptor_set`.
- **libs/ovk/logical_device.odin** - added `wait_idle_device`.
- **libs/ovk/error.odin** - now has `check` and `assert`, both returning the `Error` union. No more `check_panic`.
- **libs/ovk/instance.odin** - now has `are_layers_supported`, which belongs with instance creation.
- **libs/ovk/physical_device.odin** - now has `find_memory_type`, `get_max_usable_sample_count`, `find_depth_format`, `find_supported_format`. All physical-device queries grouped together.
- **libs/ovk/utils.odin** - removed. Its functions were distributed across `error.odin`, `instance.odin`, `physical_device.odin`, and `buffer.odin`.

And `main.odin`:
- The `App` struct now holds everything: command pool, command buffers, semaphores, fences, vertex/index buffers, texture, sampler, UBO buffers and their mapped pointers.
- Initialisation and the render loop are split into `init_app` and `run_app`.
- `run_app` returns errors from the event loop.
- `destroy_app` is the single cleanup point.
- `record_command_buffer` takes ovk types instead of raw Vulkan handles.
- The application code dropped from about 1248 lines to about 635 lines.


## The split of utils.odin

Step 30 concentrated everything in `utils.odin`: error helpers, physical device format queries, buffer transfer logic, layer support checking. There was no real cohesion between those things - they just hadn't been moved yet. Now the functions live where they belong:

| What | Where it went |
|------|--------------|
| `check`, `assert` | `error.odin` - they construct `Vulkan_Error` / `Assert_Error` instances |
| `are_layers_supported` | `instance.odin` - layers are an instance-level concept |
| `find_memory_type`, `get_max_usable_sample_count`, `find_depth_format`, `find_supported_format` | `physical_device.odin` - all are queries against the physical device |
| `transfer_to_buffer` | `buffer.odin` - it creates and manages a staging buffer |

The `check_panic` function from step 30 was removed entirely. Now every operation uses `check` which returns an `Error`, and the caller decides what to do with it. The last vestiges of panic-based error handling in ovk are gone.

The `Error` union also gained an `Assert_Error` variant to support the new `assert` proc:

```c
Assert_Error :: struct {
    message: string,
    loc:     runtime.Source_Code_Location,
}

Error :: union {
    General_Error,
    Vulkan_Error,
    Assert_Error,
}
```

`assert` takes a condition and returns an error on failure - it's not a panic. This means `load_mesh` can do `assert(obj.success, "Failed to read obj file:", path) or_return` instead of calling `os.exit(1)`.

### Physical device queries now take `^Physical_Device`

Previously `get_max_usable_sample_count` and `find_depth_format` accepted a raw `vk.PhysicalDevice`. Now they take `^Physical_Device`, consistent with everything else in ovk:

```c
// Step 30:
app.samples = ovk.get_max_usable_sample_count(app.physical_device.vk_physical_device)
app.depth_format = ovk.find_depth_format(app.physical_device.vk_physical_device)

// Step 31:
app.samples = ovk.get_max_usable_sample_count(&app.physical_device)
app.depth_format = ovk.find_depth_format(&app.physical_device)
```


## Command pools and command buffers

`command_pool.odin` and `command_buffer.odin` follow the same struct + args + create/destroy pattern as everything else:

```c
Command_Pool :: struct {
    device:          ^Device,
    vk_command_pool: vk.CommandPool,
    queue_family:    u32,
}

Command_Buffer :: struct {
    command_pool:      ^Command_Pool,
    vk_command_buffer: vk.CommandBuffer,
}
```

The singular `create_command_buffer` calls the plural `create_command_buffers` with a count of 1, extracts the first element, frees the temporary slice, and returns a single value - same pattern as descriptor sets from step 30.

### One-time command buffers

Staging operations (buffer copies, texture transfers) need a temporary command buffer that is submitted immediately and freed:

```c
create_one_time_command_buffer :: proc(command_pool: ^Command_Pool) -> (command_buffer: Command_Buffer, err: Error)
end_one_time_command_buffer :: proc(command_buffer: ^Command_Buffer, queue: ^Queue) -> (err: Error)
```

The first allocates a buffer and begins recording with `{.ONE_TIME_SUBMIT}`. The second ends recording, submits, waits for the queue to idle, and frees the buffer. Between the two calls you record whatever commands you need.

### The `cmd_` helpers moved to commands.odin

All the functions that write commands into a command buffer are prefixed with `cmd_` and live in their own file, `commands.odin`. They take `^Command_Buffer` as the first parameter:

```c
cmd_transition_image_layout(command_buffer, image, old_layout, new_layout, ...)
cmd_begin_rendering(command_buffer, color_image, resolve_image, extent, depth_image)
cmd_bind_graphics_pipeline(command_buffer, pipeline)
cmd_set_viewport(command_buffer, width, height)
cmd_set_scissor(command_buffer, width, height)
cmd_bind_vertex_buffer(command_buffer, first_binding, count, buffer, offset)
cmd_bind_index_buffer(command_buffer, buffer, offset, index_type)
cmd_bind_graphics_descriptor_set(command_buffer, pipeline, descriptor_set)
cmd_draw_indexed(command_buffer, index_count, instance_count, ...)
cmd_end_rendering(command_buffer)
cmd_copy_buffer(command_buffer, src, src_offset, dest, dest_offset, size)
cmd_copy_buffer_to_image(command_buffer, buffer, image)
cmd_generate_mipmaps(command_buffer, image, format, width, height, mip_levels)
```

Previously they were mixed into `command_buffer.odin` alongside the buffer's lifecycle functions (create/destroy/begin/end/submit). Separating them makes it clearer what's a lifecycle operation and what's a recording operation.

### Submission

`submit_command_buffer` takes a `Submit_Command_Buffer_Args` struct:

```c
Submit_Command_Buffer_Args :: struct {
    command_buffer:    ^Command_Buffer,
    queue:             ^Queue,
    // fence can be nil when no fence is needed (one-time submissions)
    fence:             ^Fence,
    wait_semaphores:   []^Semaphore,
    wait_dest_stages:  []vk.PipelineStageFlags,
    signal_semaphores: []^Semaphore,
}
```

The fence can be nil for one-time submissions. The `queue_wait_idle` helper is used by `end_one_time_command_buffer` to drain the queue before freeing the buffer.

### Mipmap generation

`cmd_generate_mipmaps` uses the old `vk.ImageMemoryBarrier` API (not `ImageMemoryBarrier2`), because the blit barrier structure doesn't map cleanly to the vk2 equivalents. The image layout transitions (`cmd_transition_image_layout`) use the vk2 API. Both work correctly, it's just a reminder that the final mip level needs a separate transition.


## Fences and semaphores

Fences and semaphores follow the same pattern:

```c
Fence :: struct {
    device:   ^Device,
    vk_fence: vk.Fence,
}

Semaphore :: struct {
    device:       ^Device,
    vk_semaphore: vk.Semaphore,
}
```

Creation comes in singular and plural variants:

```c
create_fence(args) -> (Fence, Error)
create_fences(args, count) -> ([]Fence, Error)
create_semaphore(args) -> (Semaphore, Error)
create_semaphores(args, count) -> ([]Semaphore, Error)
```

The plural versions allocate an Odin slice and call the singular version for each element. `destroy_fences` / `destroy_semaphores` iterate, destroy each handle with the correct Vulkan call, and free the slice.


## The Queue type

Queues were raw `vk.Queue` handles. Now they have a thin wrapper:

```c
Queue :: struct {
    vk_queue: vk.Queue,
}
```

Unlike the other ovk types, `Queue` doesn't store a back-reference to `Device` - queues live as long as the device lives and aren't created or destroyed independently. The `Device` struct stores three of them (`graphics_queue`, `compute_queue`, `transfer_queue`) and creates them with `vk.GetDeviceQueue` during `create_logical_device`.


## Buffer transfers and mapped memory

`transfer_to_buffer` moved from the old `utils.odin` to `buffer.odin`. It creates a staging buffer, copies data, starts a one-time command buffer, records a `CmdCopyBuffer`, submits, waits, and frees everything:

```c
ovk.transfer_to_buffer(&app.graphics_command_pool, &app.device.graphics_queue, mesh.vertices, &app.vertex_buffer)
```

### Mapped_Buffer

Mapping a buffer the Vulkan way is `vk.MapMemory`, get a `rawptr`, use it, `vk.UnmapMemory`. The library now has a `Mapped_Buffer` type that bundles the pointer with the buffer:

```c
Mapped_Buffer :: struct {
    buffer: ^Buffer,
    ptr:    rawptr,
}

create_mapped_buffers :: proc(buffers: []Buffer, ...) -> ([]Mapped_Buffer, Error)
destroy_mapped_buffers :: proc(mapped_buffers: []Mapped_Buffer)
```

The uniform buffer setup in `init_app` now reads:

```c
app.ubo_buffers = ovk.create_buffers(
    {device = &app.device, size = u64(size_of(Uniform_Buffer_Object)), usage = {.UNIFORM_BUFFER}, mem_properties = {.HOST_VISIBLE, .HOST_COHERENT}},
    NB_FRAMES_IN_FLIGHT,
) or_return
app.ubo_mapped_buffers = ovk.create_mapped_buffers(app.ubo_buffers) or_return
```

And in the render loop, `app.ubo_mapped_buffers[frame_index].ptr` replaces the old `ubo_map_memory_ptrs[frame_index]`.


## Sampler

`create_sampler` moved into the library with a `Sampler` struct:

```c
Sampler :: struct {
    device:     ^Device,
    vk_sampler: vk.Sampler,
}
```

The sampler creation parameters are still hardcoded (the same `LINEAR` / `REPEAT` / max anisotropy settings as before). The `Create_Sampler_Args` struct has only `device` for now - it can be extended if you need configurable parameters later.


## Model loading

The standalone `load_model` in `main.odin` is replaced by `ovk.load_mesh` in `model.odin`. It returns a `Mesh`:

```c
Mesh :: struct {
    vertices: []Vertex,
    indices:  []u32,
}
```

The indices are `u32` instead of `u16`. The old code used `u16` because the viking room has fewer than 65535 vertices, but `u32` is more standard. The `CmdBindIndexBuffer` call in `record_command_buffer` uses `.UINT32`.

The mesh data is freed right after the GPU buffers are populated:

```c
mesh := ovk.load_mesh("../../assets/models/viking_room/viking_room.obj") or_return
defer ovk.destroy_mesh(&mesh)

app.vertex_buffer = ovk.create_buffer({...}) or_return
ovk.transfer_to_buffer(&app.graphics_command_pool, &app.device.graphics_queue, mesh.vertices, &app.vertex_buffer)
app.index_buffer = ovk.create_buffer({...}) or_return
ovk.transfer_to_buffer(&app.graphics_command_pool, &app.device.graphics_queue, mesh.indices, &app.index_buffer)
```


## Descriptor set updates

`update_descriptor_set` takes the descriptor set and a slice of `Descriptor_Write`:

```c
Descriptor_Write :: struct {
    binding: u32,
    type:    vk.DescriptorType,
    image:   ^Image,
    sampler: ^Sampler,
    buffer:  ^Buffer,
    offset:  u64,
    size:    u64,
}

update_descriptor_set :: proc(descriptor_set: ^Descriptor_Set, descriptor_writes: []Descriptor_Write) -> (err: Error)
```

It currently supports `UNIFORM_BUFFER` and `COMBINED_IMAGE_SAMPLER`. Adding a new descriptor type is just another branch in the iteration. The call site in `init_app` becomes:

```c
for i in 0 ..< NB_FRAMES_IN_FLIGHT {
    ovk.update_descriptor_set(
        &app.descriptor_sets[i],
        {{type = .UNIFORM_BUFFER, binding = 0, buffer = &app.ubo_buffers[i]}, {type = .COMBINED_IMAGE_SAMPLER, binding = 1, image = &app.texture, sampler = &app.sampler}},
    ) or_return
}
```


## The application code is now minimal

`main` is 27 lines:

```c
main :: proc() {
    fmt.println("Odin Vulkan Tutorial")
    fmt.println("-------------------------------------------")

    app: App
    err := init_app(&app)
    if err != nil {
        fmt.eprintfln("Failed to initialize vulkan:\n%#v", err)
        os.exit(1)
    }

    err = run_app(&app)
    if err != nil {
        fmt.eprintfln("Error while running the application:\n%#v", err)
        os.exit(1)
    }

    ovk.wait_idle_device(&app.device)
    destroy_app(&app)
}
```

Every resource is initialised by `init_app`, used by `run_app`, and cleaned up by `destroy_app`. There is no manual loop over fences or semaphores in `main`.

The `App` struct now owns everything:

```c
App :: struct {
    instance:                 ovk.Instance,
    window:                   ovk.Window,
    physical_device:          ovk.Physical_Device,
    device:                   ovk.Device,
    swap_chain:               ovk.Swap_Chain,
    shader:                   ovk.Shader,
    descriptor_set_layout:    ovk.Descriptor_Set_Layout,
    descriptor_pool:          ovk.Descriptor_Pool,
    descriptor_sets:          []ovk.Descriptor_Set,
    samples:                  vk.SampleCountFlags,
    color_image:              ovk.Image,
    depth_format:             vk.Format,
    depth_image:              ovk.Image,
    graphics_pipeline:        ovk.Graphics_Pipeline,
    graphics_command_pool:    ovk.Command_Pool,
    graphics_command_buffers: []ovk.Command_Buffer,
    acquire_semaphores:       []ovk.Semaphore,
    submit_semaphores:        []ovk.Semaphore,
    draw_fences:              []ovk.Fence,
    vertex_buffer:            ovk.Buffer,
    index_buffer:             ovk.Buffer,
    texture:                  ovk.Image,
    sampler:                  ovk.Sampler,
    ubo_buffers:              []ovk.Buffer,
    ubo_mapped_buffers:       []ovk.Mapped_Buffer,
}
```

### The event loop as a function

In step 30 the event loop was inline in `main`. Now it lives in `run_app`, which returns `ovk.Error`. If `acquire_next_image` or `submit_command_buffer` fails during the loop, the error propagates up.

`acquire_next_image` and `queue_present` each return `(value, bool, Error)`. The bool indicates whether the swap chain needs recreation. The `or_return` only checks the Error part, so the recreation flag still works:

```c
swap_chain_image_index, swap_chain_recreation_needed := ovk.acquire_next_image(
    &app.swap_chain,
    &app.draw_fences[frame_index],
    &app.acquire_semaphores[frame_index],
) or_return
```

### record_command_buffer takes ovk types

The function signature got simpler - eleven raw Vulkan handles replaced with pointers to ovk types:

```c
record_command_buffer :: proc(
    command_buffer: ^ovk.Command_Buffer,
    image: ^ovk.Image,
    swap_chain_extent: vk.Extent2D,
    graphics_pipeline: ^ovk.Graphics_Pipeline,
    vertex_buffer: ^ovk.Buffer,
    index_buffer: ^ovk.Buffer,
    index_count: u32,
    descriptor_set: ^ovk.Descriptor_Set,
    depth_image: ^ovk.Image,
    color_image: ^ovk.Image,
)
```

The index count is computed from the buffer size (`u32(app.index_buffer.size / size_of(u32))`), avoiding a separate counter in `App`.

### The swap chain recreation path

When the swap chain is out of date, `run_app` calls `destroy_swap_chain(app)` then `create_swap_chain(app) or_return`. Because `create_swap_chain` now returns an error instead of panicking, a failed recreation propagates up to `main` instead of crashing mid-frame.


## What's next

This step completes the refactoring that started in step 29. Every Vulkan object and every reusable operation lives in `libs/ovk/`. `utils.odin` no longer exists - its functions now live where they belong. `main.odin` is down to about 635 lines, most of which is application-specific: the vertex definition, the uniform buffer struct, the `record_command_buffer` logic, the texture loading function, and the event loop.

What comes next is up to you. With the boilerplate out of the way, the next steps can focus on new features - compute shaders, push constants, GPU-driven rendering, or whatever Vulkan feature you want to explore.
