# Roadmap

This is my roadmap for learning Vulkan with Odin.

The idea is simple: I build solid foundations first, then I get to the pretty stuff as fast as I can. I'll add debugging tools when they actually become useful, not all up front. And I'll keep things out of the way until they start to matter.

## Setup / Helpers
- [x] Pipeline cache persistence - save the cache to disk, load it on startup. A cheap win that shaves off seconds every launch.
- [x] Debug object names + command labels - name buffers, images and pipelines. Otherwise RenderDoc captures are a wall of meaningless handles.
- [x] Synchronization 2 - `vkCmdPipelineBarrier2` + `vkQueueSubmit2`. I learn the modern version right away, skipping the legacy barriers entirely.
- [x] Timeline semaphores - one primitive for all my synchronization, instead of a growing pile of fences and binary semaphores.
- [x] ImGui integration
- [ ] FPS counter
- [ ] ImPlot integration
- [ ] FPS counter graph

## Sick of the viking room
- [ ] Cubemap texture
- [ ] Skybox rendering
- [ ] Camera user movement

## Scene + GLTF
- [ ] Scene graph - prerequisites of GLTF multi models
- [ ] GLTF loading 
- [ ] GLTF material loading - base color, metallic, roughness, emissive, alpha.
- [ ] GLTF texture loading - with the right color space handling.
- [ ] GLTF punctual lights - directional, point and spot lights from the file.
- [ ] PBR metallic-roughness - the base shading model.

## Better shader management
- [ ] Shader runtime compilation with hash cache - don't recompile what I already compiled.
- [ ] Shader hot reload - tweak a shader, see the result, no restart. This saves so much time.
- [ ] Shader reflection via Slang - pull bindings, push constants and vertex inputs out of the shader.
- [ ] Specialization constants - configure a shader at pipeline creation without a dozen shader source files.

## Shadow
- [ ] Reversed-Z + depth precision - I'm doing this here, close to the shadow work, rather than in some standalone rasterization phase.
- [ ] Shadow mapping + PCF - a depth map from the light, sampled with a comparison sampler.
- [ ] Cascaded shadow maps - split the frustum for better directional shadows.
- [ ] Point light shadows - a cubemap depth map for omnidirectional lights.
- [ ] Depth pre-pass + overdraw visualization - once the scene is busy enough that overdraw is actually visible.

## More debugging tools
- [ ] RenderDoc - set it up and trigger captures from inside the app.
- [ ] GPU profiling - `vkCmdWriteTimestamp2` and pipeline statistics queries. This only makes sense once I have passes worth measuring, so it lives here, not earlier.

## Better visuals
- [ ] HDR offscreen rendering - render to a float target. The quality jump is immediate, and everything else depends on it.
- [ ] Tone mapping - Reinhard, filmic, ACES, compare the curves.
- [ ] Normal mapping - and generating the missing tangent vectors.
- [ ] Parallax mapping - a bonus, faking depth with a height map.
- [ ] Equirectangular to cubemap - I'll need a good HDR panorama for this one.
- [ ] Diffuse irradiance map - low-frequency environment lighting.
- [ ] Prefiltered specular environment - the roughness-dependent mip levels.
- [ ] BRDF integration LUT - the precomputed specular term.
- [ ] Image-based lighting - combine the three above and the scene finally looks like something.

## Post-processing
- [ ] Bloom - extract bright pixels, downsample, blur, combine.
- [ ] 3D LUT color grading
- [ ] Motion vectors - everything temporal builds on this.
- [ ] Temporal anti-aliasing + history rejection
- [ ] SSAO / GTAO - ambient occlusion from depth and normals.
- [ ] Screen-space reflections
- [ ] Motion blur
- [ ] Depth of field, chromatic aberration, vignette, film grain - the cheap lens effects.

## Advanced lighting
- [ ] Forward+ tiled lighting - per-tile light lists.
- [ ] Clustered lighting - the tiled version with depth slices.
- [ ] Area lights with LTC - linearly transformed cosines.
- [ ] Light probes - baked indirect light for local areas.
- [ ] Meshlets and mesh shaders - I'll push this further down, closer to GPU-driven rendering where it fits better.


## Compute
- [ ] Compute image processing - blur, edge detection, histogram.
- [ ] Parallel reduction, prefix sum, stream compaction - the building blocks.
- [ ] Compute particles + particle indirect rendering
- [ ] Boids simulation
- [ ] 2D grid fluid / SPH fluid
- [ ] Reaction-diffusion - procedural patterns, weirdly satisfying.
- [ ] Procedural texture generation - noise, distance fields, terrain.
- [ ] SDF ray marching - no triangles, just math.
- [ ] Marching cubes and voxel meshing
- [ ] Compute ray tracing - a small software tracer.

## Transparency and volumetrics
- [ ] Alpha blending limitations - see the artifacts first, then fix them.
- [ ] Weighted blended OIT
- [ ] Depth peeling
- [ ] Per-pixel linked-list OIT
- [ ] Stochastic transparency
- [ ] Volumetric fog, light shafts, volumetric shadows
- [ ] Local fog volumes
- [ ] Volumetric clouds

## Drawing architectures
- [ ] Indirect drawing, indexed indirect, multi-draw indirect
- [ ] Indirect count - let the GPU decide how many draws run.
- [ ] GPU frustum culling, GPU occlusion culling, GPU LOD selection
- [ ] GPU material sorting
- [ ] GPU-driven rendering - this is where the occlusion family lands: occlusion queries, depth pyramid, HiZ.
- [ ] Deferred shading and a forward/deferred comparison.
- [ ] Visibility buffer and tile-based material resolve
- [ ] Bindless materials, descriptor indexing

## Animations
- [ ] GLTF animations - the touch that makes the scene feel alive.
- [ ] Transform hierarchy
- [ ] GPU skinning
- [ ] Compute skinning
- [ ] Animation interpolation, blending, additive animation
- [ ] Inverse kinematics (CCD, FABRIK)
- [ ] Dual-quaternion skinning
- [ ] Cloth simulation
- [ ] GPU deformers

## Ray tracing
- [ ] Acceleration structures - BLAS for meshes, TLAS for instances.
- [ ] Ray queries
- [ ] Ray-traced hard shadows and AO
- [ ] Ray tracing pipeline + shader binding table
- [ ] Ray-traced reflections and hybrid reflections
- [ ] Path tracing, multiple importance sampling, Russian roulette
- [ ] Denoising
- [ ] Ray-traced GI, DDGI, ReSTIR

## Infrastructure and portability
- [ ] Minimal render graph + visualization
- [ ] Transient image aliasing
- [ ] Descriptor pool strategies
- [ ] Pipeline libraries and shader objects
- [ ] Resource lifetime tracking, device-lost diagnostics
- [ ] Multi-window rendering
- [ ] Feature detection and fallback paths
- [ ] Subpasses versus dynamic rendering
- [ ] Android Vulkan, touch input, mobile texture formats
- [ ] Variable rate shading and foveated rendering
- [ ] WebGPU port, WebAssembly, cross-platform shaders

## Other Small experiments
- [ ] GPU wireframe rendering
- [ ] Outline rendering
- [ ] Decals
- [ ] Portals and mirrors
- [ ] Clip planes
- [ ] Infinite grid
- [ ] Billboards
- [ ] GPU text rendering (SDF / MSDF)
- [ ] Screenshot comparison and deterministic capture mode

