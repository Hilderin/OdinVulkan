---
title: VSCode Project Setup
nav_order: 2.5
---

# VSCode Project Setup

Every project folder in `src/` contains a `.vscode/` directory with configuration files that handle building and debugging. If you have never touched these files before, this page is for you.

The files work together so that opening any step folder and pressing `F5` just works: it builds the project, starts it under the debugger, and lets you inspect variables, set breakpoints, and step through Vulkan calls.

There are plenty of VSCode-specific resources out there, so this page focuses on the files as they are used in *this* repository. For the official documentation:

- [Tasks in VSCode](https://code.visualstudio.com/docs/editor/tasks)
- [Debugging in VSCode](https://code.visualstudio.com/docs/editor/debugging)
- [Launch.json attributes](https://code.visualstudio.com/docs/cpp/launch-json-reference)



## What is what

### `.vscode/tasks.json`

`tasks.json` defines commands that VSCode can run as part of your workflow: building, cleaning, type-checking.

Open `src/01_test_setup/.vscode/tasks.json` to follow along. It contains five tasks:

1. **Create build directory** (Debug and Release) -- creates the `bin/debug/` and `bin/release/` folders if they don't exist. The build step depends on this task, so the folder is always there before `odin build` tries to write the binary. The command is platform-specific (`mkdir -p` on Linux, `cmd /c if not exist ...` on Windows).

2. **Build - Debug** -- the main build task. It runs:
   ```
   odin build . -debug -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors -show-timings
   ```
   The `-debug` flag includes debug symbols (required for the debugger). All the `-vet*` flags check for common mistakes and enforce style rules. The `-show-timings` flag prints how long each compilation stage takes.

3. **Build - Release** -- same command without `-debug`, for an optimised build.

4. **Check** -- runs `odin check` instead of `odin build`. This parses and type-checks the code without producing a binary. It is faster than a full build and useful for catching errors in CI or when you just want to verify your code.

The build tasks set `"cwd"` to `bin/debug/` (or `bin/release/`). Since `odin build` outputs the binary relative to the working directory, the executable ends up inside the `bin/` folder rather than cluttering the project root.

The actual binary path is determined by `"options": {"cwd": "${workspaceFolder}/bin/debug"}` combined with the fact that odin names the executable after the current directory. The launch configuration then refers to this path to find the binary.



### `.vscode/launch.json`

`launch.json` tells VSCode how to run and debug your program. Open `src/01_test_setup/.vscode/launch.json` to follow along - the file is identical in every step folder.

It has two configurations:

- **Debug** -- builds the debug binary and launches it under the debugger. This is the one you use most of the time: set breakpoints, inspect variables, step through Vulkan calls.
- **Launch-Release** -- builds the optimised release binary and runs it *without* a debugger. Useful when you want to check raw performance or just see the program run without the overhead of the debug session.

#### Debug configuration

The **Debug** configuration has a platform split: it uses `lldb` (CodeLLDB) on Linux and `cppvsdbg` (Microsoft C/C++ debugger) on Windows. The reason for the split is explained further down - it is about avoiding the cost of loading the Vulkan validation layer's debug symbols.

##### Common fields

- `"type": "lldb"` -- the default debugger type, used on Linux. On Windows a `"windows"` block overrides this to `"cppvsdbg"` (see below).
- `"request": "launch"` -- VSCode should start the program.
- `"program": "${workspaceFolder}/bin/debug/${workspaceFolderBasename}"` -- the path to the compiled executable. The binary file name matches the folder name (for example, opening `src/01_test_setup/` produces `01_test_setup.exe` on Windows or `01_test_setup` on Linux).
- `"cwd": "${workspaceFolder}"` -- the working directory is the project folder itself, not the `bin/` output folder. This matters when the code reads files relative to the current directory.
- `"preLaunchTask": "Build - Debug"` -- before launching, VSCode runs the "Build - Debug" task from `tasks.json`. If the build fails, the launch is cancelled.
- `"initCommands"` -- a list of LLDB commands that CodeLLDB runs before the target launches. It is used here for one specific setting (see the next section).

##### `symbols.load-on-demand`: the LLDB lazy-symbol trick

The top-level `"initCommands"` contains a single LLDB command:

```json
"initCommands": [
    "settings set symbols.load-on-demand true"
]
```

By default, when LLDB loads a module (a `.so` on Linux, a `.dll` on Windows), it immediately parses the entire debug info section and builds a full symbol index in memory. For a tiny binary that is fine, but the Vulkan validation layer is not tiny - its debug info is large. Parsing it eagerly on module load adds roughly 2.6 seconds to `vkCreateInstance` on Linux when running under CodeLLDB.

`symbols.load-on-demand true` flips this behaviour: LLDB registers that the module exists but defers parsing its debug info until something actually needs it - a breakpoint being set, a stack frame being resolved, a variable being inspected. In practice, while you are stepping through your own code, LLDB rarely needs to look inside the validation layer's symbols, so the upfront cost disappears.

The trade-off: if you ever break inside the validation layer itself (which you normally don't), LLDB will pay the parsing cost at that point instead of at launch. For this project that is the right trade-off - you want fast launches and you almost never step into the layer's internals.

On Windows, the `"windows"` block overrides `"type"` to `"cppvsdbg"`, which does not understand `initCommands` and silently ignores it. So this setting only takes effect on Linux. On Windows the symbol problem is handled differently (see below).

##### The `windows` block

The `windows` block overrides the top-level `"type"` with `"cppvsdbg"` and adds symbol filtering:

```json
"windows": {
    "type": "cppvsdbg",
    "internalConsoleOptions": "openOnSessionStart",
    "logging": {
        "moduleLoad": false
    },
    "symbolOptions": {
        "searchPaths": [],
        "searchMicrosoftSymbolServer": false,
        "moduleFilter": {
            "mode": "loadAllButExcluded",
            "excludedModules": [
                "VkLayer_*.dll",
            ]
        }
    }
}
```

- `"type": "cppvsdbg"` -- use the Visual Studio Windows debugger. Requires the **Microsoft C/C++ extension** (`ms-vscode.cpptools`).
- `"internalConsoleOptions": "openOnSessionStart"` -- when the debug session starts, VSCode switches focus to the Debug Console, so your `fmt.println` output is visible immediately and not hidden behind the build terminal.
- `"logging.moduleLoad": false` -- suppresses the `Loaded 'C:\Windows\System32\...dll'` lines that `cppvsdbg` otherwise prints to the Debug Console on every DLL load. Without this, the Debug Console fills with dozens of module-load messages before your program's first line of output.
- `"symbolOptions.moduleFilter"` -- in `"loadAllButExcluded"` mode, the debugger loads symbols for every module *except* the ones matching `"excludedModules"`. `"VkLayer_*.dll"` covers the validation layer and every other Khronos layer DLL. Your own binary still gets full symbols, so breakpoints and variable inspection work as usual.
- `"searchMicrosoftSymbolServer": false` -- don't try to download Windows system DLL symbols from Microsoft's symbol server.
- `"searchPaths": []` -- don't look for PDBs anywhere except next to the module itself.

##### Why Windows uses `cppvsdbg` instead of CodeLLDB

When the Vulkan validation layer is enabled (it is, in every step that calls `ovk.create_instance` with `debug = true`), `vkCreateInstance` loads `VkLayer_khronos_validation.dll`. That DLL ships with a 117 MB PDB in the Vulkan SDK. Under the debugger, the debugger tries to locate and parse that PDB on module load, which adds around 2.5 seconds to instance creation alone. Without the debugger, the PDB is never opened and instance creation takes about 150 ms.

CodeLLDB on Windows has no way to say "skip this specific DLL's symbols". The `symbols.load-on-demand` setting helps a bit (2.5 s down to about 1.8 s) but it is still an order of magnitude slower than running without a debugger. `cppvsdbg` (the Microsoft C/C++ debugger) supports `symbolOptions.moduleFilter`, which lets us say "load symbols for everything except `VkLayer_*.dll`". With that filter, instance creation under the debugger drops to about 185 ms - basically the same as running without a debugger at all.

On Linux there is no PDB (the validation layer is a `.so` with DWARF debug info), but LLDB has the same eager-parsing habit. There, `symbols.load-on-demand` is the only tool available and it does the job well enough (2.6 s down to a few hundred milliseconds). `cppdbg` with GDB is even worse (about 3.5 s), which is why we stick with CodeLLDB on Linux.

#### Launch-Release configuration

The **Launch-Release** configuration is the same as Debug but with `"noDebug": true`: it builds and runs the optimised release binary without attaching a debugger. No breakpoints, no stepping, no variable inspection.

It keeps the same platform split and symbol options as Debug:

```json
{
    "name": "Launch-Release",
    "type": "lldb",
    "request": "launch",
    "noDebug": true,
    "program": "${workspaceFolder}/bin/release/${workspaceFolderBasename}",
    "args": [],
    "cwd": "${workspaceFolder}",
    "preLaunchTask": "Build - Release",
    "initCommands": [
        "settings set symbols.load-on-demand true"
    ],
    "windows": {
        "type": "cppvsdbg",
        "internalConsoleOptions": "openOnSessionStart",
        "logging": { "moduleLoad": false },
        "symbolOptions": {
            "searchPaths": [],
            "searchMicrosoftSymbolServer": false,
            "moduleFilter": {
                "mode": "loadAllButExcluded",
                "excludedModules": [ "VkLayer_*.dll" ]
            }
        }
    }
}
```

- `"noDebug": true` -- tells VSCode to launch the program without attaching a debugger. The program runs at full speed.
- The `"windows"` block and `"initCommands"` are kept because even with `noDebug`, the launcher still loads the target process and its modules. Without the symbol filter (Windows) or `load-on-demand` (Linux), the validation layer's debug info would still get parsed on module load, adding the same 2 to 2.6 seconds you see in debug mode. Keeping the filters means Launch-Release is just as fast as running from the terminal.
- `"preLaunchTask": "Build - Release"` -- builds the optimised release binary first.

This is the configuration to use when you want to check raw performance or just see the final result without stepping through code.

#### Extensions you need

- **On Windows**: [C/C++](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools) (for `cppvsdbg`, used by the Debug configuration).
- **On Linux**: [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) (for `lldb`, used by both configurations).
- Installing both is harmless - VSCode picks the right one based on the `"type"` resolved for the current platform.



### `.vscode/settings.json`

Only the later step folders (29, 30, 31) ship a `settings.json`. It contains a small editor tweak, for example hiding the `.code-workspace` file from the explorer:

```json
{
    "files.exclude": {
        "*.code-workspace": true
    }
}
```

You can extend it with anything VSCode supports - default formatter, OLS configuration, excluding the `bin/` folder, etc. See the [VSCode settings documentation](https://code.visualstudio.com/docs/getstarted/settings) for all available options.



## How they work together

When you open a project folder (say `src/01_test_setup/`) and press `F5`:

1. VSCode reads `launch.json` and uses the first configuration by default (**Debug**). You can pick **Launch-Release** from the debug dropdown if you want the release run.
2. VSCode sees `preLaunchTask: "Build - Debug"` (or `"Build - Release"` for the release config).
3. It looks up the task in `tasks.json`.
4. The build task depends on "Create build directory", so that runs first (creates `bin/debug/` or `bin/release/`).
5. The build task runs: `odin build . -debug -vet ...` (or without `-debug` for release). The binary lands in `bin/debug/` (or `bin/release/`).
6. If the build succeeds:
   - **Debug config on Windows**: VSCode uses `cppvsdbg` with `moduleFilter` to skip `VkLayer_*.dll` symbols, so the validation layer loads fast and the Debug Console stays readable.
   - **Debug config on Linux**: VSCode uses `lldb` (CodeLLDB) with `symbols.load-on-demand` to defer symbol parsing, so instance creation stays fast.
   - **Launch-Release config**: VSCode launches the release binary with `noDebug: true` - no debugger attaches, but the symbol filters are still active so the validation layer loads fast. The program runs at full speed.
7. On Windows with the Debug config, the Debug Console gets focus (`internalConsoleOptions`), and your program's `fmt.println` output appears there.

If the build fails, VSCode shows the error in the terminal panel and the program never starts. No mysterious crashes, no missing symbols.

This same pattern repeats in every step folder. The only thing that changes is the binary name (which matches the folder name). This is why opening a new step folder and pressing `F5` always works with no manual configuration.