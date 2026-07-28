package ovk

import "base:runtime"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

init_glfw :: proc() -> Error {

	if !glfw.Init() {
		return General_Error{"Failed to initialize GLFW"}
	}

	return nil
}

// Callback signatures handed to ovk by the application.
// They receive the ovk Window and the user pointer provided at registration
// time, so the application can recover its own state (e.g. an App struct)
// without touching any global.
Key_Callback :: proc(window: ^Window, user_pointer: rawptr, key, scancode, action, mods: i32)

Frame_Buffer_Size_Callback :: proc(window: ^Window, user_pointer: rawptr, width, height: i32)

Window :: struct {
	instance:                 ^Instance,
	window_handle:            glfw.WindowHandle,
	surface:                  vk.SurfaceKHR,
	key_user_pointer:         rawptr,
	framebuffer_user_pointer: rawptr,
	key_callback:             Key_Callback,
	framebuffer_callback:     Frame_Buffer_Size_Callback,
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

	window = {
		instance      = args.instance,
		window_handle = window_handle,
		surface       = surface,
	}
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

// Returns true if the window needs to be closed.
window_should_close :: proc(window: ^Window) -> bool {
	return bool(glfw.WindowShouldClose(window.window_handle))
}

// Returns the window size
get_window_size :: proc(window: ^Window) -> (width: i32, height: i32) {
	width, height = glfw.GetFramebufferSize(window.window_handle)
	return
}

// Execute the glfw PollEvents
poll_events :: proc() {
	glfw.PollEvents()
}

// Execute the glfw WaitEvents
wait_events :: proc() {
	glfw.WaitEvents()
}


// Register a key callback on the window.
// The `user_pointer` is forwarded to `callback` on every invocation, so the
// application can reach its own state (typically a pointer to an App struct)
// without relying on any file-level global.
set_key_callback :: proc(window: ^Window, user_pointer: rawptr, callback: Key_Callback) {
	window.key_user_pointer = user_pointer
	window.key_callback = callback
	glfw.SetWindowUserPointer(window.window_handle, rawptr(window))
	glfw.SetKeyCallback(window.window_handle, key_callback_thunk)
}

// Register a framebuffer resize callback on the window.
set_framebuffer_size_callback :: proc(window: ^Window, user_pointer: rawptr, callback: Frame_Buffer_Size_Callback) {
	window.framebuffer_user_pointer = user_pointer
	window.framebuffer_callback = callback
	glfw.SetWindowUserPointer(window.window_handle, rawptr(window))
	glfw.SetFramebufferSizeCallback(window.window_handle, framebuffer_size_callback_thunk)
}

// GLFW hands us a C function pointer, so the trampoline has to use the "c"
// calling convention. It just recovers the ovk Window from GLFW's user pointer
// and forwards the call to the Odin proc registered by the application.
@(private = "file")
key_callback_thunk :: proc "c" (window_handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	if window != nil && window.key_callback != nil {
		window.key_callback(window, window.key_user_pointer, key, scancode, action, mods)
	}
}

@(private = "file")
framebuffer_size_callback_thunk :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	if window != nil && window.framebuffer_callback != nil {
		window.framebuffer_callback(window, window.framebuffer_user_pointer, width, height)
	}
}


// Creates a surface for a window
@(private = "file")
create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> (surface: vk.SurfaceKHR, err: Error) {

	check(glfw.CreateWindowSurface(instance, window, nil, &surface), "Failed to create surface!") or_return

	return
}
