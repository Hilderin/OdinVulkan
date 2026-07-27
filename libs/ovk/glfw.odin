package ovk

import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

init_glfw :: proc() -> Error {

	if !glfw.Init() {
		return General_Error{"Failed to initialize GLFW"}
	}

	return nil
}

Window :: struct {
	instance:      ^Instance,
	window_handle: glfw.WindowHandle,
	surface:       vk.SurfaceKHR,
}

Create_Window_Args :: struct {
	instance:  ^Instance,
	title:     string,
	width:     u32,
	height:    u32,
	resizable: bool,
}

// Creates a Window using glfw.
create_window :: proc(args: Create_Window_Args) -> (window: Window, err: Error) {
	// No API to prevent OpenGL initialization.
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	// Resizable
	glfw.WindowHint(glfw.RESIZABLE, args.resizable ? 1 : 0)

	// Create the window
	ctitle := strings.clone_to_cstring(args.title)
	defer delete(ctitle)

	window_handle := glfw.CreateWindow(i32(args.width), i32(args.height), ctitle, nil, nil)
	if window_handle == nil {
		err = General_Error{"Unable to create window."}
		return
	}


	// Create the surface
	surface := create_surface(args.instance.vk_instance, window_handle) or_return

	window = {args.instance, window_handle, surface}
	return
}


// Creates a surface for a window
@(private = "file")
create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> (surface: vk.SurfaceKHR, err: Error) {

	check(glfw.CreateWindowSurface(instance, window, nil, &surface), "Failed to create surface!") or_return

	return
}


// Destroy the glfw window
destroy_window :: proc(window: ^Window) {
	if window == nil {
		return
	}

	if window.surface != 0 && window.instance != nil {
		vk.DestroySurfaceKHR(window.instance.vk_instance, window.surface, nil)
	}

	if window.window_handle != nil {
		glfw.DestroyWindow(window.window_handle)
	}
}

// Destroy (terminate) glfw
destroy_glfw :: proc() {
	glfw.Terminate()
}
