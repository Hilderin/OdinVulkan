# libs/implot

Odin bindings for [ImPlot](https://github.com/epezent/implot), the plotting library that sits on top of Dear ImGui.

What's in this folder:

- `implot.odin` - the binding. It wraps the C API of ImPlot ([cimplot](https://github.com/cimgui/cimplot)) and links against a static library, exactly like `libs/imgui` does for Dear ImGui. It is written by hand: the public API only, with the double, float and getter variants of the plot functions.
- `implot_windows_x64.lib` and `libimplot_linux_x64.a` - the prebuilt static libraries, compiled from `cimplot.cpp` plus the implot sources. They are committed so the project compiles out of the box.
- `build/` - the scripts that rebuild the libraries, with the pinned source versions.

See [Rebuilding the ImPlot library](../../docs/implot_build.md) for how to rebuild the libraries on Windows and Linux, and how to upgrade ImPlot.
