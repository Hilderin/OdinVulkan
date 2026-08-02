package ovk

import implot "../implot"

// State kept by ovk for the ImPlot integration. The rest of ImPlot's state
// lives in its own global context, created by init_implot.
ImPlot :: struct {
	ctx: ^implot.Context,
}

// Create the ImPlot context. ImPlot renders through the ImGui draw list, so
// unlike init_imgui there is no platform or renderer backend to set up: the
// only requirement is an existing ImGui context.
// Call this after init_imgui and before the main loop.
init_implot :: proc() -> (state: ImPlot, err: Error) {
	state.ctx = implot.CreateContext()
	if state.ctx == nil {
		err = General_Error{"Failed to create the ImPlot context!"}
	}
	return
}

// Destroy the ImPlot context. Call this when the device is done with its last
// frame and before destroy_imgui.
destroy_implot :: proc(state: ^ImPlot) {
	if state == nil {
		return
	}
	if state.ctx != nil {
		implot.DestroyContext(state.ctx)
		state.ctx = nil
	}
}
