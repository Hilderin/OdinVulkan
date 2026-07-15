---
title: 11 - Shader Module
nav_order: 13
---

# 11 – Shader Module

Step 10 gave us a SPIR-V blob in memory but no Vulkan call touched it. This step closes the gap: we hand those bytes to `vk.CreateShaderModule` and get back a `vk.ShaderModule` handle - the opaque object the graphics pipeline will later reference, one per shader stage.

A detail worth noting: the Slang setup compiles `vertMain` and `fragMain` into a *single* `.spv` blob, and we feed that whole blob to one `vk.ShaderModule`. Vulkan is fine with this - a module can hold several entry points, and the pipeline stage state later picks the one it wants by name. The Original C++ tutorial instead produces two separate modules (one per stage), because it compiles one GLSL file per stage. Same end result, fewer files here.

The full source for this step lives in `src/11_shader_module/main.odin`. The `shader_compiler.odin` from step 10 is reused unchanged.

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version: <https://docs.vulkan.org/tutorial/latest/03_Drawing_a_triangle/02_Graphics_pipeline_basics/01_Shader_modules.html>
- vulkan-tutorial.com version: <https://vulkan-tutorial.com/Drawing_a_triangle/Graphics_pipeline_basics/Shader_modules>

---

## What's new, in one glance

- `create_shader_module` - compiles the `.slang` file, builds a `vk.ShaderModuleCreateInfo`, and calls `vk.CreateShaderModule`. Returns the single module handle.
- `main` calls it right after the image views, with `"shader.slang"` and the `{"vertMain", "fragMain"}` entry-point list.
- Cleanup gets a `vk.DestroyShaderModule` call before the device goes.

---

## `vk.CreateShaderModule`, and the `pCode` / `codeSize` mismatch

The struct is small, but two fields look contradictory at first glance:

```c
create_info := vk.ShaderModuleCreateInfo {
	sType    = .SHADER_MODULE_CREATE_INFO,
	codeSize = len(spv),
	pCode    = raw_data(slice.reinterpret([]u32, spv)),
}
```

- **`pCode`** wants a pointer to `u32`. Vulkan reads SPIR-V as 32-bit words, not bytes. Our blob comes back from `compile_slang_shader` as `[]u8`.
- **`codeSize`** is in *bytes*, even though `pCode` is a `u32` pointer. That's a real Vulkan quirk: the field name says "size" and the type says "words" - don't divide by 4. `len(spv)` (byte count) is correct.

The first point is where Odin-specific care shows up. `slice.reinterpret` from `core:slice` gives us the same backing memory typed as `[]u32` - no copy, no allocation, just a different view of the bytes. `raw_data` then hands its pointer to Vulkan. If you ever skip the reinterpret and just pass `raw_data(spv)` directly, the compiler's type checker will catch it (the field wants `^u32`), which is the kind of safety net that makes this less painful than it is in C.

The SPIR-V byte length being a multiple of 4 isn't an accident - SPIR-V is specified as a stream of 32-bit words, so a well-formed blob always reinterprets cleanly. If `slangc` somehow handed us a length that wasn't word-aligned, `slice.reinterpret` would assert at runtime, which is preferable to feeding garbage to the driver.

---

## One module, two entry points

```c
shader_module := create_shader_module(device, "shader.slang", {"vertMain", "fragMain"})
```

Because both entry points live in the same module, we don't create a second `vk.ShaderModule` for the fragment stage. When we build the graphics pipeline in the next step, each `vk.PipelineShaderStageCreateInfo` will reference this same handle and just set a different `pName` (`"vertMain"` or `"fragMain"`). Splitting a single Slang file into two modules would mean recompiling twice with different `-entry` flags - doable, but pointless here.

If you later split shaders into one `.slang` file per stage, this proc still works unchanged: call it twice with different paths and single-element entry-point slices. The proc doesn't assume a combined blob; the Slang setup does.

---

## Compilation lives inside the proc

Note where `compile_slang_shader` is called:

```c
spv, ok := compile_slang_shader(slang_path, entry_points)
if !ok {
	fmt.eprintln("Shader compilation failed.")
	os.exit(1)
}
defer delete(spv)
```

The SPIR-V bytes are produced and consumed inside `create_shader_module`, then freed immediately after `vk.CreateShaderModule` returns. Vulkan copies the bytes into its own memory during the create call - once `vk.CreateShaderModule` returns `.SUCCESS`, the `[]u8` is dead weight and can be (and is) deleted. Keeping the blob alive beyond this point would just leak heap for no reason.

The hard `os.exit(1)` on failure is a tutorial simplification: a real engine would surface the error and recover (or fall back to a recompiled shader). For now, "shader didn't compile → stop everything" is the honest behavior.

---

## Cleanup

```c
if shader_module != 0 {
	vk.DestroyShaderModule(device, shader_module, nil)
}
```

The `0` guard is the same defensive habit as elsewhere - covers the case where `create_shader_module` exited early before assigning the handle. The module is created from the `vk.Device`, so it must be destroyed before the device. Placed first in cleanup, ahead of the image views and the swapchain, which is the Vulkan-mandated order: objects before the objects they were created from.

---

## Test it

The window is still blank - the module exists but nothing references it yet. What you should see in the terminal is the usual setup chain running to completion, now with a `Shader module... OK` line after the image views, followed by `Vulkan initialization completed with success!`. If slangc isn't on your `PATH` via `VULKAN_SDK`, the proc prints "Shader compilation failed." and exits - that's the same failure mode as step 10.

---

## What's next

With a `vk.ShaderModule` in hand, the next step assembles the graphics pipeline - the programmable stages (our shader module, referenced twice with different entry points) plus all the fixed-function state Vulkan still requires you to spell out explicitly. That's [12 - Graphics Pipeline](./12_graphics_pipeline.md).