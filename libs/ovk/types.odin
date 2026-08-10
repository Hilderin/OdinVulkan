package ovk


// Important aliases for math types
vec2 :: [2]f32
vec3 :: [3]f32
vec4 :: [4]f32
mat4 :: matrix[4, 4]f32


// Vertex attributes
Vertex :: struct {
	pos:      vec3,
	color:    vec3,
	texCoord: vec2,
	normal:   vec3,
}
