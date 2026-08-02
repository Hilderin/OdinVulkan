---
title: Rebuilding the ImPlot library
nav_order: 101
---

# Rebuilding the ImPlot library

The bindings in `libs/implot` wrap the C API of ImPlot and link against a static library. Like the ImGui library, that library is compiled once per platform and committed next to the binding - `implot_windows_x64.lib` on Windows and `libimplot_linux_x64.a` on Linux. Day to day you never touch it. You need this page only to bump the ImPlot version, or to regenerate a missing library.

Unlike ImGui, ImPlot's bindings are not generated: `implot.odin` is written by hand, from the cimplot C header. Rebuilding ImPlot is therefore only about the C library. The binding only needs a check on upgrade, to pick up new functions.

## The version pairing

Three versions must agree at build time:

- **ImGui headers** - implot.cpp includes imgui.h and imgui_internal.h, so the library is compiled against the same ImGui version as `libs/imgui`. The project uses `v1.92.8-docking`.
- **cimplot** - the C API of ImPlot. It is generated from implot.h and pinned to a commit in [cimgui/cimplot](https://github.com/cimgui/cimplot). The commit's submodule pins the matching implot revision.
- **cimgui.h** - the C imgui header that cimplot.h includes. It is generated from a specific ImGui version; use the commit whose commit message matches your ImGui version (for example "pull imgui 1.92.8 docking and generate").

The current pins are at the top of `libs/implot/build/build_windows.bat` and `build_linux.sh`.

## Prerequisites

- **git** - the build scripts fetch the sources.
- **Windows:** Visual Studio (or the Build Tools) with the C++ workload. The script locates `vcvars64.bat` through vswhere, or uses it from the PATH if set.
- **Linux:** a C++ compiler (`g++` by default, override with `CXX=...`).

## Build on Windows

From `libs/implot/build`, run:

```
build_windows.bat
```

The script, in order:

1. Clones ImGui at `--depth 1 --branch v1.92.8-docking` into `build/deps/imgui`.
2. Clones cimplot, checks out the pinned commit and initializes the implot submodule.
3. Fetches `cimgui.h` at the pinned commit from the cimgui repository.
4. Finds `vcvars64.bat`, sets up the MSVC environment and compiles `cimplot.cpp`, `implot.cpp`, `implot_items.cpp` and `implot_demo.cpp` with the same flags as the ImGui library (`/MT`, `IMGUI_DISABLE_OBSOLETE_FUNCTIONS`, ...).
5. Archives the objects into `implot_windows_x64.lib` at `libs/implot`.

The fetched sources live in `build/deps`, which is gitignored.

## Build on Linux

From `libs/implot/build`, run:

```
./build_linux.sh
```

It does the same thing with the system C++ compiler and archives the objects into `libimplot_linux_x64.a` with `ar`.

## Upgrading the version

1. Update `IMGUI_TAG` to the ImGui version `libs/imgui` uses (check `VERSION` in `libs/imgui/imgui.odin`).
2. Find the cimgui commit whose message matches that ImGui version (https://github.com/cimgui/cimgui/commits) and update `CIMGUI_COMMIT`.
3. Update `CIMPLOT_COMMIT` to a cimplot release that works with that ImGui version.
4. Re-run the build script for your platform.
5. Update `implot.odin`: add any new public functions, enums or structs that appear in `cimplot.h`, and remove none of the existing ones (ImPlot keeps its API stable across releases, additions are the norm).
6. Commit the new library, `implot.odin` and the updated pins.

Delete `build/deps` if the script complains that an existing checkout is stale - the scripts only fetch a source when its files are missing, they do not update an existing clone.

## Pitfalls

### A version mismatch shows up at runtime

The library and the ImGui headers it was compiled against must match the ImGui the app links. If they disagree, the symptom is usually a crash or garbage layout in ImPlot, not a clean link error. Keep the three pins above in sync with `libs/imgui`.

### The Windows script cannot find MSVC

The script looks for `vcvars64.bat` in the PATH first, then through `vswhere`. If neither works, install the Visual Studio "Desktop development with C++" workload and re-run. The error message names the missing piece.

### Windows-only behavior in the sources

The build scripts compile against the GLFW-free core of ImPlot: no backends, no platform code. What matters for the binding is that the exported C functions come from `cimplot.cpp`, which is compiled identically on both platforms.
