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
	// Previous key callback and user pointer. Registered callbacks are chained
	// instead of replaced, so several components can listen to the keys at once.
	prev_key_callback:        Key_Callback,
	prev_key_user_pointer:    rawptr,
	// True once the GLFW key trampoline is installed, so a later registration
	// does not overwrite callbacks installed by other libraries after us.
	key_callback_installed:   bool,
	// The GLFW callback that was installed before the trampoline (if any), so
	// the trampoline can chain to it. Stored once, at first registration.
	prev_glfw_key_callback:   glfw.KeyProc,
	framebuffer_callback:     Frame_Buffer_Size_Callback,
	// Previous framebuffer callback and user pointer. Registered callbacks are
	// chained instead of replaced, like the key callbacks above.
	prev_framebuffer_callback:        Frame_Buffer_Size_Callback,
	prev_framebuffer_user_pointer:    rawptr,
	framebuffer_callback_installed:   bool,
	prev_glfw_framebuffer_callback:   glfw.FramebufferSizeProc,
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
// If a callback is already registered, it is chained instead of replaced, the
// same way the ImGui GLFW backend chains its callbacks. The callbacks run in
// registration order, oldest first.
set_key_callback :: proc(window: ^Window, user_pointer: rawptr, callback: Key_Callback) {
	window.prev_key_callback = window.key_callback
	window.prev_key_user_pointer = window.key_user_pointer
	window.key_user_pointer = user_pointer
	window.key_callback = callback
	glfw.SetWindowUserPointer(window.window_handle, rawptr(window))

	if !window.key_callback_installed {
		// Save the GLFW callback that was installed before us (e.g. ImGui's) so
		// the trampoline can chain to it. No recursion risk: a callback
		// installed before us never chains back to our trampoline.
		window.prev_glfw_key_callback = glfw.SetKeyCallback(window.window_handle, key_callback_thunk)
		window.key_callback_installed = true
	}
}

// Register a framebuffer resize callback on the window.
// The `user_pointer` is forwarded to `callback` on every invocation, so the
// application can reach its own state (typically a pointer to an App struct)
// without relying on any file-level global.
// If a callback is already registered, it is chained instead of replaced, the
// same way set_key_callback does. The callbacks run in registration order,
// oldest first.
set_framebuffer_size_callback :: proc(window: ^Window, user_pointer: rawptr, callback: Frame_Buffer_Size_Callback) {
	window.prev_framebuffer_callback = window.framebuffer_callback
	window.prev_framebuffer_user_pointer = window.framebuffer_user_pointer
	window.framebuffer_user_pointer = user_pointer
	window.framebuffer_callback = callback
	glfw.SetWindowUserPointer(window.window_handle, rawptr(window))

	if !window.framebuffer_callback_installed {
		// Save the GLFW callback that was installed before us (e.g. ImGui's) so
		// the trampoline can chain to it. No recursion risk: a callback
		// installed before us never chains back to our trampoline.
		window.prev_glfw_framebuffer_callback = glfw.SetFramebufferSizeCallback(window.window_handle, framebuffer_size_callback_thunk)
		window.framebuffer_callback_installed = true
	}
}

// GLFW hands us a C function pointer, so the trampoline has to use the "c"
// calling convention. It just recovers the ovk Window from GLFW's user pointer
// and forwards the call to the Odin procs registered by the application, then
// to the GLFW callback that was installed before us (if any).
// The oldest callback runs first, matching the order in which they were
// registered.
@(private = "file")
key_callback_thunk :: proc "c" (window_handle: glfw.WindowHandle, key, scancode, action, mods: i32) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	if window != nil {
		if window.prev_key_callback != nil {
			window.prev_key_callback(window, window.prev_key_user_pointer, key, scancode, action, mods)
		}
		if window.key_callback != nil {
			window.key_callback(window, window.key_user_pointer, key, scancode, action, mods)
		}
		if window.prev_glfw_key_callback != nil {
			window.prev_glfw_key_callback(window_handle, key, scancode, action, mods)
		}
	}
}

@(private = "file")
framebuffer_size_callback_thunk :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	context = runtime.default_context()
	window := cast(^Window)glfw.GetWindowUserPointer(window_handle)
	if window != nil {
		if window.prev_framebuffer_callback != nil {
			window.prev_framebuffer_callback(window, window.prev_framebuffer_user_pointer, width, height)
		}
		if window.framebuffer_callback != nil {
			window.framebuffer_callback(window, window.framebuffer_user_pointer, width, height)
		}
		if window.prev_glfw_framebuffer_callback != nil {
			window.prev_glfw_framebuffer_callback(window_handle, width, height)
		}
	}
}


// Creates a surface for a window
@(private = "file")
create_surface :: proc(instance: vk.Instance, window: glfw.WindowHandle) -> (surface: vk.SurfaceKHR, err: Error) {

	check(glfw.CreateWindowSurface(instance, window, nil, &surface), "Failed to create surface!") or_return

	return
}
