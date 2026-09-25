module main

import os
import stbi
import ui2

pub struct DecodedImage {
pub:
	width    int
	height   int
	channels int
	pixels   []u8
	opacity  ui2.ImageOpacity
}

pub type ImageResourceDecoder = fn (string) !DecodedImage

pub struct ImageResourceLoader {
pub mut:
	decoder ImageResourceDecoder = unsafe { nil }
	next_id int
}

pub fn classify_image_opacity(channels int, pixels []u8) ui2.ImageOpacity {
	if channels == 3 && pixels.len >= 3 {
		return .proven_opaque
	}
	if channels != 4 || pixels.len < 4 {
		return .unknown
	}
	for index := 3; index < pixels.len; index += 4 {
		if pixels[index] != 255 {
			return .has_alpha
		}
	}
	return .proven_opaque
}

pub fn decode_stbi_image(path string) !DecodedImage {
	image_bytes := os.read_bytes(path) or {
		return error('Unable to read image: ${err.msg()}')
	}
	mut decoded := stbi.load_from_memory(image_bytes.data, image_bytes.len, stbi.LoadParams{}) or {
		return error('Unable to load image: ${err.msg()}')
	}
	if decoded.width <= 0 || decoded.height <= 0 {
		decoded.free()
		return error('decoded image has invalid dimensions')
	}
	pixel_len := decoded.width * decoded.height * 4
	mut pixels := []u8{len: pixel_len}
	copy(mut pixels, unsafe { decoded.data.vbytes(pixel_len) })
	opacity := classify_image_opacity(decoded.nr_channels, pixels)
	decoded.free()
	return DecodedImage{
		width:    decoded.width
		height:   decoded.height
		channels: 4
		pixels:   pixels
		opacity:  opacity
	}
}

pub fn new_image_resource_loader(decoder ImageResourceDecoder) ImageResourceLoader {
	return ImageResourceLoader{
		decoder: decoder
	}
}

pub fn (mut loader ImageResourceLoader) load(path string) ui2.ImageResource {
	loader.next_id++
	id := 'image-resource-${loader.next_id}'
	if voidptr(loader.decoder) == unsafe { nil } {
		return ui2.error_image_resource(id, path, 'no image decoder configured')
	}
	decoded := loader.decoder(path) or {
		return ui2.error_image_resource(id, path, err.msg())
	}
	if decoded.width <= 0 || decoded.height <= 0 || decoded.channels != 4 {
		return ui2.error_image_resource(id, path, 'decoded image has invalid metadata')
	}
	pixel_len := decoded.width * decoded.height * 4
	if decoded.pixels.len < pixel_len {
		return ui2.error_image_resource(id, path, 'decoded image has incomplete pixels')
	}
	return ui2.ready_image_resource(id, path, ui2.ImageResourceInput{
		width:    decoded.width
		height:   decoded.height
		channels: decoded.channels
		pixels:   decoded.pixels
	}, decoded.opacity)
}
