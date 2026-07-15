---
title: 04 - Physical Device
nav_order: 6
---

# 04 – Physical Device

We have a Vulkan instance, but it's just a handle - it doesn't know which GPU we want to use. This step enumerates the available physical devices, checks that they support what we need, and picks the best one.

The full source for this step lives in [src/04_physical_device/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/04_physical_device/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/03_Physical_devices_and_queue_families.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Physical_devices_and_queue_families>

Where the tutorial picks the first suitable device, this step takes a scoring approach: each device gets a score, the highest wins. Discrete GPUs score higher, missing features disqualify, and `maxImageDimension2D` acts as a tiebreaker.

---

## What's new, in one glance
- `find_queue_families` - lists the device's queue families, finds one matching the requested flags.
- `get_device_features` - queries several feature structs at once through a pNext chain.
- `score_device` - rates a physical device against our requirements and returns a score (or -1 if unsuitable).
- `pick_physical_device` - enumerates devices, calls `score_device` on each, keeps the best.

`main` now calls `pick_physical_device(instance)` between instance creation and cleanup.

---

## Enumerating physical devices

`vkEnumeratePhysicalDevices` is the same two-call pattern we've already seen: count first, allocate, then fill. Nothing new there.

What's worth knowing is what we query on each device once we have it, and that's where the new Vulkan calls show up.

---

## Queue families

Almost every Vulkan operation - drawing, transferring memory, compute - goes through a queue. Queues come from **queue families**, and each family only supports a subset of operations. A device might have one family that does graphics + compute, and another that only does transfer.

`find_queue_families` lists the families with `vkGetPhysicalDeviceQueueFamilyProperties` and looks for one whose flags include what we asked for. Right now we only need `{.GRAPHICS}`.

The flag check is a bitmask test: `(queue_flags & queue_family.queueFlags) == queue_flags` verifies that *all* requested bits are present. Passing `{.GRAPHICS}` will match a family that supports graphics, even if it also supports compute or transfer.

The function returns `(index, found)` - a simple pattern that avoids optional types. If no matching family is found, the caller gets `(0, false)`.

---

## Device properties and features

`vkGetPhysicalDeviceProperties` gives us the basics: name, type (discrete, integrated, virtual, CPU), supported API version, and limits like `maxImageDimension2D`.

`vkGetPhysicalDeviceFeatures2` tells us which optional features the device supports. Unlike the simpler `vkGetPhysicalDeviceFeatures`, the `2` version uses a pNext chain, so we can query multiple feature structs in one call.

### pNext chaining in Odin

In C++ you'd use `get<>()` with template magic. In Odin you build the chain manually by setting each struct's `pNext` to the address of the next one:

```
PhysicalDeviceFeatures2 → Vulkan11Features → Vulkan13Features → ExtendedDynamicStateFeaturesEXT
```

You'll see this pNext pattern a lot in Vulkan - it's how the API extends itself without breaking ABI. Get comfortable wiring structs together by hand.

---

## Scoring a device

`score_device` is where we decide if a GPU is good enough. It returns a positive score for suitable devices, or -1 for rejects.

The checks, in order:

- **Vulkan 1.4 minimum** - we want modern features like `dynamicRendering` without pulling them in as extensions.
- **Graphics queue family** - no graphics queue, not a graphics card.
- **Required extensions** - `vkEnumerateDeviceExtensionProperties` with the same two-call pattern as instance layers. Only the swapchain extension for now.
- **Required features** - `shaderDrawParameters`, `dynamicRendering`, `extendedDynamicState`. Each rejects the device if missing.

If all checks pass, the score favors discrete GPUs (+1000), then integrated GPUs (+500), and adds `maxImageDimension2D` as a rough capability tiebreaker.

---

## Device name as a string

```c
name := string(cstring(&props.deviceName[0]))
```

`deviceName` is a fixed-size `[256]u8` C array in Odin's bindings. To use it as a proper Odin string we cast to `cstring` first, then convert with `string()`. This is the idiomatic way to read any Vulkan fixed-size char array in Odin - you'll see it again for extension names, layer names, and so on.

---

## What's next

[05 - Logical Device](./05_logical_device.md) creates a `VkDevice` from the selected physical device and retrieves the graphics queue handle - the actual object we'll use to submit commands.