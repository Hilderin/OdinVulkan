---
title: VSCode Project Setup
nav_order: 2.5
---

# VSCode Project Setup

Every project folder in `src/` contains a `.vscode/` directory with three configuration files that handle building, debugging, and editor behavior. If you have never touched these files before, this page is for you.

The three files work together so that opening any step folder and pressing `F5` just works: it builds the project, starts it under the debugger, and lets you inspect variables, set breakpoints, and step through Vulkan calls.

There are plenty of VSCode-specific resources out there, so this page focuses on the files as they are used in *this* repository. For the official documentation:

- [Tasks in VSCode](https://code.visualstudio.com/docs/editor/tasks)
- [Debugging in VSCode](https://code.visualstudio.com/docs/editor/debugging)
- [Launch.json attributes](https://code.visualstudio.com/docs/cpp/launch-json-reference)



## What is what

### `.vscode/tasks.json`

`tasks.json` defines commands that VSCode can run as part of your workflow: building, cleaning, type-checking.

Open `src/01_test_setup/.vscode/tasks.json` to follow along. It contains five tasks:

1. **Create build directory** (Debug and Release) -- creates the `bin/debug/` and `bin/release/` folders if they don't exist. The build step depends on this task, so the folder is always there before `odin build` tries to write the binary.

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

`launch.json` tells VSCode how to run and debug your program. Open `src/01_test_setup/.vscode/launch.json`.

It has a single configuration named **Launch**:

- `"type": "lldb"` -- this means it uses the LLDB debugger.
- `"request": "launch"` -- VSCode should start the program.
- `"program": "${workspaceFolder}/bin/debug/${workspaceFolderBasename}"` -- the path to the compiled executable. The binary file name matches the folder name (for example, opening `src/01_test_setup/` produces `01_test_setup.exe` on Windows or `01_test_setup` on Linux/macOS).
- `"cwd": "${workspaceFolder}"` -- the working directory is the project folder itself, not the `bin/` output folder. This matters when the code reads files relative to the current directory.
- `"preLaunchTask": "Build - Debug"` -- before launching, VSCode runs the "Build - Debug" task from `tasks.json`. If the build fails, the launch is cancelled.

The `"type": "lldb"` requires the **CodeLLDB** extension. VSCode will prompt you to install it when you open a launch configuration that uses it, or you can install it manually from:
- [CodeLLDB on the VSCode Marketplace](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)



### `.vscode/settings.json`

The repository does not ship a `settings.json` yet, but you can create one in any project folder to override editor defaults. This file is useful for:

- Setting the default formatter (for example, forcing OLS formatting for `.odin` files)
- Configuring OLS behaviour (tab width, linting rules, etc.)
- Excluding the `bin/` folder from the file explorer

Example:
```json
{
   "files.exclude": {
      "bin": true
   }
}
```

See the [VSCode settings documentation](https://code.visualstudio.com/docs/getstarted/settings) for all available options.



## How they work together

When you open a project folder (say `src/01_test_setup/`) and press `F5`:

1. VSCode reads `launch.json` and sees `preLaunchTask: "Build - Debug"`.
2. It looks up "Build - Debug" in `tasks.json`.
3. "Build - Debug" depends on "Create build directory - Debug", so that runs first (creates `bin/debug/`).
4. "Build - Debug" runs: `odin build . -debug -vet ...`. The binary lands in `bin/debug/`.
5. If the build succeeds, VSCode launches the binary under LLDB.
6. The debugger attaches, and you can set breakpoints, inspect variables, and step through the code.

If the build fails, VSCode shows the error in the terminal panel and the program never starts. No mysterious crashes, no missing symbols.

This same pattern repeats in every step folder. The only thing that changes is the binary name (which matches the folder name). This is why opening a new step folder and pressing `F5` always works with no manual configuration.
