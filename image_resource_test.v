module main

import os
import time
import ui2

__global image_resource_test_decode_count = 0
__global image_resource_test_decoder_error = false

fn image_resource_test_pixels() []u8 {
	mut pixels := []u8{len: 8}
	pixels[0] = 255
	pixels[1] = 0
	pixels[2] = 0
	pixels[3] = 0
	pixels[4] = 0
	pixels[5] = 255
	pixels[6] = 0
	pixels[7] = 128
	return pixels
}

fn image_resource_test_decoder(_path string) !DecodedImage {
	image_resource_test_decode_count++
	if image_resource_test_decoder_error {
		return error('test decode failure')
	}
	return DecodedImage{
		width:    2
		height:   1
		channels: 4
		pixels:   image_resource_test_pixels()
		opacity:  .has_alpha
	}
}

fn image_resource_test_path() string {
	return os.join_path(os.temp_dir(), 'image-resource-test-${time.ticks()}.png')
}

fn image_resource_test_bmp() []u8 {
	mut data := []u8{len: 58}
	data[0] = `B`
	data[1] = `M`
	data[2] = 58
	data[10] = 54
	data[14] = 40
	data[18] = 1
	data[22] = 1
	data[26] = 1
	data[28] = 24
	data[34] = 4
	data[54] = 255
	data[55] = 0
	data[56] = 0
	return data
}

fn test_image_resource_loader_uses_one_decode_for_metadata_and_pixels() {
	image_resource_test_decode_count = 0
	mut loader := new_image_resource_loader(image_resource_test_decoder)
	resource := loader.load('sample.png')
	assert image_resource_test_decode_count == 1
	assert resource.state == .ready
	assert resource.opacity == .has_alpha
	assert resource.source == 'sample.png'
	assert resource.width() == 2
	assert resource.height() == 1
	assert resource.channels() == 4
	assert resource.decoded_pixels() == image_resource_test_pixels()
}

fn test_default_stbi_decoder_returns_rgba_metadata_and_opacity() {
	path := image_resource_test_path()
	os.write_bytes(path, image_resource_test_bmp()) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	decoded := decode_stbi_image(path) or { panic(err) }
	assert decoded.width == 1
	assert decoded.height == 1
	assert decoded.channels == 4
	assert decoded.pixels.len == 4
	assert decoded.opacity == .proven_opaque
	assert decoded.pixels[3] == 255
}

fn test_image_resource_opacity_classification_is_explicit() {
	assert classify_image_opacity(3, []u8{len: 3, init: 1}) == .proven_opaque
	assert classify_image_opacity(4, []u8{len: 8, init: 255}) == .proven_opaque
	mut alpha_pixels := []u8{len: 4}
	alpha_pixels[3] = 254
	assert classify_image_opacity(4, alpha_pixels) == .has_alpha
	assert classify_image_opacity(2, []u8{len: 2, init: 1}) == .unknown
	assert classify_image_opacity(4, []u8{}) == .unknown
}

fn test_app_loading_resource_keeps_previous_metadata_until_commit() {
	mut app := new_app()
	app.set_canvas_size(100, 100)
	app.set_image_loaded('ready.png', 10, 20)
	app.set_image_resource(ui2.loading_image_resource('loading-id', 'next.png'))
	assert app.image_resource.state == .loading
	assert app.image_resource.opacity == .unknown
	assert app.has_image
	assert app.img_width == 10
	assert app.img_height == 20
}

fn test_viewer_resource_path_decodes_once_and_reuses_renderer_resource() {
	image_resource_test_decode_count = 0
	image_resource_test_decoder_error = false
	path := image_resource_test_path()
	os.write_file(path, 'fixture') or { panic(err) }
	defer {
		os.rm(path) or {}
	}

	mut app := &ViewerApp{}
	app.core = new_app()
	app.image_loader = new_image_resource_loader(image_resource_test_decoder)
	app.scanned_dir = os.real_path(os.dir(path))
	app.window_ready = false
	app.load_image(path)
	app.window_ready = true
	assert image_resource_test_decode_count == 1
	assert app.core.has_image
	assert app.core.image_resource.state == .ready
	assert app.core.image_resource.opacity == .has_alpha
	assert app.core.img_width == 2
	assert app.core.img_height == 1
	app.core.set_canvas_size(800, 600)
	app.core.rotate_cw()
	app.core.flip_h()
	app.core.filter_mode = .nearest

	first := app.build_screen()
	second := app.build_screen()
	assert image_resource_test_decode_count == 1
	first_canvas := first.children[first.children.len - 1]
	second_canvas := second.children[second.children.len - 1]
	first_image := first_canvas.children[0]
	assert first_image.rotation == 90
	assert first_image.flip_h
	assert first_image.pixelated
	assert first_canvas.children[0].image_resource.id == app.core.image_resource.id
	assert second_canvas.children[0].image_resource.id == app.core.image_resource.id
	assert first_canvas.children[0].image_path == path
}

fn test_viewer_resource_error_updates_state_without_metadata() {
	image_resource_test_decode_count = 0
	image_resource_test_decoder_error = true
	path := image_resource_test_path()
	os.write_file(path, 'fixture') or { panic(err) }
	defer {
		os.rm(path) or {}
	}

	mut app := &ViewerApp{}
	app.core = new_app()
	app.image_loader = new_image_resource_loader(image_resource_test_decoder)
	app.load_image(path)
	assert image_resource_test_decode_count == 1
	assert app.core.image_resource.state == .error
	assert app.core.image_resource.error == 'test decode failure'
	assert !app.core.has_image
	assert app.core.img_width == 0
	assert app.core.img_height == 0
	assert app.core.error_msg == 'test decode failure'
}

fn test_legacy_image_path_api_remains_available() {
	legacy := ui2.transformed_image('legacy', 'legacy.png', ui2.rect(0, 0, 20, 10), 0, false)
	assert legacy.image_path == 'legacy.png'
	assert legacy.image_resource.id == ''

	resource := ui2.ready_image_resource('resource-id', 'sample.png', ui2.ImageResourceInput{
		width:    1
		height:   1
		channels: 4
		pixels:   []u8{len: 4, init: 255}
	}, .proven_opaque)
	element := ui2.transformed_image_resource('resource', resource, ui2.rect(0, 0, 20,
		10), 90, false)
	assert element.image_path == 'sample.png'
	assert element.image_resource.id == 'resource-id'
	assert element.rotation == 90
}
