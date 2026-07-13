

# Build command
Always build in "bin/debug" folder.
Always build with -strict-style.
Always build with -vet to check unused variables.

exemple:
```
odin build . -debug -vet -strict-style -out:bin/debug/03_vulkan_initialization
```
