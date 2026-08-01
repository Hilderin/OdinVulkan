---
title: Rebuilding the ImGui library
nav_order: 100
---

# Rebuilding the ImGui library

The bindings in `libs/imgui` are not a pure Odin implementation. They wrap the C++ API of dear imgui and link against a static library. That library has to be compiled once, per platform, and dropped next to the bindings. Both versions are committed in the repo - `imgui_windows_x64.lib` and `libimgui_linux_x64.a` - so day to day you never need this page. You need it only when you bump the ImGui version, or when a library goes missing and has to be regenerated.

This page walks through the rebuild for Windows and Linux, with the exact versions the project uses.

## The version pairing

The Odin binding and the C library must be built from the same ImGui version, otherwise the app fails fast at startup. The binding stores the version it was generated for:

```c
VERSION :: "1.92.8"
```

(`libs/imgui/imgui.odin:49`)

`CHECKVERSION` (`libs/imgui/imgui.odin:35`) compares that string against the compiled library's `IMGUI_VERSION`, plus the size of its core structs. If they disagree you get an assert at initialization, not a compile or link error. So when you rebuild the library, rebuild it from the same version the bindings were generated from.

This project uses:

- dear imgui: `v1.92.8-docking`
- dear_bindings: `DearBindings_v0.21_ImGui_v1.92.8-docking`
- GLFW headers: `3.3` (why this exact pin? see the pitfalls at the bottom)

## Prerequisites

- **premake5** - the odin-imgui repository ships one at its root, or install it from [premake.github.io](https://premake.github.io).
- **git** - premake clones the ImGui, dear_bindings, GLFW and Vulkan-Headers sources into `build/deps`.
- **Python 3** with the `venv` and `pip` modules (dear_bindings needs them). On Linux:
  ```
  sudo apt install python3-venv python3-pip
  ```
- **Windows:** MSVC - Visual Studio 2022 or the Build Tools. The build script needs `vcvars64.bat` to be reachable.
- **Linux:** `make` and a C++ compiler (the `build-essential` package).

## Get the odin-imgui repository

The bindings and the build tooling come from [Capati/odin-imgui](https://github.com/Capati/odin-imgui). Clone it once:

```
git clone https://github.com/Capati/odin-imgui
cd odin-imgui
```

The rest of this page assumes you are working from that folder.

## Generate the build files

From the repository root, generate the project files with the pinned versions and the backends the project uses.

On Linux:

```
premake5 --backends=glfw,vulkan --imgui-version=v1.92.8-docking --dear-bindings-version=DearBindings_v0.21_ImGui_v1.92.8-docking --glfw-version=3.3 gmake
```

On Windows:

```
premake5 --backends=glfw,vulkan --imgui-version=v1.92.8-docking --dear-bindings-version=DearBindings_v0.21_ImGui_v1.92.8-docking --glfw-version=3.3 vs2022
```

premake clones the dependencies if needed, runs dear_bindings (the Python step, which generates the `dcimgui` C wrapper in `build/generated`) and writes the build files.

## Build on Windows

Open a Visual Studio developer prompt - so `vcvars64.bat` is on the PATH - go to the `build` folder and run:

```
build.bat
```

The script compiles the ImGui sources and the generated wrapper, then archives them into `imgui_windows_x64.lib` at the repository root.

## Build on Linux

Go to the generated make directory and build with make:

```
cd build/make/linux
make config=release_x86_64
```

The result, `libimgui_linux_x64.a`, lands at the repository root.

## Copy the result

Move the archive into the project, next to the binding:

- Windows: `imgui_windows_x64.lib` -> `libs/imgui/imgui_windows_x64.lib`
- Linux: `libimgui_linux_x64.a` -> `libs/imgui/libimgui_linux_x64.a`

That is where the `foreign import` in `libs/imgui/imgui.odin` looks for it - line 12 on Windows, line 20 on Linux. No other file needs to change, since the committed bindings already match the pinned version.

## Pitfalls

### premake does not re-checkout existing dependencies

premake only clones a repository if its folder under `build/deps/` does not exist yet. Running it again with different version flags on an existing checkout changes nothing. To switch versions, delete `build/deps/imgui`, `build/deps/dear_bindings` and `build/deps/glfw` first (or check the tags out manually inside those folders), then re-run premake.

### GLFW 3.4 headers break the Linux link

premake's default GLFW version is 3.4. With those headers, `imgui_impl_glfw.cpp` calls `glfwGetPlatform()`, a GLFW 3.4-only function. On Linux the Odin program links against the system GLFW, which on Ubuntu 24.04 is 3.3.10, so the link fails with:

```
undefined reference to glfwGetPlatform
```

The Odin binding dodges this because it declares `GetPlatform` with weak linkage on Linux (`vendor/glfw/bindings/bindings.odin:216`), so the app itself links fine and the error only shows up through the static library. Pinning `--glfw-version=3.3` makes the ImGui backend compile against the 3.3 headers, which do not reference the function at all.

### A version mismatch shows up at runtime

If the library and the bindings disagree, the failure is not a link error but an assert during initialization:

```
unsatisfied ensure: DebugCheckVersionAndDataLayout(...)
```

That means the library was built from a different ImGui version than `imgui.odin`. Check the `--imgui-version` you passed to premake against `VERSION` in `libs/imgui/imgui.odin`.

### The generated bindings use spaces, the project wants tabs

The `.odin` binding files generated by dear_bindings indent with spaces, but the project compiles with `-vet-tabs`. The copies committed in `libs/imgui` were converted. If you regenerate the bindings - as opposed to only rebuilding the C library - convert the indentation to tabs before copying them in.
