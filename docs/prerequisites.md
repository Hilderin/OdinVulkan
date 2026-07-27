---
title: Prerequisites
nav_order: 2
---

# Prerequisites

You will need:
- Odin language
- VSCode and the Odin Language Extension
- Vulkan SDK
- GLFW
- The Slang extension (highly recommended for editing shaders)
- `clang-format` if you want Slang autoformatting on save




# Install Odin

Follow the instructions on the [Odin install page](https://odin-lang.org/docs/install/).

At the end you should be able to execute:
```bash
odin version
```

Output exemple:
```
odin version dev-2026-07-nightly:819fdc7
```

# Setup VSCode
I will use VSCode because it's the IDE I commonly use but feel free to use any IDE you prefer.
All the projects in the repository are setuped for VSCode.
Simply open the root folder of a project and start it (F5).

You will need:
- VSCode
- Odin Language Extension
- A tasks.json and a launch.json file in .vscode folder for each project.


## Install VSCode
Follow the instructions on the [VSCode download page](https://code.visualstudio.com/download).

At the end you should be able to open VSCode from your start menu or via the `code` command.


## Install Odin Language Extension
This extension will provide a Language Server (LSP) which allows VSCode to validate your odin code, have code documentation and code formatting.

From VSCode, go to Extensions which should be available from the side bar (Default shortcut is Ctrl-Shift-X).
Search for `Odin Language`. Be sure tou select the Odin language extension published by Daniel Gavin and click `install`.

For more instructions: [the ols repository on GitHub](https://github.com/DanielGavin/ols).

The first time you start a project with a .odin file, the `ols.json` file should be created at the root of your project. This file contains configuration for the Odin Language Server. The list of the available settings are defined in the [ols configuration section](https://github.com/DanielGavin/ols?tab=readme-ov-file#configuration). This file is already present for each project in this repository.


{: .warning }
> The first time you will open a `.odin` file, the extension will ask via a notification to install the latest version. You need to click `Yes`. Otherwise the extension will not install. 


## VSCode tasks.json
The `tasks.json` file contains tasks available to VSCode. You can execute them via the Command Palette (Ctrl-Shift-P or F1) and search for "Tasks: Run Task". But usually, you don't start task manually, you use the "Run and Debug" panel which starts the build and debug defined in the `launch.json`.
So usually, the `tasks.json` file defines the commands to build the project and the `launch.json` define the commands to start and debug the project.

Note: The tasks.json and launch.json files have to be in the `.vscode` folder at the root of the project. These files are already present for each project in this repository.


## Vulkan SDK

Follow instructions: 
- Windows: [Vulkan SDK - Windows getting started](https://vulkan.lunarg.com/doc/sdk/latest/windows/getting_started.html)
- Linux: [Vulkan SDK - Linux getting started](https://vulkan.lunarg.com/doc/sdk/latest/linux/getting_started.html)
- Mac: [Vulkan SDK - Mac getting started](https://vulkan.lunarg.com/doc/sdk/latest/mac/getting_started.html)


## GLFW

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


## Slang extension

I suggest you install the `Slang` extension for VSCode to have color highlighting and errors when editing shaders (.slang files).

Search for 'Slang' in the Extensions panel in VSCode and click install.


For more information: [the Slang VSCode extension on GitHub](https://github.com/shader-slang/slang-vscode-extension).

If you want autoformatting, you will need `clang-format` installed:

### Linux:
```
sudo apt install clang-format
```

### Windows:
- Navigate to <https://llvm.org/builds/>
- Click on 'Windows installer (64-bit)' in the 'Windows snapshot builds' section to download the installer
- Execute the downloaded .exe to install LLVM which includes clang-format
  - IMPORTANT: Select Add LLM to the system PATH (for all users or for current user does not matter)


### Test clang-format installation

In a terminal:
```
clang-format --version
```

You should se something like:
```
clang-format version ....
```

**TO COMPLETE FOR MAC, NON DEBIAN LINUX**


## Testing your installation

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


{: .warning }
> The first time you start debugging in VSCode, there's a delay of a couple of seconds before the debugger attaches, for some reason. Subsequent runs are fast.
