package ovk


import "core:bytes"
import img "core:image"
import "core:image/jpeg"
import "core:image/png"

// Avoids 'unused import' error: "core:image/png" or "core:image/jpeg" needs to be imported in order
// to make `img.load` understand png and jpeg format.
_ :: png
_ :: jpeg

// Representation of a Bitmap in memory.
Bitmap :: struct {
	width:     u32,
	height:    u32,
	channels:  u32,
	depth:     u32,
	pixels:    []u8,
	src_image: ^img.Image,
}


Options :: img.Options


// Create a bitmap from a file on the disk.
load_bitmap_from_file :: proc(path: string, options: Options = {}) -> (bitmap: Bitmap, err: Error) {

	src_image, err_load_image := img.load(path, options)
	assert(err_load_image == nil, "Failed to open image file: %q %q.", path, err_load_image) or_return

	bitmap.width = u32(src_image.width)
	bitmap.height = u32(src_image.height)
	bitmap.channels = u32(src_image.channels)
	bitmap.depth = u32(src_image.depth)
	bitmap.pixels = bytes.buffer_to_bytes(&src_image.pixels)
	bitmap.src_image = src_image

	return

}


// Destroy the bitmap
destroy_bitmap :: proc(bitmap: ^Bitmap) {
	if bitmap != nil {
		img.destroy(bitmap.src_image)
	}
}
