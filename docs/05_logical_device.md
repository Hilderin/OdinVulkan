---
title: 05 - Logical Device
nav_order: 7
---

# 05 – Logical Device

We picked a physical device. Now we create a `VkDevice` from it - the logical device, the actual handle we'll use to talk to the GPU - and grab a graphics queue.

The full source for this step lives in `src/05_logical_device/main.odin`.

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/04_Logical_device_and_queues.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Logical_device_and_queues>

---

## What's new, in one glance
- `create_logical_device` - creates the `VkDevice` from the physical device, enables the queues and features we want, and returns the device + graphics queue.
- `required_extensions` is now a global - we need the same list to pick the physical device and to create the logical device.

`main` keeps the result of `pick_physical_device`, calls `create_logical_device`, and adds a `vk.DestroyDevice` to the cleanup section.

---

## The logical device in Vulkan

A physical device is the GPU. A logical device is *what we want from it*: which queues, which extensions, which features. You can have several logical devices on the same physical device, configured differently. Here we just create one.

`vkCreateDevice` is the call. Like everything else in Vulkan, it takes a `…_CreateInfo` struct filled with our requirements and gives us a handle back.

---

## Queue priorities

```c
queue_priority: f32 = 0.5
queue_create_info := vk.DeviceQueueCreateInfo {
	sType            = .DEVICE_QUEUE_CREATE_INFO,
	queueFamilyIndex = queue_index,
	queueCount       = 1,
	pQueuePriorities = &queue_priority,
}
```

Each queue family you request can be given a priority between 0.0 and 1.0. When several queues compete for GPU time, higher priority wins. We only create one queue, so the value doesn't really matter - but Vulkan still wants it.

The `pQueuePriorities` field is a *pointer to an array*, one float per queue. With one queue, pointing at a single local `f32` does the job. Note that Vulkan keeps no reference to this pointer after `vkCreateDevice` returns, so a local is fine.

We need the queue family index again here, so `create_logical_device` reuses `find_queue_families(physical_device, {.GRAPHICS})`. Slight waste of work, but cheap and keeps the function self-contained.

---

## Enabling features through the pNext chain

We already saw the pNext pattern in step 04 for *querying* features. Now we use it to *enable* them on the logical device, by chaining the same structs into `VkDeviceCreateInfo::pNext`:

```
DeviceCreateInfo
   → PhysicalDeviceFeatures2
       → PhysicalDeviceVulkan11Features (shaderDrawParameters)
           → PhysicalDeviceVulkan13Features (dynamicRendering)
               → PhysicalDeviceExtendedDynamicStateFeaturesEXT (extendedDynamicState)
```

Each struct in the chain must have its `sType` set and its `pNext` pointing to the next. Only the features set to `true` in those structs get enabled - anything you don't list stays off. That's exactly why we queried them in step 04: enabling a feature the device doesn't support fails device creation.

The interesting Odin bit: the chain is built by taking the address of local structs (`&device_feature_vulkan11`, etc.). The structs have to live until `vkCreateDevice` returns - local variables do, so no need for heap allocation.

---

## Enabling extensions

```c
enabledExtensionCount   = u32(len(required_extensions)),
ppEnabledExtensionNames = raw_data(required_extensions),
```

Same fields as instance creation, just on `VkDeviceCreateInfo`. The only required extension right now is `VK_KHR_SWAPCHAIN_EXTENSION_NAME` - we need it to present images to a surface, even before we have one.

`raw_data` gives a `^cstring` from an Odin slice. Vulkan's `ppEnabledExtensionNames` is `^^u8` in the bindings but accepts that pointer - this is the standard way to bridge an Odin `[]cstring` to a Vulkan "pointer to pointer to char" field.

---

## Getting the queue

```c
queue: vk.Queue
vk.GetDeviceQueue(device, queue_index, 0, &queue)
```

Queues aren't created - they're already there, owned by the device. `vkGetDeviceQueue` retrieves the handle of the queue at `(queueFamilyIndex, queueIndex within the family)`. `queue_index` here is the family index we found earlier. We requested one queue from that family, so we take the first one (index 0 within the family).

The function returns `(vk.Device, vk.Queue)` - same "return a flag" pattern as `find_queue_families` returns `(index, found)`. Multiple return values, no optionals.

---

## Cleanup ordering

```c
if device != nil {
	vk.DestroyDevice(device, nil)
}
if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
	vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
}
if instance != nil {
	vk.DestroyInstance(instance, nil)
}
```

Device before instance, as you'd expect: the device depends on the physical device, which depends on the instance. Reverse order of creation, same as in step 03.

---

## What's next

The setup phase is done. From here we move toward actually rendering something - the swapchain, the chain of presentable images attached to a window surface. See [06 - Create Window](./06_create_window.md).