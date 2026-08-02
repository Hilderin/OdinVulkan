// FPS counter and rolling FPS / frame time graph, drawn with ImGui and ImPlot.
//
// This is the heart of step 39. Every frame we read ImGui's smoothed framerate
// (a rolling average over 60 frames), keep a rolling history of the last
// FPS_HISTORY_CAPACITY samples and render a small performance window: current
// FPS, stats over the visible window and a scrolling plot.
//
// The code lives in its own file next to main.odin, in the same package, so
// the main loop only calls fps_counter_init, fps_history_update and
// fps_counter_render. It is not part of ovk: the framework stays a Vulkan
// wrapper, and this is pure application logic.
package main

import im "../../libs/imgui"
import implot "../../libs/implot"

// How many (time, fps) samples the ring buffer keeps. At 60 fps that is more
// than a minute of history, plenty for a 60 second window.
FPS_HISTORY_CAPACITY :: 4096

// The time window shown by the plot when the app starts, in seconds.
DEFAULT_WINDOW_SECONDS :: 10.0

// Plot labels, kept as cstring so they can be passed straight to ImPlot.
FPS_PLOT_TITLE :: cstring("FPS")
FRAME_TIME_PLOT_TITLE :: cstring("Frame time (ms)")
FPS_Y_FORMAT :: cstring("%.0f")
FRAME_TIME_Y_FORMAT :: cstring("%.2f")

// Rolling history of the frame rate. Samples are (time, value) pairs where
// time is the elapsed time in seconds since the app started and value is the
// smoothed FPS. The buffer is a ring: when full, the oldest sample is
// overwritten by the newest one.
Fps_History :: struct {
	samples:         [FPS_HISTORY_CAPACITY]implot.Point, // the ring buffer
	head:            int, // next slot to write
	total:           int, // samples pushed since the start
	window_seconds:  f32, // visible window length, seconds
	show_frame_time: bool, // plot frame time instead of FPS
	current_fps:     f64, // smoothed FPS of the last frame
	visible_count:   int, // samples plotted this frame
}

// Initialize the history. Called once before the render loop starts.
fps_counter_init :: proc(h: ^Fps_History) {
	h.window_seconds = DEFAULT_WINDOW_SECONDS
	h.show_frame_time = false
}

// Append a sample to the ring buffer, overwriting the oldest one when full.
fps_history_push :: proc(h: ^Fps_History, time_seconds, value: f64) {
	h.samples[h.head] = implot.Point {
		x = time_seconds,
		y = value,
	}
	h.head = (h.head + 1) % FPS_HISTORY_CAPACITY
	h.total += 1
}

// Call once per frame. Reads ImGui's smoothed framerate (rolling average over
// 60 frames) and pushes it into the history. The raw glfw.GetTime() delta is
// too noisy at high frame rates to plot cleanly.
fps_history_update :: proc(h: ^Fps_History, now: f64) -> f64 {
	io := im.GetIO()
	fps := f64(io.Framerate)
	h.current_fps = fps
	fps_history_push(h, now, fps)
	return fps
}

// Walk the samples that fall inside the visible window and fill avg, min, max.
// Returns the number of samples in the window, which is what ImPlot plots.
// When show_frame_time is on, stats are computed on frame times (1000 / fps)
// instead of FPS, so the numbers always match the graph.
fps_history_stats :: proc(h: ^Fps_History, now: f64) -> (avg: f64, min_value: f64, max_value: f64, count: int) {
	limit := now - f64(h.window_seconds)
	sum := 0.0
	lo := 0.0
	hi := 0.0

	for i in 0 ..< FPS_HISTORY_CAPACITY {
		if i >= h.total {
			break
		}
		// Index of the i-th newest sample.
		idx := (h.head - 1 - i + FPS_HISTORY_CAPACITY) % FPS_HISTORY_CAPACITY
		sample := h.samples[idx]
		if sample.x < limit {
			break
		}

		value := sample.y if !h.show_frame_time else 1000.0 / sample.y
		count += 1
		sum += value
		if count == 1 {
			lo = value
			hi = value
		} else {
			lo = min(lo, value)
			hi = max(hi, value)
		}
	}

	if count > 0 {
		avg = sum / f64(count)
		min_value = lo
		max_value = hi
	}

	return
}

// ImPlot Getter used by PlotLineG: maps the linear plot index to the ring
// buffer, starting at the oldest visible sample. The frame time transform is
// applied here too so the graph and the stats agree.
fps_plot_getter :: proc(idx: i32, user_data: rawptr) -> implot.Point {
	h := (^Fps_History)(user_data)
	ring_index := (h.head - h.visible_count + int(idx) + FPS_HISTORY_CAPACITY) % FPS_HISTORY_CAPACITY
	point := h.samples[ring_index]
	if h.show_frame_time {
		point.y = 1000.0 / point.y
	}
	return point
}

// Draw the performance window: controls, current FPS, stats over the visible
// window and the scrolling plot. Called between imgui_new_frame and im.Render.
fps_counter_render :: proc(h: ^Fps_History, now: f64) {
	im.SetNextWindowPos(im.Vec2{10, 10}, .FirstUseEver)
	im.SetNextWindowSize(im.Vec2{430, 320}, .FirstUseEver)

	if !im.Begin("FPS counter") {
		im.End()
		return
	}

	im.SliderFloat("Window (s)", &h.window_seconds, 2.0, 30.0, "%.0f")
	im.Checkbox("Show frame time", &h.show_frame_time)

	im.Separator()

	// Stats over the visible window.
	avg, min_value, max_value: f64
	avg, min_value, max_value, h.visible_count = fps_history_stats(h, now)

	if h.show_frame_time {
		im.Text("Current: %.2f ms", 1000.0 / h.current_fps)
		im.Text("Avg: %.2f ms   Min: %.2f ms   Max: %.2f ms", avg, min_value, max_value)
	} else {
		im.Text("Current: %.0f FPS", h.current_fps)
		im.Text("Avg: %.0f FPS   Min: %.0f FPS   Max: %.0f FPS", avg, min_value, max_value)
	}

	im.Separator()

	title := FPS_PLOT_TITLE if !h.show_frame_time else FRAME_TIME_PLOT_TITLE
	y_format := FPS_Y_FORMAT if !h.show_frame_time else FRAME_TIME_Y_FORMAT

	if implot.BeginPlot(title, im.Vec2{-1, -1}, {.NoLegend}) {
		implot.SetupAxisFormat(.X1, "%.0f")
		implot.SetupAxisFormat(.Y1, y_format)
		implot.SetupAxisLimits(.X1, now - f64(h.window_seconds), now, .Always)
		if max_value > 0 {
			implot.SetupAxisLimits(.Y1, 0, max_value * 1.1, .Always)
		}
		if h.visible_count > 0 {
			implot.PlotLineG(title, fps_plot_getter, rawptr(h), i32(h.visible_count))
		}
		implot.EndPlot()
	}

	im.End()
}
