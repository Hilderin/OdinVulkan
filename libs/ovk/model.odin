package ovk

import "core:os"
import "core:path/slashpath"

import tinyobj "../tinyobj"

Mesh :: struct {
	vertices: []Vertex,
	indices:  []u32,
}

// Load a mesh from disk
load_mesh :: proc(path: string) -> (mesh: Mesh, err: Error) {

	data, err_read := os.read_entire_file(path, context.allocator)
	assert(err_read == nil, "Failed to read obj file: %v, error: %v", path, err_read) or_return
	defer delete(data)

	current_dir := slashpath.dir(path)
	defer delete(current_dir)
	obj := tinyobj.parse_obj(string(data), current_dir, tinyobj.FLAG_TRIANGULATE)
	assert(obj.success, "Failed to read obj file:", path)
	defer tinyobj.destroy(&obj)

	mesh.vertices = make([]Vertex, len(obj.attrib.vertices) / 3)
	for f_index in 0 ..< len(mesh.vertices) {
		v := Vertex {
			pos   = {obj.attrib.vertices[f_index * 3], obj.attrib.vertices[(f_index * 3) + 1], obj.attrib.vertices[(f_index * 3) + 2]},
			color = {1.0, 1.0, 1.0},
		}
		mesh.vertices[f_index] = v
	}

	indices_list: [dynamic]u32
	for &vertex_index in obj.attrib.faces {
		append(&indices_list, u32(vertex_index.v_idx))

		texCoord := vec2{obj.attrib.texcoords[vertex_index.vt_idx * 2], 1.0 - obj.attrib.texcoords[(vertex_index.vt_idx * 2) + 1]}
		mesh.vertices[vertex_index.v_idx].texCoord = texCoord
	}

	mesh.indices = indices_list[:]
	return
}

// Destroy the mesh
destroy_mesh :: proc(mesh: ^Mesh) {
	delete(mesh.vertices)
	delete(mesh.indices)
}
