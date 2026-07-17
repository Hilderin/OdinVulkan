---
title: 03 - Validation Layers
nav_order: 5
---

# 03 – Validation Layers

Vulkan doesn't validate anything by default. If you pass wrong parameters, it'll happily return `VK_SUCCESS` or silently give you undefined behavior. **Validation layers** hook into Vulkan calls and check for mistakes at runtime.

The full source for this step lives in [src/03_validation_layers/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/03_validation_layers/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/00_Setup/02_Validation_layers.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Validation_layers>

IMPORTANT: Normally validation layers are only enabled in debug builds - they add overhead for no benefit in production. Here, for the tutorial, they're always on for simplicity.

For more information on Validation layer and how to configure it: <https://vulkan.lunarg.com/doc/view/latest/windows/khronos_validation_layer.html>

---

## What's new, in one glance
- `are_layers_supported` - checks that the required layers are installed.
- `debug_callback` - a function Vulkan calls every time a validation message is emitted.
- `VK_EXT_debug_utils` extension + `VkDebugUtilsMessengerEXT` - the handle that routes messages to your callback.
- The messenger is set up *twice*: once chained into `vkCreateInstance` (to catch messages during instance creation), then a permanent one right after.

---

## are_layers_supported

```c
vk.EnumerateInstanceLayerProperties(&layer_count, nil)
```

Standard Vulkan two-call pattern: first with `nil` to get the count, allocate, then fill. Returns `false` if a required layer is missing.

The standard validation layer is `VK_LAYER_KHRONOS_validation`.

---

## The debug callback

```c
debug_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	// ...
	return false
}
```

Two important Odin-specific things here:

- **`"system"` calling convention** - the callback is called from C code inside the Vulkan loader, not from Odin. Without this annotation the ABI won't match.
- **`context = runtime.default_context()`** - callbacks with `"system"` convention don't have an Odin context set. If we use `fmt.eprintfln` or anything that needs the context, we must set it first. Without this line the program will crash on the first validation message.

The callback checks each severity against the global `debug_level` to control verbosity.

---

## Debug messenger setup

The extension `VK_EXT_debug_utils` gives us `vkCreateDebugUtilsMessengerEXT` and friends.

### Chained into instance creation

```c
debug_create_info := vk.DebugUtilsMessengerCreateInfoEXT { ... }
create_info := vk.InstanceCreateInfo {
	// ...
	pNext = &debug_create_info,
}
```

Passing the messenger create info through `pNext` lets Vulkan use it during `vkCreateInstance` and `vkDestroyInstance`.

### Permanent messenger

```c
vk.CreateDebugUtilsMessengerEXT(instance, &debug_create_info, nil, &debug_messenger)
```

Second messenger with the same config, persists for the program's lifetime. The handle is stored in a global for cleanup.

Both the chained and the permanent messenger share the same `vk.DebugUtilsMessengerCreateInfoEXT` struct.

---

## Extensions list goes dynamic

We now need to append `VK_EXT_DEBUG_UTILS_EXTENSION_NAME`, so GLFW's list goes into a `[dynamic]cstring`:

```c
ext_names: [dynamic]cstring
defer delete(ext_names)
append(&ext_names, ..extensions)
append(&ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
```

---

## Cleanup ordering

The messenger must be destroyed *before* the instance:

```c
if instance != nil && vk.DestroyDebugUtilsMessengerEXT != nil {
	vk.DestroyDebugUtilsMessengerEXT(instance, debug_messenger, nil)
}
if instance != nil {
	vk.DestroyInstance(instance, nil)
}
```

The function pointer check avoids the call when the extension wasn't loaded.

---

## Test it

To see the layers in action, remove the `vk.DestroyDebugUtilsMessengerEXT` call from `main` and re-run. You should see a validation error about an un-destroyed debug messenger.

---

## What's next

[04 - Physical Device](./04_physical_device.md) introduces physical device selection and logical device creation, which is where we pick which GPU to use and configure what it can do.
