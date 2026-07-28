package ovk

import "core:math"

// Create a perspective matrix for vulkan
matrix4_perspective_vulkan :: proc(fovy, aspect, near, far: f32) -> (m: mat4) {
	tan_half_fovy := math.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect * tan_half_fovy)
	m[1, 1] = -1 / (tan_half_fovy)
	m[2, 2] = -far / (far - near)
	m[3, 2] = -1
	m[2, 3] = -(far * near) / (far - near)

	return
}
