---
title: 02 — Instance
nav_order: 4
---

# 02 - Instance

The first thing we need to do is initialize the Vulkan API instance. Without that, nothing can work.

The full source for this step lives in `src/02_instance/main.odin`.

I'm not going to go over every line of code, the Khronos tutorial does an excellent job here of explaining how to get the instance.

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/01_Instance.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Instance>


# Creating the instance
The `vk.CreateInstance` method lets you initialize the instance. Conversely, using the `vk.DestroyInstance` method lets you destroy it!

### Important Odin-specific note:
The addresses of Vulkan functions are loaded dynamically from the libraries. The `load_proc_addresses` function therefore lets you initialize the API's methods, without which they will be null and the application will crash on the very first call to the Vulkan API.
```c
vk.load_proc_addresses(rawptr(glfw.GetInstanceProcAddress))
```

Same goes for this method which loads into memory the address of the current instance:
```c
vk.load_proc_addresses_instance(instance)
```


## vk_check
I added the `vk_check` utility method to easily inspect the result of Vulkan methods. Being a C API, the methods won't throw an exception if they fail to do their job. Methods that can return an error will return an enum of type `vk.Result`. If it's `SUCCESS`, all is well, otherwise, we're better off not continuing. In a real application, it would be better not to crash the application, but for a tutorial, it's just simpler this way. You'll find the call to this method all over the place!


## What's next

Right now if we pass Vulkan bad arguments, it'll happily return `VK_SUCCESS` and nothing — no warning, no error, just silently wrong output. That's because we haven't enabled a **validation layer** yet. In [03 - Validation Layers](./03_validation_layers.md) we finally enable `VK_LAYER_KHRONOS_validation`, so Vulkan starts telling us when we mess up.