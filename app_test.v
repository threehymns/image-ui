module main

import os
import math
import time
import ui2

fn test_app_initialization_and_load() {
	mut app := new_app()
	assert !app.has_image
	assert app.canvas_w == 0

	app.set_canvas_size(1000, 800)
	assert app.canvas_w == 1000
	assert app.canvas_h == 800

	app.set_image_loaded('/path/to/test.png', 1920, 1080)
	assert app.has_image
	assert app.img_width == 1920
	assert app.img_height == 1080
	assert app.viewport_init

	// Should be fitted to window: scale = 1000 / 1920 = 0.520833
	expected_scale := f32(1000.0) / f32(1920.0)
	assert math.abs(app.viewport.scale - expected_scale) < 0.001
	assert app.filter_mode == .linear
}

fn test_app_actions_zoom_and_filter() {
	mut app := new_app()
	app.set_canvas_size(1000, 1000)
	app.set_image_loaded('sample.png', 1000, 1000)
	assert app.viewport.scale == 1.0

	// Zoom in above 2.0 -> nearest-neighbor filter
	app.zoom_at(500, 500, 2.5)
	assert app.viewport.scale == 2.5
	assert app.filter_mode == .nearest

	// Zoom out below 1.0 -> bilinear filter
	app.zoom_at(500, 500, 0.2)
	assert app.viewport.scale == 0.5
	assert app.filter_mode == .linear
}

fn test_app_zoom_at_off_center_preserves_anchor() {
	mut app := new_app()
	app.set_canvas_size(1000, 800)
	app.set_image_loaded('sample.png', 800, 600)
	// Image 800x600 fits inside 1000x800 canvas at 1:1, centered at (100, 100)
	assert app.viewport.x == 100.0
	assert app.viewport.y == 100.0

	// Cursor at (300, 250) (off center)
	cursor_x := f32(300.0)
	cursor_y := f32(250.0)

	ix0, iy0 := screen_to_image(cursor_x, cursor_y, app.viewport, 800, 600)

	// Zoom in by factor 1.2
	app.zoom_at(cursor_x, cursor_y, 1.2)

	// Image point directly under cursor must remain invariant
	ix1, iy1 := screen_to_image(cursor_x, cursor_y, app.viewport, 800, 600)
	assert math.abs(ix1 - ix0) < 0.01
	assert math.abs(iy1 - iy0) < 0.01

	// Viewport must NOT have been forced to center (1000 - 960)/2 = 20
	// Position is 300 - (300 - 100) * 1.2 = 60
	assert math.abs(app.viewport.x - 60.0) < 0.01
}

fn test_app_actions_rotation_and_flip() {
	mut app := new_app()
	app.set_canvas_size(1000, 800)
	app.set_image_loaded('sample.png', 800, 600)

	// Rotate CW
	app.rotate_cw()
	assert app.viewport.rotation == 90
	assert app.viewport.width == 600.0
	assert app.viewport.height == 800.0

	// Rotate CCW returns to 0
	app.rotate_ccw()
	assert app.viewport.rotation == 0
	assert app.viewport.width == 800.0
	assert app.viewport.height == 600.0

	// Flip H and V
	assert !app.viewport.flip_h
	assert !app.viewport.flip_v
	app.flip_h()
	assert app.viewport.flip_h
	app.flip_v()
	assert app.viewport.flip_v
}

fn test_transparency_background_follows_displayed_resource_during_pending_request() {
	mut app := new_app()
	app.set_image_loaded('opaque.png', 10, 10)
	app.image_resource = ui2.ready_image_resource('opaque', 'opaque.png', ui2.ImageResourceInput{
		width:    1
		height:   1
		channels: 4
		pixels:   []u8{len: 4, init: 255}
	}, .proven_opaque)
	app.displayed_resource = app.image_resource
	app.image_resource = ui2.loading_image_resource('pending-opaque', 'next.png')
	assert !app.transparency_background_visible()

	app.set_image_loaded('alpha.png', 10, 10)
	app.image_resource = ui2.ready_image_resource('alpha', 'alpha.png', ui2.ImageResourceInput{
		width:    1
		height:   1
		channels: 4
		pixels:   []u8{len: 4, init: 255}
	}, .has_alpha)
	app.displayed_resource = app.image_resource
	app.image_resource = ui2.loading_image_resource('pending-alpha', 'next.png')
	assert app.transparency_background_visible()
}

fn test_transparency_background_keeps_pattern_for_unknown_without_opaque_display() {
	mut app := new_app()
	assert app.transparency_background_visible()
	app.image_resource = ui2.ready_image_resource('unknown', 'unknown.png', ui2.ImageResourceInput{
		width:    1
		height:   1
		channels: 4
		pixels:   []u8{len: 4, init: 255}
	}, .unknown)
	assert app.transparency_background_visible()
}

fn test_app_toggle_fit_and_actual() {
	mut app := new_app()
	app.set_canvas_size(960, 540)
	app.set_image_loaded('sample.png', 1920, 1080)
	// Initial fit is 0.5
	assert math.abs(app.viewport.scale - 0.5) < 0.001

	// Toggle switches to 1.0
	app.toggle_zoom_fit_actual()
	assert math.abs(app.viewport.scale - 1.0) < 0.001

	// Toggle switches back to 0.5
	app.toggle_zoom_fit_actual()
	assert math.abs(app.viewport.scale - 0.5) < 0.001
}

fn test_app_pan_constrained() {
	mut app := new_app()
	app.set_canvas_size(800, 600)
	app.set_image_loaded('sample.png', 1600, 1200)
	app.zoom_actual() // 1600x1200 at 1:1 on 800x600

	// Current centered pos: x = -400, y = -300
	assert app.viewport.x == -400.0
	assert app.viewport.y == -300.0

	// Pan right by 100px: x becomes -300
	app.pan(100.0, 0.0)
	assert app.viewport.x == -300.0

	// Attempt to pan excessively right (off screen): clamped to 0
	app.pan(1000.0, 0.0)
	assert app.viewport.x == 0.0

	// Attempt to pan excessively left (off screen): clamped to -800
	app.pan(-2000.0, 0.0)
	assert app.viewport.x == -800.0
}

fn test_app_playlist_navigation() {
	mut app := new_app()
	app.open_path('/photos/img5.png')
	assert app.target_path == '/photos/img5.png'
	assert app.playlist == ['/photos/img5.png']
	assert app.active_index == 0

	// Integrate Neighborhood batch
	batch := SiblingBatch{
		items:           ['/photos/img1.png', '/photos/img2.png', '/photos/img5.png',
			'/photos/img10.png', '/photos/img20.png']
		is_neighborhood: true
		is_last:         true
		generation:      app.scan_generation
	}
	app.integrate_batch(batch)
	assert app.playlist.len == 5
	assert app.active_index == 2
	assert app.active_sibling_path() == '/photos/img5.png'

	// Next sibling (+1)
	assert app.next_sibling() == true
	assert app.active_index == 3
	assert app.active_sibling_path() == '/photos/img10.png'

	// Prev sibling (-1)
	assert app.prev_sibling() == true
	assert app.active_index == 2
	assert app.active_sibling_path() == '/photos/img5.png'

	// Secondary navigation step (+10): clamps to end
	assert app.next_secondary_step() == true
	assert app.active_index == 4
	assert app.active_sibling_path() == '/photos/img20.png'

	// Step past end should return false (no change)
	assert app.next_sibling() == false
	assert app.active_index == 4

	// Secondary navigation step (-10): clamps to beginning
	assert app.prev_secondary_step() == true
	assert app.active_index == 0
	assert app.active_sibling_path() == '/photos/img1.png'

	// Step before start should return false (no change)
	assert app.prev_sibling() == false
	assert app.active_index == 0
}

fn test_app_progressive_batch_integration_preserves_active() {
	mut app := new_app()
	app.open_path('/photos/pic50.png')

	// First batch: Neighborhood of 50..60
	batch1 := SiblingBatch{
		items:           ['/photos/pic50.png', '/photos/pic51.png', '/photos/pic52.png']
		is_neighborhood: true
		is_last:         false
		generation:      app.scan_generation
	}
	app.integrate_batch(batch1)
	assert app.active_index == 0
	assert app.active_sibling_path() == '/photos/pic50.png'
	assert app.is_scanning == true
	assert app.scan_complete == false

	// Navigate to pic51
	assert app.next_sibling() == true
	assert app.active_sibling_path() == '/photos/pic51.png'
	assert app.active_index == 1

	// Progressive batch arrives with preceding items (pic10..pic49)
	batch2 := SiblingBatch{
		items:           ['/photos/pic10.png', '/photos/pic20.png']
		is_neighborhood: false
		is_last:         true
		generation:      app.scan_generation
	}
	app.integrate_batch(batch2)

	// Playlist should now be naturally sorted: [pic10, pic20, pic50, pic51, pic52]
	assert app.playlist == ['/photos/pic10.png', '/photos/pic20.png', '/photos/pic50.png',
		'/photos/pic51.png', '/photos/pic52.png']
	// Active image must still be pic51, now at index 3
	assert app.active_sibling_path() == '/photos/pic51.png'
	assert app.active_index == 3
	assert app.is_scanning == false
	assert app.scan_complete == true
}

fn test_app_ignores_stale_scanner_generation() {
	mut app := new_app()
	app.open_path('/photos/current.png')
	app.invalidate_scan()
	generation := app.scan_generation
	app.begin_scan(generation)
	before := app.playlist.clone()
	old_ch := chan SiblingBatch{cap: 1}
	spawn scan_directory_siblings_with_generation('/path/that/does/not/exist', '', generation - 1, old_ch)
	stale := next_app_scan_batch(old_ch)
	assert stale.generation == generation - 1

	app.integrate_batch(stale)

	assert app.playlist == before
	assert app.target_path == '/photos/current.png'
	assert app.is_scanning == true
	assert app.scan_complete == false
}

fn test_app_open_directory_defers_selection() {
	tmp_dir := os.join_path(os.temp_dir(), 'test_app_dir_${time.ticks()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	os.write_file(os.join_path(tmp_dir, 'img2.png'), 'data') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'img1.png'), 'data') or { panic(err) }

	mut app := new_app()
	app.open_path(tmp_dir)

	assert app.target_path == tmp_dir
	assert app.playlist.len == 0
	assert app.active_index == 0
	assert app.has_first_content == false
	assert app.is_scanning == true
	assert app.scan_complete == false
}

fn next_app_scan_batch(ch chan SiblingBatch) SiblingBatch {
	select {
		batch := <-ch {
			return batch
		}
		5 * time.second {
			panic('scanner batch timeout')
		}
	}
	return SiblingBatch{}
}

fn test_app_directory_first_content_before_completion() {
	tmp_dir := os.join_path(os.temp_dir(), 'test_app_first_${time.ticks()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	for name in ['img10.png', 'img2.png', 'img1.png', 'img3.png'] {
		os.write_file(os.join_path(tmp_dir, name), 'data') or { panic(err) }
	}

	mut app := new_app()
	app.open_path(tmp_dir)
	ch := chan SiblingBatch{cap: 4}
	spawn scan_directory_siblings_with_generation(tmp_dir, '', app.scan_generation, ch)

	first := next_app_scan_batch(ch)
	assert first.is_first_content == true
	assert first.is_neighborhood == false
	assert first.is_last == false
	assert first.items == [os.join_path(tmp_dir, 'img1.png')]
	app.integrate_batch(first)
	assert app.has_first_content == true
	assert app.is_scanning == true
	assert app.scan_complete == false
	assert app.target_path == os.join_path(tmp_dir, 'img1.png')

	mut current := first
	for !current.is_last {
		current = next_app_scan_batch(ch)
		app.integrate_batch(current)
	}
	assert app.scan_complete == true
	assert app.playlist.len == 4
	assert app.playlist[0] == os.join_path(tmp_dir, 'img1.png')
	assert app.playlist[3] == os.join_path(tmp_dir, 'img10.png')
}

fn test_app_first_image_centered_after_canvas_resize() {
	// First frame preload initializes the viewport with fallback bounds
	// before the real window size is known; the pristine viewport must be
	// recomputed so the first image opens centered.
	mut app := new_app()
	app.set_image_loaded('/photos/img1.png', 400, 300)
	app.set_canvas_size(800, 600)
	app.set_canvas_size(1024, 768)
	assert math.abs(app.viewport.x - 312.0) < 0.01
	assert math.abs(app.viewport.y - 234.0) < 0.01
	assert app.viewport.scale == 1.0
}

fn test_app_first_large_image_fit_after_canvas_resize() {
	mut app := new_app()
	app.set_image_loaded('/photos/big.png', 1920, 1080)
	app.set_canvas_size(800, 600)
	app.set_canvas_size(1024, 768)
	expected_scale := f32(1024.0) / f32(1920.0)
	assert math.abs(app.viewport.scale - expected_scale) < 0.001
	assert math.abs(app.viewport.x - 0.0) < 0.01
	assert math.abs(app.viewport.y - 96.0) < 0.01
}

fn test_app_user_zoom_preserved_on_canvas_resize() {
	mut app := new_app()
	app.set_image_loaded('/photos/img1.png', 400, 300)
	app.set_canvas_size(800, 600)
	app.set_canvas_size(1024, 768)
	app.zoom_in()
	zoomed_scale := app.viewport.scale
	app.set_canvas_size(1280, 800)
	assert app.viewport.scale == zoomed_scale
}
