package main

import "core:math"
import la "core:math/linalg"

// Container for the camera
Camera :: struct {
	position: vec3,
	yaw:      f32,
	pitch:    f32,
}

// Rotate the camera to look at a target point.
camera_look_at :: proc(camera: ^Camera, target: vec3) {
	direction := la.normalize(target - camera.position)
	camera.yaw = math.atan2(direction.z, direction.x)
	camera.pitch = math.asin(direction.y)
}

camera_rotate :: proc(camera: ^Camera, yaw_delta, pitch_delta: f32) {
	camera.yaw += yaw_delta
	camera.pitch += pitch_delta

	limit := math.to_radians_f32(89.0)
	camera.pitch = math.clamp(camera.pitch, -limit, limit)
}

// Returns the view matrix of the camera.
get_camera_view_matrix :: proc(camera: ^Camera) -> mat4 {
	forward := get_camera_forward_vector(camera)
	return la.matrix4_look_at(camera.position, camera.position + forward, vec3{0.0, 1.0, 0.0})
}

// Returns the forward vector "look at" of the camera.
get_camera_forward_vector :: proc(camera: ^Camera) -> vec3 {
	cos_pitch := math.cos(camera.pitch)
	return vec3{math.cos(camera.yaw) * cos_pitch, math.sin(camera.pitch), math.sin(camera.yaw) * cos_pitch}
}

// Returns the camera right vector on the horizontal plane.
get_camera_right_vector :: proc(camera: ^Camera) -> vec3 {
	return la.normalize(la.cross(get_camera_forward_vector(camera), vec3{0.0, 1.0, 0.0}))
}

// Returns the camera up vector after applying pitch.
get_camera_up_vector :: proc(camera: ^Camera) -> vec3 {
	return la.normalize(la.cross(get_camera_right_vector(camera), get_camera_forward_vector(camera)))
}
