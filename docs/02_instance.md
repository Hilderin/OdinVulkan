# 02 - Instance

The previous step was a smoke test: link Vulkan and GLFW, ask for an instance, see if anything explodes. This step is the real first building block.

We now wrap instance creation in its own procedure, ask Vulkan for the extensions GLFW needs to put a window on screen, target a more recent API version, and — importantly — clean up after ourselves instead of letting the OS reclaim everything at exit.

It's still a command-line program. Nothing is drawn. But from here on, every step will assume a valid `vk.Instance` exists, so getting this one right matters.

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/01_Instance.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Instance>

The full source for this step lives in [`src/02_instance/main.odin`](../src/02_instance/main.odin). Open it side by side with this doc.


## What we want to prove

1. We can put instance creation behind a function, instead of doing it inline in `main`.
2. We can query the **instance extensions** GLFW requires and pass them to Vulkan. This is what makes the bridge between a window system and Vulkan possible.
3. We can target Vulkan **1.4** as the API version, instead of the 1.0 from the smoke test.
4. We can tear the instance down cleanly with `vk.DestroyInstance` before the program exits.

If all four pass, we have a foundation that the next steps (validation layers, physical device selection, the window itself) can build on.


## The code, step by step

### Imports

```odin
import "core:fmt"
import "core:os"

import "vendor:glfw"
import vk "vendor:vulkan"
```

Same as the smoke test. `core:fmt` and `core:os` for printing and exiting, `vendor:glfw` for windowing, and `vendor:vulkan` aliased as `vk` because typing `vulkan` on every line gets old fast.


### Wrapping creation in a procedure

```odin
createInstance :: proc() -> (vk.Instance, bool) {
    vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
    ...
    return instance, true
}
```

The whole point of this step. Instead of doing `vk.CreateInstance` in `main` and moving on, we put it behind `createInstance` which returns a `(vk.Instance, bool)` pair: the handle, and a success flag.

This is a small Odin-ism worth getting used to. Vulkan functions don't throw, and Odin doesn't either, so the natural way to report a failure from a procedure is to return multiple values. The caller checks the `bool` and decides what to do. We could return a tagged union (`union(ok)`), but a plain tuple is honest enough here — there's exactly one interesting failure mode and we want a handle on success.

The first line inside the proc is the same loader call from step 01. It has to happen before any other Vulkan call, otherwise the `vk` package's function pointers are still null and `vk.CreateInstance` will crash. Worth repeating: Vulkan is a *loaded* API. The functions you call aren't resolved by the linker, they're fetched at runtime.


### The ApplicationInfo

```odin
appInfo: vk.ApplicationInfo
appInfo.sType = vk.StructureType.APPLICATION_INFO
appInfo.pApplicationName = "Instance creation"
appInfo.applicationVersion = vk.MAKE_VERSION(1, 0, 0)
appInfo.pEngineName = "No Engine"
appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
appInfo.apiVersion = vk.API_VERSION_1_4
```

This is metadata we hand to the driver — app name, version, engine name, and the Vulkan API version we target. Vulkan is technically allowed to ignore all of it, but drivers can use it for hints, and tools like RenderDoc read it to label traces.

Two things to notice:

- The `sType` field is back. Every Vulkan struct you fill in starts with one. It tells the loader "this is an `ApplicationInfo`, not some other struct you might receive through the same pointer". Get used to it, you'll be typing this pattern a lot.
- `appInfo.apiVersion = vk.API_VERSION_1_4`. The smoke test asked for `1.0`; we now ask for `1.4`. This is the highest version our local loader can give us, and we want to keep up so we can use features like synchronization2 or dynamic rendering later without bumping it retroactively. The Khronos tutorial uses `vk::ApiVersion14` for the same reason — see the "Instance" chapter referenced above.

In C you'd also have to zero the struct before filling it. Odin zeroes for you — anything you don't assign on a freshly declared `appInfo: vk.ApplicationInfo` starts at zero. That's one less footgun.


### The InstanceCreateInfo — and the new bit

```odin
createInfo: vk.InstanceCreateInfo
createInfo.sType = vk.StructureType.INSTANCE_CREATE_INFO
createInfo.pApplicationInfo = &appInfo

extensions := glfw.GetRequiredInstanceExtensions()
createInfo.enabledExtensionCount = u32(len(extensions))
createInfo.ppEnabledExtensionNames = raw_data(extensions)

createInfo.enabledLayerCount = 0
```

The `InstanceCreateInfo` is what we actually hand to Vulkan. `pApplicationInfo` takes a *pointer* to the struct we just filled (`&appInfo`), because Odin passes by value by default and Vulkan wants addresses.

The interesting part, and the new thing this step introduces, is the extensions block:

```odin
extensions := glfw.GetRequiredInstanceExtensions()
createInfo.enabledExtensionCount = u32(len(extensions))
createInfo.ppEnabledExtensionNames = raw_data(extensions)
```

Vulkan doesn't know about your window system. It's platform-agnostic by design, which means anything related to actually putting pixels on a window — `VK_KHR_surface` on Linux/X11, `VK_KHR_win32_surface` on Windows, `VK_KHR_wayland_surface` on Wayland, etc. — is bolted on through **extensions**. GLFW knows which of those it needs for the current platform, and `glfw.GetRequiredInstanceExtensions()` returns the list.

In Odin's bindings that returns a `[]cstring`. Vulkan wants two things on the C side: a count, and a pointer to a `const char * const *`. So:

- `enabledExtensionCount = u32(len(extensions))` — the count, cast to `u32` because Vulkan takes a `uint32_t`, not an Odin `int`.
- `ppEnabledExtensionNames = raw_data(extensions)` — `raw_data` gives us a `rawptr` to the slice's backing array, which is what the C signature expects.

This works because the slice elements are `cstring`, which is layout-compatible with `const char *`. If you ever swap the slice type, double-check the element layout before doing this — `raw_data` does not check element sizes for you.

Then `enabledLayerCount = 0`: we're not enabling any validation layer yet. That's the entire subject of the next step, so we leave it empty here on purpose. The smoke test had a *separate* helper that just *checked* if the validation layer was available; we deliberately don't enable it here, because enabling without checking first is the wrong way around, and doing the check properly deserves its own step.

A subtle point: in the smoke test we left extensions empty too. That worked because there was no window. As soon as a window is involved — which is from step 06 onwards — Vulkan won't create a surface for you unless you ask for these extensions now, *at instance creation time*. There's no way to bolt them on later. So getting this pattern right early saves you a confusing error message in a few steps.


### Actually creating it

```odin
result: vk.Result
instance: vk.Instance
result = vk.CreateInstance(&createInfo, nil, &instance)
if result != vk.Result.SUCCESS {
    fmt.eprintln("failed to create instance!")
    return nil, false
}
vk.load_proc_addresses_instance(instance)

return instance, true
```

The classic Vulkan call shape:

1. declare a result variable and an output variable,
2. call the function with pointers to both,
3. check the `vk.Result`,
4. only then touch the output.

`vk.CreateInstance` takes three arguments here: the create info pointer, a custom allocator (we pass `nil` for the default), and a pointer to the instance handle it should write to.

If it fails, we return `nil, false` instead of exiting. That's deliberate — we want the *caller* to decide whether a failed instance creation is fatal. In this small program it is, but keeping that decision in `main` makes the procedure reusable later when we'll want to fall back to a different API version or extension set.

On success, `vk.load_proc_addresses_instance(instance)` runs. This is the second loader call, and it's mandatory: *instance-level* Vulkan functions (everything except `vk.CreateInstance` and the handful of global helpers) need a live instance handle to be loaded. We did the global load with `glfw.GetInstanceGetProcAddress` at the top; this one resolves the rest. Forget it and the subsequent `vk.DestroyInstance` call will crash.

The Khronos tutorial uses the C++ bindings, where this happens implicitly through RAII. We're using the raw API, so we do it by hand — but it's two lines, not magic.


### main: init, create, clean up

```odin
main :: proc() {
    fmt.println("Instance creation")
    fmt.println("-------------------------------------------")

    if (!glfw.Init()) {
        fmt.eprintln("Failed to initialize GLFW")
        os.exit(1)
    }

    instance: vk.Instance
    result: bool
    instance, result = createInstance()
    if (!result) {
        fmt.eprintln("Create instance failed.")
        os.exit(1)
    }
    fmt.println("Create instance... OK")

    fmt.println()
    fmt.println("Instance creation completed with success!")

    if instance != nil {
        vk.DestroyInstance(instance, nil)
    }
}
```

`main` is mostly orchestration:

- `glfw.Init()` first. Same as the smoke test — if GLFW can't come up, there's no point.
- Then the multiple-value return from `createInstance` gets unpacked into `instance` and `result` in one go. Odin lets you do `a, b = proc()` directly, which is cleaner than the C++ alternative of catching an exception or unwrapping a `Result`.
- If `result` is false, we print and `os.exit(1)`. This is where we decide the failure is fatal — the procedure just reported it.
- The interesting new bit at the bottom:

```odin
if instance != nil {
    vk.DestroyInstance(instance, nil)
}
```

Vulkan does not garbage-collect anything. Every object you create, you destroy, *in the right order*, when you're done. `vk.DestroyInstance` is the cleanup call matching `vk.CreateInstance`. The second argument is an optional allocator callback; we pass `nil` for the default, same as we did for create.

The `nil`-check is belt-and-braces: if `createInstance` returned `false`, we already exited, so we'd never reach this line with a nil instance. But the instinct to keep resource cleanup behind a null check is a good one to internalise in Vulkan, where you'll soon be destroying dozens of objects in a specific order at shutdown. A null check is cheap, a segfault on cleanup is not.

One thing worth flagging: Vulkan's creation and destruction calls don't pair symmetrically the way `malloc`/`free` do. The order you destroy things in matters — children before parents. Right now we only have one object, so the order is trivial. But once we have a `Device` allocated from a `PhysicalDevice` and a `Surface` hanging off the `Instance`, you destroy in reverse: device first, then surface, then instance. We'll come back to this in later steps.


## Run it

From the `src/02_instance/` folder:

```
odin build . -debug -vet -strict-style -out:bin/debug/02_instance
./bin/debug/02_instance
```

You should see:

```
Instance creation
-------------------------------------------
Create instance... OK

Instance creation completed with success!
```

No window pops up — that's expected, we're not asking GLFW for one yet. The success message is the contract: instance was created, instance was destroyed, program exited cleanly.

If `Create instance failed.` shows up instead, the most common cause is missing the extensions GLFW asked for. That would hint at a partial Vulkan install — for example, `VK_KHR_surface` not being picked up by the loader. Re-check [prerequisites](./prerequisites.md) and your `vulkaninfo --summary` output.


## What's next

Right now if we pass Vulkan bad arguments, it'll happily return `VK_SUCCESS` and nothing — no warning, no error, just silently wrong output. That's because we haven't enabled a **validation layer** yet. In [03 - Validation Layers](./03_validation_layers.md) we finally enable `VK_LAYER_KHRONOS_validation`, so Vulkan starts telling us when we mess up.