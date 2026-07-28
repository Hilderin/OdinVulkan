---
title: 29 - ovk Framework Init
nav_order: 31
---

# 29 - ovk Framework Init

This is a turning point for the project. After 28 steps of adding features one at a time, the code in `main.odin` was a single 2200-line file with everything from instance creation to the event loop mixed together. This step pulls the reusable pieces into a small library called `ovk` (Odin Vulkan) under `libs/ovk/`.

The goal is **not** to build an engine. ovk stays close to Vulkan's concepts - instances, devices, queues, surfaces - just removes the boilerplate that's the same in every project. Each `src/` folder still has its own `main.odin` with the step-specific logic (swap chain, pipelines, command buffers, etc.), but the foundation code (instance creation, physical device selection, logical device setup, window surface management) lives in the library and is shared.

The full source for this step lives in [src/29_ovk_framework_init/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/29_ovk_framework_init/main.odin) and [libs/ovk/](https://github.com/Hilderin/OdinVulkan/tree/main/libs/ovk).


## What we're doing

There's no new Vulkan feature in this step. The viking room still rotates, the MSAA is still on. What changes is how the code is organised. In one glance:

- **libs/ovk/error.odin** - an `Error` union type (`General_Error | Vulkan_Error`) so the library can return errors instead of panicking.
- **libs/ovk/glfw.odin** - GLFW init/destroy, window creation, surface creation, all bundled into a `Window` struct.
- **libs/ovk/instance.odin** - `Instance` struct with `create_instance` and `destroy_instance`, debug messenger management.
- **libs/ovk/physical_device.odin** - `Physical_Device` struct that caches queue family indices, `get_physical_device` with scoring.
- **libs/ovk/logical_device.odin** - `Device` struct holding the `vk.Device` and queues, `create_logical_device` / `destroy_logical_device`.
- **libs/ovk/utils.odin** - `check` (returns `Error`) and `check_panic` (panics) for Vulkan results, `are_layers_supported`.
- **src/29_ovk_framework_init.code-workspace** - a multi-root workspace that includes both `src/29_ovk_framework_init/` and `libs/ovk/`. Opening this file in VSCode shows both folders side by side, which is handy now that the code is split across two directories.
- **.vscode/settings.json** - hides `*.code-workspace` from the VSCode explorer so the workspace file doesn't clutter the file list.
- **src/29_ovk_framework_init/main.odin** - about 300 lines shorter than step 27, uses the library through `init_app` / `destroy_app`.

The first step toward a complete refactoring where every Vulkan object (instance, physical device, logical device, swap chain, pipelines, command buffers, etc.) will eventually have a corresponding ovk wrapper. For now, just the foundation layer is extracted.


## What was extracted, and why

### The Error type (`libs/ovk/error.odin`)

```c
General_Error :: struct {
    message: string,
}

Vulkan_Error :: struct {
    result:  vk.Result,
    message: string,
    loc:     runtime.Source_Code_Location,
}

Error :: union {
    General_Error,
    Vulkan_Error,
}
```

Two error variants. `General_Error` for things like "GLFW failed to initialise" where there's no Vulkan result code. `Vulkan_Error` for actual API failures, with the `vk.Result` and the caller location so you can find where it happened. The `Error` union lets library functions return errors with `or_return` instead of calling `os.exit(1)` inline.

The old code used `vk_check` everywhere, which panics on any error. The library now uses `check` which returns an `Error` - the library never panics. The remaining parts of `main.odin` still use `check_panic` (same behaviour as the old `vk_check`) as a temporary measure, until they are moved into the library too.

### GLFW wrapper (`libs/ovk/glfw.odin`)

```c
Window :: struct {
    instance:      ^Instance,
    window_handle: glfw.WindowHandle,
    surface:       vk.SurfaceKHR,
}

Create_Window_Args :: struct {
    instance:  ^Instance,
    title:     string,
    width:     u32,
    height:    u32,
    resizable: bool,
}
```

A `Window` struct bundles the GLFW window handle with the Vulkan surface. The `create_window` function takes a `Create_Window_Args` struct, which is the pattern used throughout the library: named arguments in a struct instead of a long parameter list. It's more verbose at the call site but self-documenting and extensible without breaking callers.

The `instance: ^Instance` pointer is needed so `destroy_window` can clean up the surface before destroying the window. There's a coupling here - the window needs to know which instance the surface belongs to - but it keeps the destroy API simple: one function, one struct, no extra parameters.

### Instance creation (`libs/ovk/instance.odin`)

```c
create_instance :: proc(args: Create_Instance_Args) -> (instance: Instance, err: Error) {
    vk.load_proc_addresses(args.get_instance_proc_addr)

    if args.debug {
        if !are_layers_supported(validation_layers) {
            err = General_Error { "Vulkan validation layers not available..." }
            return
        }
    }
    ...
    check(vk.CreateInstance(&create_info, nil, &instance.vk_instance), "failed to create instance!") or_return
    vk.load_proc_addresses_instance(instance.vk_instance)

    if args.debug && vk.CreateDebugUtilsMessengerEXT != nil {
        check(vk.CreateDebugUtilsMessengerEXT(...), "failed to create debug messenger!") or_return
    }
    return
}
```

Two important changes from the old code:

1. **The debug level filters at the Vulkan level, not in the callback.** The old code passed `debug_level` to `vk.DebugUtilsMessengerCreateInfoEXT.messageSeverity` *and* checked the same level again inside the callback. Vulkan already filters messages by severity before calling the callback, so the double-check was redundant. The new callback just formats whatever it receives.

2. **The instance is returned, not stored in a global.** The old code used a global `debug_messenger` variable. Now the messenger handle lives on the `Instance` struct. That's consistent with RAII-like cleanup: `destroy_instance` reads `instance.debug_messenger` from the same struct.

### Physical device with cached queues (`libs/ovk/physical_device.odin`)

```c
Physical_Device :: struct {
    vk_physical_device:    vk.PhysicalDevice,
    graphics_queue_family: u32,
    compute_queue_family:  u32,
    transfer_queue_family: u32,
}
```

The physical device struct caches three queue family indices. In the old code, every function that needed a queue index called `find_queue_families` and searched through the list again. Now the indices are stored once in `get_physical_device` and reused.

The compute and transfer fallbacks are worth noting. If a dedicated compute or transfer queue family doesn't exist (which is common on desktop GPUs), the code falls back to the graphics queue family. Graphics queues always support compute and transfer bits per the Vulkan spec, so this is safe.

### Logical device with queues baked in (`libs/ovk/logical_device.odin`)

```c
Device :: struct {
    physical_device: ^Physical_Device,
    vk_device:       vk.Device,
    graphics_queue:  vk.Queue,
    compute_queue:   vk.Queue,
    transfer_queue:  vk.Queue,
}
```

The `Device` struct doesn't just store the `vk.Device` handle - it also stores the three queue handles, retrieved with `vk.GetDeviceQueue` after creation. The main code can then use `app.device.graphics_queue` instead of passing a separate `graphics_queue` variable around.

The `physical_device` pointer keeps a back-reference to the physical device, which some operations (like memory allocation) need.

### The two check functions (`libs/ovk/utils.odin`)

`check_panic` is temporary - it exists only to keep the old behaviour in the parts of `main.odin` that haven't been refactored yet. Once everything is in the library, `check_panic` will be removed and all error handling will go through `check`.

```c
check_panic :: proc(result: vk.Result, operation: string, loc := #caller_location) {
    if result == .SUCCESS { return }
    p := context.assertion_failure_proc
    when ODIN_DEBUG {
        p(operation, reflect.enum_string(result), loc)
    } else {
        p(operation, "Vulkan operation failed", loc)
    }
}

check :: proc(result: vk.Result, operation: string, loc := #caller_location) -> (err: Error) {
    if result == .SUCCESS { return }
    err = Vulkan_Error{result, fmt.tprint(operation, reflect.enum_string(result)), loc}
    return
}
```

Two variants with the same surface but different behaviour:

- `check_panic` - crashes on failure. Used in the application code (`main.odin`) where there's no sensible way to recover.
- `check` - returns an `Error`. Used inside the library (`instance.odin`, `logical_device.odin`) so the caller can decide how to handle the failure.

Both include `#caller_location` so the error message points to the actual call site, not to the utility function itself.


## How the application changed

The `main.odin` went from about 2265 lines (step 27) to about 1960 lines - roughly 300 lines removed, mostly the extracted boilerplate plus the globals `debug_messenger`, `debug_level`, `validation_layers`, and the `vk_check` proc.

The new `App` struct wraps the four ovk types:

```c
App :: struct {
    instance:        ovk.Instance,
    window:          ovk.Window,
    physical_device: ovk.Physical_Device,
    device:          ovk.Device,
}
```

Initialisation is now a single function call:

```c
init_app :: proc(app: ^App) -> (err: ovk.Error) {
    ovk.init_glfw() or_return
    app.instance = ovk.create_instance({...}) or_return
    app.window = ovk.create_window({...}) or_return
    app.physical_device = ovk.get_physical_device({...}) or_return
    app.device = ovk.create_logical_device({...}) or_return
    return
}
```

If any step fails, the `or_return` propagates the error up to `main`, which prints the error and exits. This is cleaner than the old pattern where each function called `os.exit(1)` internally with a `fmt.eprintln` - the error type now carries both the message and the Vulkan result code, so the output is more informative.

One thing to watch: if `init_app` fails partway through (say the window was created but the physical device selection failed), the resources from earlier steps are not cleaned up. The `or_return` returns immediately without running any defer. For now this is acceptable because the application just exits on failure, but it's something to improve in a future step.

Cleanup is symmetric in `destroy_app`:

```c
destroy_app :: proc(app: ^App) {
    ovk.destroy_logical_device(&app.device)
    ovk.destroy_window(&app.window)
    ovk.destroy_instance(&app.instance)
    ovk.destroy_glfw()
}
```

Order matters - the device must be destroyed before the instance, the window surface must be destroyed before the instance, and GLFW is terminated last. Each `destroy_*` function checks for nil / zero handles before calling Vulkan or GLFW, so double-destruction is safe.

### `check_panic` is a temporary stand-in

You'll see `ovk.check_panic` everywhere in `main.odin` where the old `vk_check` was. It keeps the same behaviour (crash on error) while only the foundation layer is extracted. Once the rest of the Vulkan objects (swap chain, buffers, pipelines, etc.) move into ovk, `check_panic` will be removed and everything will use `check` with `or_return`. It's a stepping stone, not the final design.

Throughout the remaining code in `main.odin`, every call to the old `vk_check` was replaced with `ovk.check_panic`. Same behaviour, different package. This is the only change in most of the swap chain, pipeline, buffer, image, and command buffer functions - the code itself is identical to step 27.

### `create_command_pool` uses the cached queue

The old code called `find_queue_families` again inside `create_command_pool`. The new code uses the cached index directly:

```c
create_command_pool :: proc(device: vk.Device, physical_device: ^ovk.Physical_Device) -> vk.CommandPool {
    command_pool_create_info := vk.CommandPoolCreateInfo {
        ...
        queueFamilyIndex = physical_device.graphics_queue_family,
    }
    ...
}
```

Small change, but it removes a redundant device properties query (and the associated allocation) every time a command pool is created.

### What stayed the same

The swap chain, image views, depth resources, color resources, shader modules, pipelines, command buffers, semaphores, fences, buffers, descriptors, and all the rendering code in `record_command_buffer` are unchanged. They still take raw `vk.Device` and `vk.PhysicalDevice` handles, accessed through `app.device.vk_device` and `app.physical_device.vk_physical_device`. Wrapping those is the next step.


## The ovk API design in a sentence

ovk is a thin wrapper that turns the Vulkan two-step initialisation (enumerate + choose) into a single call that returns a struct with the useful handles. It does not abstract away Vulkan concepts - you still work with `vk.Queue`, `vk.Image`, `vk.Pipeline` etc. directly. It just removes the "check layers are installed, set up debug messenger, find queue families, pick the right device" preamble that's the same in every project.

The decision to use `Create_*_Args` parameter structs everywhere was deliberate. Vulkan create info structs already work this way - you fill a struct and pass it. ovk does the same for its own API. The result is that adding a new optional parameter (like a custom allocator callback, or a specific queue priority) doesn't break existing callers.


## What's next

The foundation layer (instance, physical device, logical device, window) is now in the library. The [next step](./30_ovk_framework_objects.md) wraps the remaining Vulkan objects - swap chain, buffers, images, shader modules, graphics pipelines, descriptor sets - so the main code shrinks further. Eventually the goal is to have ovk handle the full lifecycle of every Vulkan resource, while keeping the application code focused on what makes each step different.
