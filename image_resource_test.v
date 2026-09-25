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

fn image_resource_test_ready(path string, id string) ui2.ImageResource {
	return image_resource_from_decoded(id, path, DecodedImage{
		width:    2
		height:   1
		channels: 4
		pixels:   image_resource_test_pixels()
		opacity:  .has_alpha
	})
}

fn image_resource_test_path() string {
	return os.join_path(os.temp_dir(), 'image-resource-test-${time.ticks()}.png')
}

fn image_resource_test_siblings(root string, count int) []string {
	mut paths := []string{}
	for index in 0 .. count {
		path := os.join_path(root, 'sibling-${index:03d}.png')
		os.write_file(path, 'fixture-${index}') or { panic(err) }
		paths << path
	}
	return paths
}

fn image_resource_test_resident_viewer(paths []string, active_index int) &ViewerApp {
	mut app := &ViewerApp{
		core:           new_app()
		image_pipeline: new_manual_image_pipeline()
	}
	app.core.playlist = paths.clone()
	app.core.active_index = active_index
	app.core.set_canvas_size(100, 100)
	app.core.set_image_loaded(paths[active_index], 1, 1)
	app.image_pipeline.set_resident(app.core.displayed_image_resource())
	for path in paths {
		signature := sibling_file_signature(path)
		assert app.image_pipeline.cache.put(path, signature, image_resource_test_ready(path, 'resident-${path}'), 4, 4)
	}
	app.sync_sibling_cache_retention()
	return app
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
	assert image_resource_renderer_bytes(resource) == 8
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
	assert decoded.renderer_bytes == decoded.pixels.len
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
	app.image_pipeline = new_manual_image_pipeline()
	app.scanned_dir = os.real_path(os.dir(path))
	app.window_ready = false
	app.load_image(path)
	assert image_resource_test_decode_count == 0
	request := app.image_pipeline.current_request()
	assert request.path == path
	assert app.image_pipeline.complete_active(image_resource_test_ready(path, 'resource-id'))
	app.poll_image_pipeline()
	app.window_ready = true
	assert app.image_pipeline.metrics.accepted == 1
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
	assert image_resource_test_decode_count == 0
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
	app.image_pipeline = new_manual_image_pipeline()
	app.load_image(path)
	request := app.image_pipeline.current_request()
	assert image_resource_test_decode_count == 0
	assert app.image_pipeline.fail_active(request.generation, path, 'test decode failure')
	app.poll_image_pipeline()
	assert app.core.image_resource.state == .error
	assert app.core.image_resource.error == 'test decode failure'
	assert !app.core.has_image
	assert app.core.img_width == 0
	assert app.core.img_height == 0
	assert app.core.error_msg == 'test decode failure'
}

fn test_app_rejects_stale_image_commit() {
	mut app := new_app()
	app.set_image_loaded('a.png', 10, 20)
	first := app.request_image('b.png', 'test')
	latest := app.request_image('c.png', 'test')
	assert !app.commit_image_request(first, image_resource_test_ready(first.path, 'stale-id'))
	assert app.displayed_image_resource().source == 'a.png'
	assert app.has_image
	assert app.pending_image_request.generation == latest.generation
	assert app.commit_image_request(latest, image_resource_test_ready(latest.path, 'latest-id'))
	assert app.displayed_image_resource().source == 'c.png'
}

fn test_sibling_key_keeps_previous_and_does_not_decode_in_handler() {
	image_resource_test_decode_count = 0
	mut app := &ViewerApp{
		core:           new_app()
		image_loader:   new_image_resource_loader(image_resource_test_decoder)
		image_pipeline: new_manual_image_pipeline()
	}
	app.core.set_canvas_size(100, 100)
	app.core.set_image_loaded('a.png', 10, 20)
	app.core.playlist = ['a.png', 'b.png', 'c.png']
	app.core.active_index = 0
	app.core.zoom_actual()
	app.core.pan(3, 4)
	viewport := app.core.viewport
	app.image_pipeline.set_resident(app.core.displayed_image_resource())

	app.handle_key_event(ui2.KeyEvent{ code: .right })

	assert image_resource_test_decode_count == 0
	assert app.core.has_image
	assert app.core.displayed_image_resource().source == 'a.png'
	assert app.core.image_resource.state == .loading
	assert app.core.pending_image_request.path == 'b.png'
	app.handle_key_event(ui2.KeyEvent{ code: .left })
	assert app.core.target_path == 'a.png'
	assert app.core.pending_image_request.path == 'a.png'
	assert app.image_pipeline.queued_count() == 1
	screen := app.build_screen_at_size(100, 100)
	canvas := screen.children[screen.children.len - 1]
	assert canvas.id == 'canvas_bg'
	assert canvas.children[0].image_path == 'a.png'
	assert app.core.viewport.x == viewport.x
	assert app.core.viewport.y == viewport.y
	assert app.core.viewport.scale == viewport.scale
}

fn test_pipeline_worker_decodes_off_coordinator() {
	image_resource_test_decode_count = 0
	image_resource_test_decoder_error = false
	mut pipeline := new_image_pipeline(image_resource_test_decoder)
	request := pipeline.request('worker.png', 'worker')
	mut worker_result := ImagePipelineResult{}
	select {
		result := <-pipeline.result_ch {
			worker_result = result
		}
		5 * time.second {
			panic('image pipeline worker timeout')
		}
	}
	assert image_resource_test_decode_count == 1
	assert worker_result.request.generation == request.generation
	assert worker_result.resource.state == .ready
	pipeline.result_ch <- worker_result
	results := pipeline.poll()
	assert results.len == 1
	assert results[0].resource.source == request.path
}

fn test_pipeline_rejects_stale_completion_and_keeps_latest_request() {
	mut pipeline := new_manual_image_pipeline()
	first := pipeline.request('a.png', 'test')
	latest := pipeline.request('b.png', 'test')
	assert pipeline.queued_count() == 1
	assert pipeline.complete(first.generation, first.path, image_resource_test_ready(first.path, 'a-id'))
	mut results := pipeline.poll()
	assert results.len == 0
	assert pipeline.metrics.rejected == 1
	assert pipeline.active_request.path == latest.path
	assert pipeline.complete(latest.generation, latest.path, image_resource_test_ready(latest.path, 'b-id'))
	results = pipeline.poll()
	assert results.len == 1
	assert results[0].request.generation == latest.generation
	assert results[0].resource.source == latest.path
}

fn test_pipeline_coalesces_rapid_input_to_one_queued_request() {
	mut pipeline := new_manual_image_pipeline()
	first := pipeline.request('first.png', 'test')
	for index in 0 .. 100 {
		latest := pipeline.request('sibling-${index}.png', 'test')
		assert latest.generation == first.generation + index + 1
	}
	assert pipeline.queued_count() == 1
	assert pipeline.pending_count() == 2
	assert pipeline.metrics.max_pending <= 2
	assert pipeline.metrics.skipped == 99
	assert pipeline.metrics.coalesced == 99
	assert pipeline.current_request().generation == 101
}

fn test_resident_right_key_repeat_displays_every_sibling_in_order() {
	root := os.join_path(os.temp_dir(), 'image-ui-right-repeat-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	paths := image_resource_test_siblings(root, 6)
	mut app := image_resource_test_resident_viewer(paths, 0)
	for index in 1 .. paths.len {
		app.handle_key_event(ui2.KeyEvent{ code: .right })
		_ = app.build_screen_at_size(100, 100)
		assert app.core.displayed_image_resource().source == paths[index]
		assert app.core.active_index == index
		assert app.image_pipeline.metrics.requested == index
		assert app.image_pipeline.metrics.displayed == index
		assert app.image_pipeline.metrics.skipped == 0
		assert app.image_pipeline.metrics.coalesced == 0
	}
}

fn test_resident_left_key_repeat_displays_every_sibling_in_order() {
	root := os.join_path(os.temp_dir(), 'image-ui-left-repeat-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	paths := image_resource_test_siblings(root, 6)
	mut app := image_resource_test_resident_viewer(paths, paths.len - 1)
	for index in paths.len - 2 .. -1 {
		app.handle_key_event(ui2.KeyEvent{ code: .left })
		_ = app.build_screen_at_size(100, 100)
		assert app.core.displayed_image_resource().source == paths[index]
		assert app.core.active_index == index
		assert app.image_pipeline.metrics.requested == paths.len - 1 - index
		assert app.image_pipeline.metrics.displayed == paths.len - 1 - index
		assert app.image_pipeline.metrics.skipped == 0
		assert app.image_pipeline.metrics.coalesced == 0
	}
}

fn test_key_repeat_faster_than_decode_stays_bounded_and_latest_request_wins() {
	root := os.join_path(os.temp_dir(), 'image-ui-fast-repeat-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	paths := image_resource_test_siblings(root, 102)
	mut app := &ViewerApp{
		core:           new_app()
		image_pipeline: new_manual_image_pipeline()
	}
	app.core.playlist = paths.clone()
	app.core.active_index = 0
	app.core.set_canvas_size(100, 100)
	app.core.set_image_loaded(paths[0], 1, 1)
	app.image_pipeline.set_resident(app.core.displayed_image_resource())

	for index in 1 .. 101 {
		app.handle_key_event(ui2.KeyEvent{ code: .right })
	}

	assert app.image_pipeline.metrics.requested == 100
	assert app.image_pipeline.pending_count() == 2
	assert app.image_pipeline.metrics.max_pending == 2
	assert app.image_pipeline.prefetch_pending_count() <= 3
	assert app.image_pipeline.prefetch_metrics.skipped <= app.image_pipeline.prefetch_metrics.requested
	assert app.image_pipeline.metrics.max_total_pending <= 5
	assert app.core.target_path == paths[100]
	first := app.image_pipeline.active_request
	assert first.path == paths[1]
	assert app.image_pipeline.complete_active(image_resource_test_ready(first.path, 'stale'))
	app.poll_image_pipeline()
	latest := app.image_pipeline.active_request
	assert latest.path == paths[100]
	assert app.image_pipeline.complete_active(image_resource_test_ready(latest.path, 'latest'))
	app.poll_image_pipeline()
	assert app.core.displayed_image_resource().source == paths[100]
	assert app.image_pipeline.metrics.displayed == 1
	assert app.image_pipeline.metrics.skipped == 99
	assert app.image_pipeline.metrics.coalesced == 98
}

fn test_sibling_failure_keeps_navigation_and_recovers() {
	mut app := &ViewerApp{
		core:           new_app()
		image_loader:   new_image_resource_loader(image_resource_test_decoder)
		image_pipeline: new_manual_image_pipeline()
	}
	app.core.set_canvas_size(100, 100)
	app.core.set_image_loaded('a.png', 10, 20)
	app.core.playlist = ['a.png', 'bad.png', 'good.png']
	app.core.active_index = 0
	app.image_pipeline.set_resident(app.core.displayed_image_resource())

	app.handle_key_event(ui2.KeyEvent{ code: .right })
	bad_request := app.image_pipeline.current_request()
	assert app.core.has_image
	assert app.core.displayed_image_resource().source == 'a.png'
	assert app.image_pipeline.fail_active(bad_request.generation, bad_request.path, 'bad sibling')
	app.poll_image_pipeline()
	assert app.core.has_image
	assert app.core.displayed_image_resource().source == 'a.png'
	assert app.core.error_msg == 'bad sibling'
	assert app.core.playlist.len == 3
	screen := app.build_screen_at_size(100, 100)
	assert screen.children[screen.children.len - 1].id == 'error_card'
	canvas := screen.children[screen.children.len - 2]
	assert canvas.id == 'canvas_bg'
	assert canvas.children[0].image_path == 'a.png'

	app.handle_key_event(ui2.KeyEvent{ code: .right })
	assert app.core.target_path == 'good.png'
	assert app.core.has_image
	assert app.core.error_msg == ''
	good_request := app.image_pipeline.current_request()
	assert app.image_pipeline.complete_active(image_resource_test_ready(good_request.path, 'good-id'))
	app.poll_image_pipeline()
	assert app.core.displayed_image_resource().source == 'good.png'
	assert app.core.image_resource.state == .ready
	assert app.core.error_msg == ''
}

fn test_resident_resource_uses_render_path_without_decode() {
	image_resource_test_decode_count = 0
	path := image_resource_test_path()
	os.write_file(path, 'fixture') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	mut app := &ViewerApp{
		core:           new_app()
		image_loader:   new_image_resource_loader(image_resource_test_decoder)
		image_pipeline: new_manual_image_pipeline()
	}
	app.core.set_image_resource(image_resource_test_ready(path, 'resident-resource'))
	app.image_pipeline.set_resident(app.core.displayed_image_resource())
	app.request_image(path, 'resident')
	assert app.core.image_resource.state == .loading
	_ = app.build_screen_at_size(100, 100)
	assert app.core.image_resource.state == .ready
	assert app.core.displayed_image_resource().source == path
	assert app.image_pipeline.metrics.resident_hits == 1
	assert image_resource_test_decode_count == 0
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
