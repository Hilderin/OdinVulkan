package main

import "core:math"
import la "core:math/linalg"

// A directional light has no position. Its rotation describes the direction
// from which the light comes, in degrees, as yaw and pitch.
Directional_Light :: struct {
	rotation:          vec2,
	intensity:         f32,
	color:             vec3,
	ambient_color:     vec3,
	ambient_strength:  f32,
	specular_strength: f32,
	shininess:         f32,
}

get_directional_light_direction :: proc(light: ^Directional_Light) -> vec3 {
	yaw := math.to_radians_f32(light.rotation.x)
	pitch := math.to_radians_f32(light.rotation.y)
	cos_pitch := math.cos(pitch)

	return la.normalize(vec3 {
		math.cos(yaw) * cos_pitch,
		math.sin(pitch),
		math.sin(yaw) * cos_pitch,
	})
}
