---
title: 01 — Test Setup
nav_order: 3
---

# 01 - Test Setup

This first step isn't going to render anything. Before we go further, we want to make sure the whole toolchain works: that Odin compiles, that GLFW initialises, that the Vulkan SDK is reachable, and that our GPU actually supports Vulkan.

Think of this as a sanity check. If something is wrong with the setup, better to find out now than three chapters in.

The full source for this step lives in `src/01_test_setup/main.odin`. Open it side by side with this doc.


## What we want to accomplish

Five things, in order:

1. **GLFW** can initialise.
2. **Vulkan** can create an `Instance`.
3. The **VULKAN_SDK** environment variable points to a valid SDK installation.
4. The **Vulkan validation layers** are installed and discoverable.
5. The **slang compiler** (`slangc`) is present in the SDK.

If all five pass, we're ready to actually build something. If any of them fails, the error message will (hopefully) point you back to the [prerequisites](./prerequisites.md) doc.


## Run it

Open the `src/01_test_setup/` folder in VSCode and hit `F5`. Or, from the command line:

```
odin build . -debug -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors -out:bin/debug/01_test_setup
./bin/debug/01_test_setup
```

If everything is in order you should see:

```
Test setup
--------------------------
GLFW... OK!
Vulkan... OK!
Vulkan SDK path... OK!
Vulkan validation layers... OK!
Slang compiler found... OK!

Good job, everything is setup correctly!
```

If you get an error instead, jump back to [prerequisites](./prerequisites.md) — that's exactly what it's there for.


## What's next

We have proof our environment works, but that's all. No window, no rendering, yet. In [02 - Instance](./02_instance.md) we'll wrap instance creation behind a proper procedure, ask Vulkan for the extensions GLFW needs, and start cleaning up after ourselves.