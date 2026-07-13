package main

import "core:fmt"
import "core:os"

import "vendor:glfw"

// Manage the escape key exit.
running: bool = true

main :: proc() {
	fmt.println("My first window with GLFW")

	// Initializing GLFW
	if (!glfw.Init()) {
		fmt.eprintln("Failed to initialize GLFW")
		os.exit(1)
	}


	// Creates an empty window
	window := glfw.CreateWindow(512, 512, "My first window", nil, nil)

	if window == nil {
		fmt.eprintln("Unable to create window")
		os.exit(1)
	}
	defer glfw.DestroyWindow(window)

	// Called when glfw keystate changes
	key_callback :: proc "c" (window: glfw.WindowHandle, key, scancode, action, mods: i32) {
		// Exit program on escape pressed
		if key == glfw.KEY_ESCAPE {
			running = false
		}
	}

	// This function sets the key callback of the specified window, which is called when a key is pressed, repeated or released.
	glfw.SetKeyCallback(window, key_callback)

	for (!glfw.WindowShouldClose(window) && running) {
		// Process waiting events in queue
		glfw.PollEvents()
	}

}
