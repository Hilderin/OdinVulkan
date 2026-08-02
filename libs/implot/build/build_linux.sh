#!/usr/bin/env bash
# Builds the ImPlot static library for Linux (x64).
#
# This script fetches the exact sources the committed libimplot_linux_x64.a
# should be built from, compiles them with the C++ compiler and drops the
# archive next to implot.odin. Run it from libs/implot/build.
#
# Requirements:
#   - git
#   - a C++ compiler (g++ by default, override with CXX=...)
#
# To upgrade ImPlot or ImGui, update the pins at the top and re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
DEPS="$SCRIPT_DIR/deps"

# --- Pins --------------------------------------------------------------------
# ImGui headers, the project uses the same version as libs/imgui.
IMGUI_TAG=v1.92.8-docking
# cimgui.h, the C header cimplot includes. Find the commit whose message
# matches your ImGui version in https://github.com/cimgui/cimgui/commits.
CIMGUI_COMMIT=650a4270695803565a2f40f49bcc01726a25c702
# cimplot commit; its submodule pins the matching implot revision.
CIMPLOT_COMMIT=8213880
# ------------------------------------------------------------------------------

mkdir -p "$DEPS"

# ImGui headers
if [ ! -f "$DEPS/imgui/imgui.h" ]; then
    echo "Cloning ImGui $IMGUI_TAG..."
    git clone --depth 1 --branch "$IMGUI_TAG" https://github.com/ocornut/imgui.git "$DEPS/imgui"
fi

# cimplot (C API for ImPlot) plus its implot submodule
if [ ! -f "$DEPS/cimplot/cimplot.h" ]; then
    echo "Cloning cimplot $CIMPLOT_COMMIT..."
    git clone https://github.com/cimgui/cimplot.git "$DEPS/cimplot"
    git -C "$DEPS/cimplot" checkout "$CIMPLOT_COMMIT"
    git -C "$DEPS/cimplot" submodule update --init --depth 1
fi

# cimgui.h
if [ ! -f "$DEPS/cimgui.h" ]; then
    echo "Fetching cimgui.h at $CIMGUI_COMMIT..."
    curl -fsSL "https://raw.githubusercontent.com/cimgui/cimgui/$CIMGUI_COMMIT/cimgui.h" -o "$DEPS/cimgui.h"
fi

CXX="${CXX:-g++}"

INCLUDE_DIRS=(
    -I"$DEPS/cimplot"
    -I"$DEPS/cimplot/implot"
    -I"$DEPS"
    -I"$DEPS/imgui"
)

echo "Compiling with $CXX..."
$CXX -std=c++11 -O2 -fPIC -DNDEBUG \
    -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_DISABLE_OBSOLETE_KEYIO \
    "${INCLUDE_DIRS[@]}" \
    -c "$DEPS/cimplot/cimplot.cpp" -o "$SCRIPT_DIR/cimplot.o"
$CXX -std=c++11 -O2 -fPIC -DNDEBUG \
    -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_DISABLE_OBSOLETE_KEYIO \
    "${INCLUDE_DIRS[@]}" \
    -c "$DEPS/cimplot/implot/implot.cpp" -o "$SCRIPT_DIR/implot.o"
$CXX -std=c++11 -O2 -fPIC -DNDEBUG \
    -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_DISABLE_OBSOLETE_KEYIO \
    "${INCLUDE_DIRS[@]}" \
    -c "$DEPS/cimplot/implot/implot_items.cpp" -o "$SCRIPT_DIR/implot_items.o"
$CXX -std=c++11 -O2 -fPIC -DNDEBUG \
    -DIMGUI_DISABLE_OBSOLETE_FUNCTIONS -DIMGUI_DISABLE_OBSOLETE_KEYIO \
    "${INCLUDE_DIRS[@]}" \
    -c "$DEPS/cimplot/implot/implot_demo.cpp" -o "$SCRIPT_DIR/implot_demo.o"

echo "Creating static library..."
ar rcs "$ROOT/libimplot_linux_x64.a" "$SCRIPT_DIR/"*.o
rm -f "$SCRIPT_DIR/"*.o

echo "Done. Library written to $ROOT/libimplot_linux_x64.a"
