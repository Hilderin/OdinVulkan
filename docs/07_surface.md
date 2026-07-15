---
title: 07 — Surface
nav_order: 9
---

# 07 – Surface

We now have a Vulkan instance and a window, but they don't know about each other. The `VkSurfaceKHR` is the bridge — a platform-agnostic handle that says "this is the thing Vulkan can present images to". Once it exists, we can finally ask a physical device: "can you draw to this window?"

The full source for this step lives in `src/07_surface/main.odin`.

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/01_Presentation/00_Window_surface.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Presentation/Window_surface>

---

## What's new, in one glance

- `create_surface` — one-liner that asks GLFW to build a `VkSurfaceKHR` from the window.
- `is_physical_device_support_surface` — queries whether a given queue family can present to the surface.
- Surface destruction in the cleanup section, before the instance goes.

The surface is created right after the window, *before* device selection — because device selection now needs the surface to ask the present-support question.

---

## The surface, and why it's a `KHR` extension

```c
create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> vk.SurfaceKHR {
	surface: vk.SurfaceKHR
	vk_check(glfw.CreateWindowSurface(instance, window, nil, &surface), "Failed to create surface!")

	return surface
}
```

`VkSurfaceKHR` is not part of Vulkan core. It lives in the `VK_KHR_surface` extension, which is why every related type and call has the `KHR` suffix. Vulkan itself has no opinion about windows — it just deals with images and queues. The extension is the agreed-upon way to plug a windowing system in, without Vulkan having to know about Win32, X11 or Wayland.

We don't call `vkCreateXcbSurfaceKHR` or any of the platform calls directly. GLFW owns the window, so GLFW owns the platform check — `glfw.CreateWindowSurface` picks the right backend and hands us back a `VkSurfaceKHR` we can use against any Vulkan call. The signature in the Odin glfw binding is literally `proc(instance, window, allocator, &surface) -> vk.Result`, so it slots into the same `vk_check` helper we already use for Vulkan calls.

One thing worth noting: the surface is created from the `instance`, not from a device. It's tied to the instance, so it survives device selection and logical device creation. That's also why, in cleanup, it has to be destroyed *before* the instance but *after* the logical device.

---

## Present support per queue family

```c
is_physical_device_support_surface :: proc(physical_device: vk.PhysicalDevice, queue_index: u32, surface: vk.SurfaceKHR) -> bool {
	supported: b32
	result := vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, queue_index, surface, &supported)
	// ...
	return bool(supported)
}
```

A graphics queue family is not automatically a present queue family. They usually coincide on desktop GPUs, but Vulkan refuses to assume it — you have to ask, for each queue family, with `vkGetPhysicalDeviceSurfaceSupportKHR`. The answer can be different per surface, which is why the call takes the surface as an argument.

In Odin the Vulkan bindings define `supported` as a `b32` (Vulkan's `VkBool32`). A bare cast to `bool` is enough to bring it back into Odin's bool world.

The `find_queue_families` change is small but worth a sentence:

```c
if surface == 0 || is_physical_device_support_surface(physical_device, u32(i), surface) {
	return u32(i), true
}
```

The `surface == 0` guard keeps the function usable from `score_device`'s old call sites, where we just want a graphics family and don't have a surface yet. In practice every call now passes a real surface, but the guard costs nothing and makes the function a bit more honest about what it accepts.

---

## Cleanup ordering

```c
if device != nil {
	vk.DestroyDevice(device, nil)
}
if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
	vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
}
if surface != 0 {
	vk.DestroySurfaceKHR(instance, surface, nil)
}
if instance != nil {
	vk.DestroyInstance(instance, nil)
}
```

The surface sits in the same cleanup window as the debug messenger: both are tied to the instance, so they must be destroyed before `vkDestroyInstance`. The surface also implies that the logical device has stopped using it, which is already true by the time we reach this block — `vkDestroyDevice` comes first.

`vkDestroySurfaceKHR` is part of the `VK_KHR_surface` extension, but it's a loader entry point that's always present as long as the instance was created with the extension enabled (GLFW asks for it for us, see step 02).

---

## Test it

The window still does nothing visible — there's no swapchain yet, no image to put on it. The surface is just a handle Vulkan agreed to recognize.

---

## What's next

With a surface in hand, the next step is the swapchain — the queue of images Vulkan will cycle through to actually put frames on that window. That's where presentation stops being theoretical. That's [08 — Swap Chain](./08_swap_chain.md).