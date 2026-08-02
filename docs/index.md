---
title: Home
nav_order: 1
---

# Odin Vulkan Tutorial

Hello hello!!
Yep, another Vulkan tutorial based on the [official Vulkan tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html)! While digging deeper into Odin and Vulkan, I realized the amount of tutorials and documentation out there is pretty thin. I love the Odin language for its fluidity, its ease... generally the vibe is, if it compiles, it should work fine. So, why not redo the Vulkan tutorial in this still fairly new language.

At the same time, I'll throw in my two cents in the tutorial by adding a few details I found important that I personally missed the first times I went through the tutorial. My goal is to share as much knowledge as possible on the subject while keeping it accessible, interesting and relevant.


The other thing that caused trouble is that there are two versions of the tutorial: the first version ([https://vulkan-tutorial.com](https://vulkan-tutorial.com)) is based on the C API, while the new official one from Khronos ([https://docs.vulkan.org/tutorial/latest/00_Introduction.html](https://docs.vulkan.org/tutorial/latest/00_Introduction.html)) uses the C++ RAII version which often wraps the lower-level calls we'll be using in Odin. On the other hand, the more recent official tutorial uses version 1.4 of the Vulkan API as well as Slang instead of GLSL. This new version of the Vulkan API makes developers' lives slightly easier by enabling dynamic rendering. The idea here is therefore to use the new version of the API and use Slang, but in Odin.

All the code for this tutorial lives in the [repository](https://github.com/Hilderin/OdinVulkan), under the `src/` folder. Each folder in `src/` is one step forward. The docs here explain what each step does and why it's done that way, in roughly the same order you'd write the code.

If you're new, start at [prerequisites](./prerequisites.md) to get the toolchain installed, then go through the steps below in order. Each doc links forward to the next one.

> **Attribution:** This project is inspired by the [Khronos Vulkan® Tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html) (licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)) and the original [Vulkan Tutorial](https://vulkan-tutorial.com) by Alexander Overvoorde. The code and text in this repository are original work written in Odin and licensed under the [MIT License](https://github.com/Hilderin/OdinVulkan/blob/main/LICENSE).

## Steps

| # | Doc | What it covers |
|---|-----|----------------|
| 01 | [Test Setup](./01_test_setup.md) | Sanity check: GLFW, Vulkan instance, SDK path, validation layers, slang compiler. |
| 02 | [Instance](./02_instance.md) | Wrap instance creation in a procedure, query GLFW extensions, target Vulkan 1.4, destroy the instance on exit. |
| 03 | [Validation Layers](./03_validation_layers.md) | Enable `VK_LAYER_KHRONOS_validation`, add a debug messenger so Vulkan tells you when you mess up. |
| 04 | [Physical Device](./04_physical_device.md) | Pick a GPU that supports Vulkan and meets basic requirements (dedicated vs integrated, queues, features). |
| 05 | [Logical Device](./05_logical_device.md) | Create a logical device from the physical one, request graphics and present queues. |
| 06 | [Create Window](./06_create_window.md) | Finally, a visible window - GLFW window creation, the event loop, and tying it to the Vulkan instance. |
| 07 | [Surface](./07_surface.md) | Create a `VkSurfaceKHR` so Vulkan knows where to draw. |
| 08 | [Swap Chain](./08_swap_chain.md) | Query surface capabilities, pick a present mode and extent, create a swap chain. |
| 09 | [Image Views](./09_image_views.md) | Wrap each swap chain image in an image view so the pipeline can use them as render targets. |
| 10 | [Shaders Compilation](./10_shaders_compilation.md) | Compile Slang shaders to SPIR-V using `slangc` at run time. |
| 11 | [Shader Module](./11_shader_module.md) | Load the compiled SPIR-V into `VkShaderModule` objects. |
| 12 | [Graphics Pipeline](./12_graphics_pipeline.md) | The big one - fixed-function stages (vertex input, input assembly, rasterizer, multisampling, color blend) plus pipeline layout, no render pass thanks to dynamic rendering. |
| 13 | [Command Buffers](./13_command_buffers.md) | Allocate and record command buffers that record the draw calls. |
| 14 | [Presentation and First Triangle](./14_presentation_first_triangle.md) | Submit command buffers, present the image, see a triangle on screen. |
| 15 | [Frames In Flight](./15_frames_in_flight.md) | Multiple frames in flight with fences and semaphores so the GPU stays fed. |
| 16 | [Swap Chain Recreation](./16_swap_chain_recreation.md) | Handle window resize: rebuild the swap chain without restarting the app. |
| 17 | [Vertex Input](./17_vertex_input.md) | Pass per-vertex data through vertex buffers instead of hard-coding it in the shader. |
| 18 | [Staging Buffer](./18_staging_buffer.md) | Use a host-visible staging buffer to upload data to device-local memory. |
| 19 | [Index Buffer](./19_index_buffer.md) | Indexed drawing to reuse vertices. |
| 20 | [Uniform Buffers](./20_uniform_buffers.md) | Per-frame uniform buffers for transformation matrices and other constants. |
| 21 | [Images](./21_images.md) | Create a Vulkan image from a JPEG file and copy its pixels into GPU-local memory, first step toward texturing. |
| 22 | [Image view and sampler](./22_image_view_sampler.md) | Wrap the texture image in an image view and a sampler so a shader can read it; not wired into the pipeline yet. |
| 23 | [Combined image sampler](./23_combined_image_sampler.md) | Wire the texture into the pipeline: a second descriptor binding, a `texCoord` attribute, and a shader that samples it. |
| 24 | [Depth Buffering](./24_depth_buffering.md) | Add a real depth buffer and a second quad so the GPU can sort front-to-back; clean up the projection matrix. |
| 25 | [Loading Models](./25_loading_models.md) | Load the viking room mesh from a `.obj` file into the existing vertex and index buffers. |
| 26 | [Mipmaps](./26_mipmaps.md) | Generate a mip chain at load time so distant fragments sample smaller, pre-filtered copies of the texture. |
| 27 | [Multisampling](./27_multisampling.md) | Enable MSAA so triangle edges at the silhouette stop staircase-shimmering. |
| 28 | [Compute Shader](./28_compute_shader.md) | Bonus chapter: a GPU-driven particle system using a compute shader and shader storage buffers, no CPU round trip per frame. |
| 29 | [ovk Framework Init](./29_ovk_framework_init.md) | First refactoring step: extract instance, device, window, and GLFW boilerplate into the reusable `ovk` library. No new features, just cleaner code. |
| 30 | [ovk Framework Objects](./30_ovk_framework_objects.md) | Second refactoring step: wrap swap chain, buffers, images, shader modules, pipelines, descriptor sets into the `ovk` library. |
| 31 | [ovk Framework Commands](./31_ovk_framework_commands.md) | Third refactoring step: move command pools, command buffers, recording helpers, fences, semaphores, queues, buffer transfers, sampler and model loading into `ovk`; split up `utils.odin`. |
| 32 | [ovk Framework Helpers](./32_ovk_framework_helpers.md) | Fourth refactoring step: bundle the swap chain, color/depth images, semaphores, fences and the acquire/submit/present cycle into a `Swap_Chain_Helper`, move texture loading and a `Bitmap` helper into `ovk`. `main.odin` drops to about 435 lines. |
| 33 | [Pipeline Cache](./33_pipeline_cache.md) | Add a pipeline cache to the graphics pipeline creation, persist it to disk and load it back on the next run to speed up pipeline compilation. |
| 34 | [Debug Names](./34_debug_names.md) | Name every Vulkan object and label command buffer regions so RenderDoc captures and validation messages show readable names instead of raw handles. |
| 35 | [Synchronisation 2](./35_synchronisation_2.md) | Migrate the last legacy synchronization calls (`vkCmdPipelineBarrier`, `vkQueueSubmit`) to the modern `*2` versions inside the `ovk` library. |
| 36 | [Timeline Semaphores](./36_timeline_semaphores.md) | Replace the frame-in-flight fences with a single timeline semaphore carrying a monotonic counter, waited on from the host; swapchain acquire/present stays binary. |
| 37 | [ImGui](./37_imgui.md) | Vendor the dear imgui Odin bindings and their C library, add `ovk` helpers to init and draw ImGui, and show the demo window over the viking room using dynamic rendering. |
| 38 | [ImPlot](./38_implot.md) | Vendor the ImPlot binding and its C library, create the ImPlot context alongside ImGui, and show the ImPlot demo window. Covers the `Spec` trap where a zeroed `Spec{}` produces an invisible line. |
| 39 | [FPS Counter](./39_fps_counter.md) | Build an FPS counter and a scrolling graph of the frame rate with ImGui and ImPlot: a ring buffer, a `PlotLineG` getter callback, ImGui's smoothed framerate, and a frame time toggle. |

## References

- [Code standards](./code_standards.md) - naming, style, compiler flags, Vulkan-specific gotchas.
- [Prerequisites](./prerequisites.md) - installing Odin, Vulkan SDK, GLFW, VSCode setup.
- [VSCode Project Setup](./vscode_setup.md) - how the `.vscode/` config files work (tasks, debug, settings).
- [Setup Documentation Site](./setup_documentation_site.md) - build and preview this Jekyll site locally.
- [RenderDoc](./renderdoc.md) - GPU debugging with RenderDoc.
- [Rebuilding the ImGui library](./imgui_build.md) - rebuild the imgui C library for Windows and Linux when the version changes.
- [Rebuilding the ImPlot library](./implot_build.md) - rebuild the implot C library for Windows and Linux when the version changes.

## External References

- [Khronos Vulkan® Tutorial](https://docs.vulkan.org/tutorial/latest/00_Introduction.html)
- [The Vulkan Guide](https://docs.vulkan.org/guide/latest/index.html)
- [Vulkan Samples](https://docs.vulkan.org/samples/latest/README.html)
- [Vulkan Tutorial](https://vulkan-tutorial.com)
- [Slang language](https://shader-slang.org)
- [Odin Documentation](https://odin-lang.org/docs/)
- [Odin Examples](https://github.com/odin-lang/examples)

---

## License

Copyright (C) 2026 Guillaume Lebrun

The contents and code listings in this repository are licensed under the MIT License, unless stated otherwise. By contributing, you agree to license your contributions to the public under that same license.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See [LICENSE](https://github.com/Hilderin/OdinVulkan/blob/main/LICENSE) for the full text.
