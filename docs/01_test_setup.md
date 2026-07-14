---
title: 01 — Test Setup
nav_order: 3
---

# 01 - Test Setup

This first step isn't going to render anything. Before we go further, we want to make sure the whole toolchain works: that Odin compiles, that GLFW initialises, that the Vulkan SDK is reachable, and that our GPU actually supports Vulkan.

Think of this as a sanity check. If something is wrong with the setup, better to find out now than three chapters in.

The full source for this step lives in [`src/01_test_setup/main.odin`](../src/01_test_setup/main.odin). Open it side by side with this doc.


## What we want to prove

Five things, in order:

1. **GLFW** can initialise.
2. **Vulkan** can create an `Instance`.
3. The **VULKAN_SDK** environment variable points to a valid SDK installation.
4. The **Vulkan validation layers** are installed and discoverable.
5. The **slang compiler** (`slangc`) is present in the SDK.

If all five pass, we're ready to actually build something. If any of them fails, the error message will (hopefully) point you back to the [prerequisites](./prerequisites.md) doc.


## The code, step by step

### Imports

```c
import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"
```

Nothing fancy here. `core:fmt` and `core:os` come with Odin. The other two are vendored copies shipped with the language:

- `vendor:glfw` — bindings to GLFW, the library that gives us a window and an event loop without having to talk to X11 / Win32 / Cocoa directly.
- `vendor:vulkan` — bindings to Vulkan. We alias it as `vk` to keep things short.

The `vendor:` prefix is Odin's way of saying "this lives in the vendor folder of the standard library". If you ever need another vendor lib (stb, miniaudio, etc.) it'll follow the same pattern.


### Proving GLFW works

```c
if !glfw.Init() {
    fmt.eprintln("Failed to initialize GLFW")
    os.exit(1)
}
```

`glfw.Init()` returns `true` on success. If it returns `false`, we print to `stderr` and exit.

There's not much else to say — GLFW either comes up or it doesn't. If it doesn't on Linux, double-check [prerequisites](./prerequisites.md): you most likely did not install `libglfw3-dev`.


### Proving Vulkan works

This is the main part. We don't just want to *link* Vulkan — we want to actually create a `vk.Instance` to prove the loader can talk to our driver.

#### Loading function pointers

```c
vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
```

Vulkan is a *loaded* API: the functions you call aren't resolved by the linker at build time, they're grabbed at runtime through a function pointer you provide. `glfw.GetInstanceProcAddress` is exactly one of those pointer-providers — GLFW knows how to dig up Vulkan functions because it was built against Vulkan itself.

We pass it in here, before calling any Vulkan function, so Odin can populate its `vk` package with real entry points. Try calling `vk.CreateInstance` without this line and it will crash.

#### The ApplicationInfo

```c
app_info := vk.ApplicationInfo {
    sType = .APPLICATION_INFO,
    pApplicationName = "Test setup",
    applicationVersion = vk.MAKE_VERSION(1, 0, 0),
    pEngineName = "No Engine",
    engineVersion = vk.MAKE_VERSION(1, 0, 0),
    apiVersion = vk.API_VERSION_1_0,
}
```

Vulkan loves structures, and structures start with an `sType` field that tells Vulkan *what kind* of structure this is. This is a recurring pattern — get used to adding an `sType` line every time you fill in a Vulkan struct.

The `ApplicationInfo` itself is just metadata: app name, version, engine name, and the Vulkan API version we target. We're asking for `1.0` here because the test doesn't need anything fancy.

#### The InstanceCreateInfo

```c
create_info := vk.InstanceCreateInfo {
    sType = .INSTANCE_CREATE_INFO,
    pApplicationInfo = &app_info,
    enabledLayerCount = 0,
}
```

The `InstanceCreateInfo` is what we actually hand to Vulkan when we ask for an instance. Note three things here:

- `enabledLayerCount = 0` — we're not enabling any validation layer *for this instance*. The test checks for layers separately, just below.
- `pApplicationInfo` takes a *pointer* to the struct we just filled (`&app_info`). Odin passes by value by default; Vulkan wants addresses.
- No `enabledExtensionNames`? For a pure command-line test we don't need any. As soon as we want a window though, we'll have to ask for the `VK_KHR_surface` family of extensions. That comes in later steps.

A small detail: in C, you'd have to remember to zero out the struct before filling it. Odin does that for us — anything not listed in a struct literal starts zeroed.

#### Actually creating it

```c
instance: vk.Instance
result := vk.CreateInstance(&create_info, nil, &instance)
if result != vk.Result.SUCCESS {
    fmt.eprintln("Failed to create Vulkan instance. ...")
    os.exit(1)
}
vk.load_proc_addresses_instance(instance)
fmt.println("Vulkan... OK!")
```

Vulkan functions return a `vk.Result` instead of throwing. So it's:

1. call the function
2. store the result
3. check it
4. only then use the thing it produced

Oh, and after creating the instance, we call `load_proc_addresses_instance(instance)`. Why? Because *instance-level* functions (everything that isn't `vk.GetInstanceProcAddr`, `vk.CreateInstance` or the enumeration helpers) need a live instance handle to be loaded. That's how Vulkan works.

#### Checking the VULKAN_SDK path

```c
vulkan_sdk, found := os.lookup_env("VULKAN_SDK", context.allocator)
defer delete(vulkan_sdk)
if !found || vulkan_sdk == "" {
    fmt.eprintln("VULKAN_SDK environment variable is not set. ...")
    os.exit(1)
}
fmt.println("Vulkan SDK path... OK!")
```

We ask the OS for the `VULKAN_SDK` environment variable. If it's missing or empty, there's no point continuing — Vulkan SDK tools and layers won't be found either. The `defer delete(vulkan_sdk)` frees the string Odin allocated for us.

The only way to fix this is to install the SDK and set the variable. The [prerequisites](./prerequisites.md) doc has the links.

#### Checking the validation layers

```c
if !check_validation_layer_support() {
    fmt.eprintln(
        "Vulkan validation layers not available. The Vulkan SDK is not correctly installed. ..."
    )
    os.exit(1)
}
fmt.println("Vulkan validation layers... OK!")
```

The SDK ships a validation layer named `VK_LAYER_KHRONOS_validation`. If we *can't* find it at runtime, something is wrong with the SDK installation — the variable might be set but point to an incomplete SDK, or the layer wasn't deployed. In either case it's a hard error so we exit.

The helper that does the searching:

```c
check_validation_layer_support :: proc() -> b32 {
    layer_count: u32
    vk.EnumerateInstanceLayerProperties(&layer_count, nil)
    available_layers := make([]vk.LayerProperties, layer_count)
    defer delete(available_layers)
    vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

    for &layer in available_layers {
        if cstring(&layer.layerName[0]) == "VK_LAYER_KHRONOS_validation" {
            return true
        }
    }
    return false
}
```

The classic Vulkan two-call pattern:

1. Ask *how many* first (pass `nil` for the buffer, get back a count).
2. Allocate a buffer of that size.
3. Ask again, this time providing the buffer (`raw_data(available_layers)` gives us a `rawptr` to the underlying array).

You'll see this pattern *everywhere* in Vulkan. Get comfortable with it — it's not going anywhere.

Then we loop over what we got and compare each `layerName` against `"VK_LAYER_KHRONOS_validation"`. The name is a fixed-size char array inside `LayerProperties`, so `cstring(&...[0])` casts it into a proper Odin string for comparison. A small bit of pointer wrangling, but it's a one-liner.

#### Checking for the slang compiler

```c
slangc_path := fmt.tprintf("%s/bin/slangc", vulkan_sdk)
if !os.exists(slangc_path) {
    fmt.eprintfln("slangc executable not found: '%q'. ...", slangc_path)
    os.exit(1)
}
fmt.println("Slang compiler found... OK!")
```

`slangc` is the shader compiler that comes bundled with the Vulkan SDK under `$VULKAN_SDK/bin/slangc`. Since we'll write shaders in Slang later, we need to know the compiler is reachable before we rely on it.

We build the full path from `VULKAN_SDK` (already validated), then check if the file exists. If `slangc` isn't there, the SDK installation is incomplete or outdated.


## Run it

Open the `src/01_test_setup/` folder in VSCode and hit `F5`. Or, from the command line:

```
odin build . -debug -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors -out:bin/debug/01_test_setup
./bin/debug/01_test_setup
```

If everything is in order you should see:

```
Test setup
--------------------------
GLFW... OK!
Vulkan... OK!
Vulkan SDK path... OK!
Vulkan validation layers... OK!
Slang compiler found... OK!

Good job, everything is setup correctly!
```

If you get an error instead, jump back to [prerequisites](./prerequisites.md) — that's exactly what it's there for.


## What's next

We have proof our environment works, but that's all. No window, no rendering, yet. In [02 - Instance](./02_instance.md) we'll wrap instance creation behind a proper procedure, ask Vulkan for the extensions GLFW needs, and start cleaning up after ourselves.