# Prerequisites

You will need:
- Odin language
- VSCode and plugins
- Vendor libs




# Install Odin

Follow instructions: https://odin-lang.org/docs/install/

At the end you should be able to execute:
```
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
Follow insttructions: https://code.visualstudio.com/download

At the end you should be able to open VSCode from your start menu or via the `code` command.


## Install Odin Language Extension
This extension will provide a Language Server (LSP) which allows VSCode to validate your odin code, have code documentation and code formatting.

From VSCode, go to Extensions which should be available from the side bar (Default shortcut is Ctrl-Shift-X).
Search for `Odin Language`. Be sure tou select the Odin language extension published by Daniel Gavin and click `install`.

For more instructions: https://github.com/DanielGavin/ols

The first time you start a project with a .odin file, the `ols.json` file should be created at the root of your project. This file contains configuration for the Odin Language Server. The list of the available settings are defined here: https://github.com/DanielGavin/ols?tab=readme-ov-file#configuration. This file is already present for each project in this repository.


### WARNING:
The first time you will open a `.odin`file the extension will ask via a notification to install the lastest version, you need to click `Yes`. Otherwise the extension will not install. 


## VSCode tasks.json
The `tasks.json` file contains tasks available to VSCode. You can execute them via the Command Palette (Ctrl-Shift-P or F1) and search for "Tasks: Run Task". But usually, you don't start task manually, you use the "Run and Debug" panel which starts the build and debug defined in the `launch.json`.
So usually, the `tasks.json` file defines the commands to build the project and the `launch.json` define the commands to start and debug the project.

Note: The tasks.json and launch.json files have to be in the `.vscode` folder at the root of the project. These files are already present for each project in this repository.


## Vulkan SDK

Follow instructions: 
- Windows: https://vulkan.lunarg.com/doc/sdk/latest/windows/getting_started.html
- Linux: https://vulkan.lunarg.com/doc/sdk/latest/linux/getting_started.html
- Mac: https://vulkan.lunarg.com/doc/sdk/latest/mac/getting_started.html


## GLFW
sudo apt install libglfw3-dev



## Testing your installation





Note: The first time you will start debugging.



## Troubleshooting


odin build .

/usr/bin/ld: cannot find -lglfw: No such file or directory
clang: error: linker command failed with exit code 1 (use -v to see invocation)

sudo apt install libglfw3-dev
