module main

import os
import stbi

pub struct LoadedImageMetadata {
pub:
	width             int
	height            int
	source_bytes      int
	original_channels int
}

pub fn load_image_metadata(path string) !LoadedImageMetadata {
	bytes := os.read_bytes(path) or { return error('Unable to read image: ${err.msg()}') }
	image := stbi.load_from_memory(bytes.data, bytes.len, stbi.LoadParams{}) or {
		return error('Unable to load image: ${err.msg()}')
	}
	metadata := LoadedImageMetadata{
		width:             image.width
		height:            image.height
		source_bytes:      bytes.len
		original_channels: image.original_nr_channels
	}
	image.free()
	return metadata
}
