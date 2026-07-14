---
title: Code Standards
nav_order: 99
---

# Code standards

This document lists the conventions we try to follow across every `src/` step. They are mostly the same as the [Odin examples naming and style convention](https://github.com/odin-lang/examples/wiki/Naming-and-style-convention), with a few notes specific to this project.

The goal of these standards is to keep all the examples consistent, to match the Odin conventions you'll find in other projects, and to follow good practices.


## Naming

In general: `Ada_Case` for types, `snake_case` for values.

| Element            | Convention             |
|--------------------|------------------------|
| Import name        | `snake_case` (prefer single word) |
| Types              | `Ada_Case`             |
| Enum values        | `Ada_Case`             |
| Procedures         | `snake_case`           |
| Local variables    | `snake_case`           |
| Constant variables | `SCREAMING_SNAKE_CASE` |
| Global variables   | `snake_case` (no special prefix) |


## Compiler flags

The project must build cleanly with:

```
odin build . -debug -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors
```

What these flags check, roughly:

- `-vet` — unused variables, common mistakes.
- `-strict-style` — enforces a subset of the style rules below.
- `-vet-tabs` — complains if you mix tabs and spaces for indentation.
- `-disallow-do` — forbids `do` blocks, which we don't use.
- `-warnings-as-errors` — warnings don't get to hide.

If any of these flag something, fix the code, don't relax the flags.


## Style

### Opening brace at end of line

```c
some_proc :: proc() {
}

Some_Type :: struct {
}
```

Allman style (brace on its own line) is not used in this project.

### Prefer `val := Some_Type {` over `val: Some_Type = {`

```c
cam := Camera {
	position = { 50, 50, 10 },
}
```

Not:

```c
cam: Camera = {
	position = { 50, 50, 10 },
}
```

Exception: `val: f32 = 5` and `val := f32(5)` are both fine.

### Prefer type inference

```c
sound := load_sound(filename)
```

Not:

```c
sound: Sound = load_sound(filename)
```

Be explicit about the type only when it actually helps readability. One case where you have to: creating a union and assigning a specific variant on the same line.

### Use initializers when possible

```c
cam := Camera {
	position = { 50, 50, 10 },
	offset = { 10, 20 },
	zoom = 2,
}
```

Not:

```c
cam: Camera
cam.position = { 50, 50, 10 }
cam.offset = { 10, 20 }
cam.zoom = 2
```

### Write `val: int` and `val := 5`

No spaces around the `:` in a declaration, no space before `:=`. So `val : int`, `val:= 5` and `val: = 5` are all out.

### Don't overuse `defer`

`defer` is great when there are several ways out of a scope and the same cleanup must run on all of them. It's not a freebie: the code is no longer linear, so it's a bit harder to read.

If a proc has exactly one return point at the end, just call `delete` (or whatever cleanup) explicitly before the return. Save `defer` for when it actually earns its place.

### Tabs for indentation, spaces for alignment

Indentation is tabs. Alignment between adjacent lines is spaces, so the alignment looks the same regardless of the reader's tab width.

When a parameter list is too long and gets wrapped, the continuation lines are indented with tabs up to the base column, then spaces to align with the first parameter:

```c
some_proc :: proc(a: int, lot: f32, of: string, parameters: f64,
                  is: f32, fun: string) {
	fmt.println(fun)
}
```


## Vulkan-specific notes

A few things that come up often in this codebase and aren't covered by the generic Odin conventions.

- `sType` on every struct in a `pNext` chain. Vulkan drivers ignore structs whose `sType` doesn't match, which means a missing `sType` fails silently: the feature is queried or enabled as if the struct wasn't there. Always set `sType` right after declaring the struct.
- Activate the validation layers you check for. `areLayersSupported` only tells you the layer is installed; you still have to pass it to `createInfo.enabledLayerCount` / `ppEnabledLayerNames`. A check without activation is a no-op.
- `cstring == cstring` compares by content in Odin. Don't convert to `string` just to compare extension or layer names — that allocates for nothing. Compare the `cstring`s directly.
- `for value, index in` — the index comes second. It's the opposite of what people coming from Rust or Go expect.
- Anything returned by `make` needs a matching `delete`. If a proc returns a slice it allocated, the caller is responsible for freeing it; use `defer delete(...)` at the call site.
- Always use `vk_check` to verify result of a Vulkan method except when the result could be more specific like VK_SUBOPTIMAL_KHR or VK_ERROR_OUT_OF_DATE_KHR