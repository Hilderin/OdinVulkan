---
title: Home
nav_order: 1
---

# Odin Vulkan Tutorial

Hello hello!!
Yep, another Vulkan tutorial based on the [official Vulkan tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html)! While digging deeper into Odin and Vulkan, I realized the amount of tutorials and documentation out there is pretty thin. I love the Odin language for its fluidity, its ease... generally the vibe is, if it compiles, it should work fine. So, why not redo the Vulkan tutorial in this still fairly new language.

At the same time, I'll throw in my two cents in the tutorial by adding a few details I found important that I personally missed the first times I went through the tutorial. My goal is to share as much knowledge as possible on the subject while keeping it accessible, interesting and relevant.

The other thing that caused trouble is that there are two versions of the tutorial: the first version ([https://vulkan-tutorial.com](https://vulkan-tutorial.com)) is based on the C API, while the new official one from Khronos ([https://docs.vulkan.org/tutorial/latest/00_Introduction.html](https://docs.vulkan.org/tutorial/latest/00_Introduction.html)) uses the C++ RAII version which often wraps the lower-level calls we'll be using in Odin. On the other hand, the more recent official tutorial uses version 1.4 of the Vulkan API as well as Slang instead of GLSL. This new version of the Vulkan API makes developers' lives slightly easier by enabling dynamic rendering. The idea here is therefore to use the new version of the API and use Slang, but in Odin.

Each folder in `src/` is one step forward. The docs here explain what each step does and why it's done that way, in roughly the same order you'd write the code.

If you're new, start at [prerequisites](./prerequisites.md) to get the toolchain installed, then go through the steps below in order. Each doc links forward to the next one.

## Steps

| # | Doc | What it covers |
|---|-----|----------------|
| 01 | [Test Setup](./01_test_setup.md) | Sanity check: GLFW, Vulkan instance, SDK path, validation layers, slang compiler. |
| 02 | [Instance](./02_ instance.md) | Wrap instance creation in a procedure, query GLFW extensions, target Vulkan 1.4, destroy the instance on exit. |
| 03 | [Validation Layers](./03_validation_layers.md) | Enable `VK_LAYER_KHRONOS_validation`, add a debug messenger so Vulkan tells you when you mess up. |
| 04 | [Physical Device](./04_physical_device.md) | Pick a GPU that supports Vulkan and meets basic requirements (dedicated vs integrated, queues, features). |
| 05 | [Logical Device](./05_logical_device.md) | Create a logical device from the physical one, request graphics and present queues. |
| 06 | [Create Window](./06_create_window.md) | Finally, a visible window — GLFW window creation, the event loop, and tying it to the Vulkan instance. |
| 07 | [Surface](./07_surface.md) | Create a `VkSurfaceKHR` so Vulkan knows where to draw. |
| 08 | [Swap Chain](./08_swap_chain.md) | Query surface capabilities, pick a present mode and extent, create a swap chain. |
| 09 | [Image Views](./09_image_views.md) | Wrap each swap chain image in an image view so the pipeline can use them as render targets. |
| 10 | [Shaders Compilation](./10_shaders_compilation.md) | Compile Slang shaders to SPIR-V using `slangc` at build time. |
| 11 | [Shader Module](./11_shader_module.md) | Load the compiled SPIR-V into `VkShaderModule` objects. |
| 12 | [Graphics Pipeline](./12_graphics_pipeline.md) | The big one — vertex input, input assembly, rasterizer, multisampling, depth/stencil, color blend, layout, render pass. |
| 13 | [Command Buffers](./13_command_buffers.md) | Allocate and record command buffers that record the draw calls. |
| 14 | [Presentation — First Triangle](./14_presentation_first_triangle.md) | Submit command buffers, present the image, see a triangle on screen. |
| 15 | [Frames In Flight](./15_frames_in_flight.md) | Multiple frames in flight with fences and semaphores so the GPU stays fed. |
| 16 | [Swap Chain Recreation](./16_swap_chain_recreation.md) | Handle window resize: rebuild the swap chain without restarting the app. |
| 17 | [Vertex Input](./17_vertex_input.md) | Pass per-vertex data through vertex buffers instead of hard-coding it in the shader. |
| 18 | [Staging Buffer](./18_staging_buffer.md) | Use a host-visible staging buffer to upload data to device-local memory. |
| 19 | [Index Buffer](./19_index_buffer.md) | Indexed drawing to reuse vertices. |
| 20 | [Uniform Buffers](./20_uniform_buffers.md) | Per-frame uniform buffers for transformation matrices and other constants. |

## Reference

- [Code standards](./code_standards.md) — naming, style, compiler flags, Vulkan-specific gotchas.
- [Prerequisites](./prerequisites.md) — installing Odin, Vulkan SDK, GLFW, VSCode setup.
