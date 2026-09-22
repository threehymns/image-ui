module main

import math

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
