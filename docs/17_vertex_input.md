---
title: 17 - Vertex Input
nav_order: 19
---

# 17 - Vertex Input

Until now the triangle's positions and colors were hardcoded inside the vertex shader as `static` arrays, indexed by `SV_VertexID`. That works for a triangle, but it doesn't scale to anything real - you can't ship a model as a shader. This step pulls that data out of the shader and feeds it from the application side, through a vertex buffer.

I originally planned to follow the tutorial chapter by chapter, but the Vulkan Tutorial splits this into two steps: "Vertex input description" (telling the pipeline the layout) and "Vertex buffer creation" (allocating and filling the buffer). Doing only the first one leaves the program broken, because the shader no longer has the hardcoded positions but the buffer doesn't exist yet - there's nothing to draw. So I merged both into a single step. It actually reads better that way: you see the description and the data it describes next to each other, and the distinction between *describing* a vertex and *providing* one is clearer when both happen in the same `main`.

The full source for this step lives in [src/17_vertex_input/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/17_vertex_input/main.odin).

The corresponding chapters in the Vulkan Tutorial are:
- Khronos version:
  - <https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/00_Vertex_input_description.html>
  - <https://docs.vulkan.org/tutorial/latest/04_Vertex_buffers/01_Vertex_buffer_creation.html>
- vulkan-tutorial.com version:
  - <https://vulkan-tutorial.com/Vertex_buffers/Vertex_input_description>
  - <https://vulkan-tutorial.com/Vertex_buffers/Vertex_buffer_creation>

---

## What's new, in one glance

- `vec2` / `vec3` - two type aliases on top of Odin's fixed-size arrays. Vulkan expects positions as `R32G32_SFLOAT` and colors as `R32G32B32_SFLOAT`, and these aliases make the matching obvious.
- `Vertex` struct - the in-memory layout of a single vertex: a `pos` then a `color`. The whole discussion from here on hangs off this struct.
- `VertexInputBindingDescription` + `VertexInputAttributeDescription` - the two halves of the vertex input state we plug into the pipeline. One describes the buffer, the other describes the fields inside it.
- `create_buffer` - a generic proc that creates a `vk.Buffer`, queries its memory requirements, finds a matching memory type, allocates `vk.DeviceMemory`, and binds the two together.
- `find_memory_type` - the small search loop that picks a GPU memory type matching both the buffer's requirements and the properties we want (here, host-visible and host-coherent).
- `mem_copy_to_buffer` - maps the buffer memory into CPU address space, copies our `vertices` slice in, and unmaps.
- `vk.CmdBindVertexBuffers` called inside `record_command_buffer`, then the existing `vk.CmdDraw` now reads from the bound buffer instead of from the shader's built-in index.
- The shader's `static` arrays are gone; `vertMain` now takes a `VSInput` struct whose fields are filled from the bindings described above.

---

## Two descriptions for one vertex

Vulkan splits vertex input into two pieces, and the split is worth understanding because it shows up everywhere:

- A **binding description** answers: "how is the buffer laid out?" One buffer, how many bytes per vertex? Each binding has a number.
- An **attribute description** answers: "what fields are in there, and where?" For each field, which binding it lives in (via binding number), which `location` the shader expects it at, what the pixel format is, and the byte offset from the start of the vertex.

We have one binding and two attributes, so the code looks like:

```c
binding_description := vk.VertexInputBindingDescription{}
binding_description.binding = 0
binding_description.stride = size_of(Vertex)
binding_description.inputRate = .VERTEX

vertex_attributes_description := []vk.VertexInputAttributeDescription {
	{binding = 0, location = 0, format = .R32G32_SFLOAT,    offset = u32(offset_of(Vertex, "pos"))},
	{binding = 0, location = 1, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Vertex, "color"))},
}
```

A couple of Odin-specific things are hiding in those few lines.

The `location` numbers here have to match the shader side. In Slang the link is *implicit*: `vertMain` takes a `VSInput` struct, and Slang assigns `location = 0` to the first field (`inPosition`) and `location = 1` to the second (`inColor`). If you reorder the struct fields without reordering the `location` values here, you get a red triangle where it should be green. The Khronos C++ version of the tutorial has you write `location = 0` etc. in the GLSL shader explicitly; Slang hides it, which is neater but also one more thing to keep in your head.

`offset_of(Vertex, pos)` is Odin's equivalent of C's `offsetof`. It's a builtin that takes the type and the bare field name (no quotes, no symbol - just `pos`), and returns an `int` corresponding to the offset of the field in the struct.

---

## Creating a buffer is four steps, not one

This is one of the Vulkan patterns that feels weird the first time: you don't "create a buffer" in one call. Vulkan separates a buffer object (its size, its usage flags, who can share it) from the memory that backs it. You create the buffer handle, query what kind of memory it wants, allocate memory of that type, and then bind the memory to the handle. Four steps, every time, wrapped inside `create_buffer`.

### 1. Create the buffer handle
```c
buffer_info := vk.BufferCreateInfo {
	sType       = .BUFFER_CREATE_INFO,
	size        = vk.DeviceSize(size),
	usage       = usage,
	sharingMode = .EXCLUSIVE,
}

buffer: vk.Buffer
vk_check(vk.CreateBuffer(device, &buffer_info, nil, &buffer), "Failed to create buffer!")
```

That gives us a handle with no storage.

### 2. Query what kind of memory it wants
```c
mem_requirements: vk.MemoryRequirements
vk.GetBufferMemoryRequirements(device, buffer, &mem_requirements)
```

`memoryTypeBits` is a bitmask saying "any of these memory types would do". `find_memory_type` walks the physical device's memory types and picks the first one that's both in that bitmask and has all the `properties` we asked for:

```c
find_memory_type :: proc(physical_device: vk.PhysicalDevice, type_filter: u32, properties: vk.MemoryPropertyFlags) -> (u32, bool) {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (type_filter & (1 << i)) != 0 && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i, true
		}
	}

	return 0, false
}
```

The `(type_filter & (1 << i)) != 0` check is "is type *i* in the allowed set", and the `& properties == properties` check is "does type *i* have **all** the flags we asked for". Order matters when chaining those with `&&` - if you flip the order you read every `memoryTypes[i]` even when the filter already says no, but for a handful of types that's irrelevant. The `-> (u32, bool)` return with `return 0, false` on failure is the Odin idiom for "value, ok" pairs you've seen in earlier steps.

The properties we ask for here are ` {.HOST_VISIBLE, .HOST_COHERENT}`:
- `HOST_VISIBLE` means the CPU can see this memory - it's mapped into the host's address space.
- `HOST_COHERENT` means we don't have to call `vk.InvalidateMappedMemoryRanges` / `vk.FlushMappedMemoryRanges` around our writes; the GPU sees them automatically.

This is the easy, slow choice. It's fine for a triangle. We'll revisit memory types later when staging buffers and device-local memory start mattering.


### 3. Allocate memory of that type
```c
alloc_info := vk.MemoryAllocateInfo {
    sType           = .MEMORY_ALLOCATE_INFO,
    allocationSize  = mem_requirements.size,
    memoryTypeIndex = memory_type_index,
}

buffer_memory: vk.DeviceMemory
vk_check(vk.AllocateMemory(device, &alloc_info, nil, &buffer_memory), "Failed to allocate memory!")
```

Then `vk.AllocateMemory` gives us a `vk.DeviceMemory`.


### 4. Bind the memory to the handle
```c
vk_check(vk.BindBufferMemory(device, buffer, buffer_memory, 0), "Failed to bind buffer memory!")
```

Then `vk.BindBufferMemory` glues the buffer handle and the buffer memory.

That last argument is an offset into the allocated memory, zero here because the buffer owns the whole allocation. You can bind several buffers into one big allocation at different offsets; that's an optimization we're not doing yet.

---

## Copying the data in

With a buffer bound to host-visible memory (visible from the CPU side), getting the vertices into the buffer is done by getting the buffer address (via `vk.MapMemory`), here `dest_data` and using a simple `mem.copy` to copy the data directly to this address. Don't forget to unmap. You can decide to leave the buffer mapped if you need to update the data regularly, we do that for the uniform buffer in a later chapter. This technique is called "persistent mapping". For now, we just need to update the vertex data once since it will never change.

```c
mem_copy_to_buffer :: proc(device: vk.Device, buffer_memory: vk.DeviceMemory, data: []$T) {
	size := size_of(T) * len(data)
	dest_data: rawptr

	vk_check(vk.MapMemory(device, buffer_memory, 0, vk.DeviceSize(size), {}, &dest_data), "Failed to map memory!")

	mem.copy(dest_data, raw_data(data), size)

	vk.UnmapMemory(device, buffer_memory)
}
```

Two Odin things worth flagging. The proc is generic over `T` (the `$T`), so it figures out the element type from the `[]T` we pass in - here `Vertex` - and `size_of(T)` works on that inferred type. `mem.copy` is `core:mem:mem_copy`, the Odin standard library's byte-wise copy; we imported `core:mem` at the top for it. `raw_data` turns the slice into a `rawptr` the way it did for the attribute description.

Because we picked `HOST_COHERENT`, we don't need to flush after the copy - the write is visible to the GPU the moment `UnmapMemory` returns. With a non-coherent memory type you'd have a `vk.FlushMappedMemoryRanges` call sitting between the copy and the unmap.

---

## Binding the buffer at record time

The pipeline already knew what to expect (we told it through the descriptions above). At record time we hand it the actual buffer. Inside `record_command_buffer`:

```c
offsets := vk.DeviceSize(0)
local_vertex_buffer := vertex_buffer
vk.CmdBindVertexBuffers(command_buffer, 0, 1, &local_vertex_buffer, &offsets)
```

`vk.CmdBindVertexBuffers` wants pointers-to-pointers: a `*vk.Buffer` for the buffers and a `*vk.DeviceSize` for the offsets, because it's designed to bind multiple buffers in one call. Our `vertex_buffer` is a `proc` parameter that lives on the call frame, and taking `&vertex_buffer` directly would technically be fine, but pulling it into a local first and taking the address of the local keeps the lifetimes obvious - the pointer we hand to Vulkan points at a stack slot we still control when the command gets recorded. Same idea for `offsets`. The `0` after the command buffer is `firstBinding`, the `1` is `bindingCount`.

After that, `vk.CmdDraw(command_buffer, 3, 1, 0, 0)` does the same draw as before - 3 vertices, 1 instance, start at 0 - but those 3 vertices now come from the bound buffer instead of the shader's `SV_VertexID` lookup. That's the whole change at draw time.

---

## The shader side

`shader.slang` lost its `static` arrays and gained an input struct:

```c
struct VSInput {
    float2 inPosition;
    float3 inColor;
};

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;
    output.pos = float4(input.inPosition, 0.0, 1.0);
    output.color = input.inColor;
    return output;
}
```

The `VSInput` fields line up with the two `VertexInputAttributeDescription` entries: `inPosition` is `location 0` of type `R32G32_SFLOAT` (`float2`), `inColor` is `location 1` of type `R32G32B32_SFLOAT` (`float3`). Slang fills those fields from whatever buffer is bound at the matching location. The rest of the shader is unchanged.

---

## Cleanup grew two calls

A buffer and its memory are two separate Vulkan objects, so they get destroyed separately, in the opposite order they were created:

```c
if vertex_buffer_memory != 0 {
	vk.FreeMemory(device, vertex_buffer_memory, nil)
}
if vertex_buffer != 0 {
	vk.DestroyBuffer(device, vertex_buffer, nil)
}
```

`vk.DestroyBuffer` doesn't free the memory bound to it because that memory could be shared - you free it yourself with `vk.FreeMemory`. The `0` guards keep cleanup safe on a half-initialized exit, same pattern as every other Vulkan object we destroy.

---

## Test it

Run the executable from the `src/17_vertex_input` directory. The startup log is the same as step 16's up to the fences, then adds two lines for the buffer and the copy. The window shows the same colored triangle, except it's no longer coming out of the shader - it's coming out of a `[]Vertex` slice in `main`, through a buffer we allocated, mapped, wrote to, and bound at record time. Resizing still works, since the swapchain recreation block from step 16 doesn't touch the vertex buffer (its lifetime is independent of the swapchain).

If validation complains about a missing or mismatched vertex input binding, double-check that the `location` values in `vertex_attributes_description` match the field order of `VSInput` in `shader.slang`.

---

## What's next

The triangle is fed from a real buffer now, but only because the GPU is okay reading host-coherent memory we mapped from the CPU. That's the slow path. The next step is to stage the data through a host-visible buffer into a device-local one, so the GPU keeps the hot data in its own fast memory and we only touch the slow memory once at upload time. That's [18 - Staging Buffer](./18_staging_buffer.md).