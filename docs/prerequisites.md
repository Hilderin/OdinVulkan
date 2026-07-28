---
title: Prerequisites
nav_order: 2
---

# Prerequisites

You will need:
- Odin language
- VSCode
- Odin Language VSCode Extension
- Vulkan SDK
- GLFW
- Slang VSCode Extension (optional but recommended for editing shaders)
- clang-format (optional but recommended for formatting slang shaders)

Plus, depending on your OS, one of the following VSCode debugger extensions:
- **Windows**: C/C++ VSCode Extension (for `cppvsdbg` - see below)
- **Linux**: CodeLLDB VSCode Extension (install it from VSCode the first time you press `F5`)


# Odin language

Follow the instructions on the [Odin install page](https://odin-lang.org/docs/install/).

At the end you should be able to execute:
```bash
odin version
```

Output example:
```
odin version dev-2026-07-nightly:819fdc7
```

# VSCode
I will use VSCode because it's the IDE I commonly use but feel free to use any IDE you prefer.
All the projects in the repository are setuped for VSCode.

Follow the instructions on the [VSCode download page](https://code.visualstudio.com/download).

At the end you should be able to open VSCode from your start menu or via the `code` command.


# Odin Language VSCode Extension
This extension will provide a Language Server (LSP) which allows VSCode to validate your odin code, have code documentation and code formatting.

From VSCode, go to Extensions which should be available from the side bar (Default shortcut is Ctrl-Shift-X).
Search for `Odin Language`. Be sure you select the Odin language extension published by Daniel Gavin and click `install`.

For more instructions: [the ols repository on GitHub](https://github.com/DanielGavin/ols).

The first time you start a project with a .odin file, the `ols.json` file should be created at the root of your project. This file contains configuration for the Odin Language Server. The list of the available settings are defined in the [ols configuration section](https://github.com/DanielGavin/ols?tab=readme-ov-file#configuration). This file is already present for each project in this repository.


{: .warning }
> The first time you will open a `.odin` file, the extension will ask via a notification to install the latest version. You need to click `Yes`. Otherwise the extension will not install. 


# Vulkan SDK
Vulkan SDK is required to activate the validation layer. It helps a lot when developping and debugging Vulkan applications.

Follow instructions: 
- Windows: [Vulkan SDK - Windows getting started](https://vulkan.lunarg.com/doc/sdk/latest/windows/getting_started.html)
- Linux: [Vulkan SDK - Linux getting started](https://vulkan.lunarg.com/doc/sdk/latest/linux/getting_started.html)
- Mac: [Vulkan SDK - Mac getting started](https://vulkan.lunarg.com/doc/sdk/latest/mac/getting_started.html)


# GLFW
GLFW handles the window, the inputs and the surface for us. This project uses Odin's bundled `vendor:glfw` collection, so the way it links depends on your OS.

{: .note }
> On Windows and macOS, Odin ships a prebuilt static GLFW library in its `vendor/glfw/lib/` folder, so there is nothing to install. The build picks it up automatically.

### Linux

Linux links against the system's GLFW, so you need the development package:

- Debian / Ubuntu:
  ```
  sudo apt install libglfw3-dev
  ```
- Fedora / RHEL:
  ```
  sudo dnf install glfw-devel
  ```
- Arch:
  ```
  sudo pacman -S glfw
  ```

If you would rather link statically, drop a `libglfw3.a` next to Odin's `vendor/glfw/lib/` and build with `GLFW_SHARED=false`:

```
odin build . -debug -define:GLFW_SHARED=false
```

### macOS

By default Odin uses the bundled `lib/darwin/libglfw3.a` static library, so no extra install is needed.

If you prefer the dynamic build (`GLFW_SHARED=true`), install it through Homebrew:

```
brew install glfw
```

### Windows

By default Odin uses the bundled `glfw3_mt.lib` static library, so no extra install is needed.

If you want the DLL build (`GLFW_SHARED=true`), grab the precompiled Windows binaries from the [GLFW download page](https://www.glfw.org/download), put `glfw3.dll` next to your executable and build with:

```
odin build . -debug -define:GLFW_SHARED=true
```


# C/C++ VSCode Extension (Windows only)

On Windows, the project uses the Visual Studio Windows debugger (`cppvsdbg`) to speed up the debugging process. `cppvsdbg` is provided by the **C/C++** extension from Microsoft.

From VSCode, go to Extensions (Ctrl-Shift-X), search for `C/C++`, select the one published by **Microsoft** and click `install`.

For more information: [C/C++ extension on the VSCode Marketplace](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools).

{: .note }
> You do not need Visual Studio itself, only the extension. The extension ships its own copy of the debugger engine.
>
> The reason we use `cppvsdbg` on Windows instead of CodeLLDB is to speed up debugging. On my PC, creating the Vulkan instance while debugging takes around 2.5 s using CodeLLDB and only around 260 ms with cppvsdbg. cppvsdbg also has the `symbolOptions.moduleFilter` feature, which lets us tell the debugger to skip symbols for `VkLayer_*.dll` (the 117 MB PDB in the Vulkan SDK), which cuts another 100 ms when creating the Vulkan instance. See [VSCode Project Setup](./vscode_setup.md) for the full rationale.
>
> On Linux there is no PDB, but LLDB still parses the validation layer's DWARF debug info eagerly. CodeLLDB's `symbols.load-on-demand` setting (already wired up in `launch.json`) keeps it lazy, so the C/C++ extension is not needed there.


# Slang VSCode Extension
I suggest you install the `Slang` extension for VSCode to have color highlighting and errors when editing shaders (.slang files).

Search for 'Slang' in the Extensions panel in VSCode and click install.

For more information: [the Slang VSCode extension on GitHub](https://github.com/shader-slang/slang-vscode-extension).


# clang-format
clang-format is required for auto formatting with the Slang VSCode Extension. 

### Linux

- Debian / Ubuntu:
  ```
  sudo apt install clang-format
  ```
- Fedora / RHEL:
  ```
  sudo dnf install clang-format
  ```
- Arch:
  ```
  sudo pacman -S clang-format
  ```

### macOS

```
brew install clang-format
```

### Windows

- Navigate to <https://llvm.org/builds/>
- Click on 'Windows installer (64-bit)' in the 'Windows snapshot builds' section to download the installer
- Execute the downloaded .exe to install LLVM which includes clang-format
  - IMPORTANT: Select **Add LLVM to the system PATH** (for all users or for current user does not matter)


## Test clang-format installation

In a terminal:
```
clang-format --version
```

You should see something like:
```
clang-format version ....
```


# Testing your installation

Open the folder `src/01_test_setup` using VSCode or your editor of choice and build and start the project (F5 by default in VSCode).

If all goes right, you should see in the terminal something like:

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


{: .note }
> The first time you press `F5` in a step folder, VSCode may prompt you to install the debugger extension required for your OS (C/C++ on Windows, CodeLLDB on Linux). Click `Install` and reload VSCode when asked. Subsequent runs start the debugger immediately.
