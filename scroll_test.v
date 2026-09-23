module main

import math

// scroll_test_app builds a headless viewer with an 800x600 image on a
// 1000x800 canvas. The image fits at 1:1 centered at (100, 100).
fn scroll_test_app() &ViewerApp {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(1000, 800)
	app.core.set_image_loaded('sample.png', 800, 600)
	return app
}

fn test_handle_scroll_zooms_in_anchored_at_cursor() {
	mut app := scroll_test_app()
	assert app.core.viewport.scale == 1.0

	cursor_x := 300.0
	cursor_y := 250.0
	ix0, iy0 := screen_to_image(f32(cursor_x), f32(cursor_y), app.core.viewport, 800, 600)

	app.handle_scroll(cursor_x, cursor_y, 1.0)

	// One discrete wheel notch must match the legacy single-step factor.
	assert math.abs(app.core.viewport.scale - 1.15) < 0.0001
	// The image point under the cursor must remain invariant.
	ix1, iy1 := screen_to_image(f32(cursor_x), f32(cursor_y), app.core.viewport, 800, 600)
	assert math.abs(ix1 - ix0) < 0.01
	assert math.abs(iy1 - iy0) < 0.01
}

fn test_handle_scroll_zooms_out_on_negative_delta() {
	mut app := scroll_test_app()

	app.handle_scroll(300, 250, -1.0)

	assert math.abs(app.core.viewport.scale - f32(1.0 / 1.15)) < 0.0001
}

fn test_handle_scroll_fractional_delta_scales_smoothly() {
	mut app := scroll_test_app()

	// High-resolution trackpads report fractional deltas; the response must
	// be proportional so a half-notch zooms by half a step.
	app.handle_scroll(500, 400, 0.5)

	expected := f32(math.pow(1.15, 0.5))
	assert math.abs(app.core.viewport.scale - expected) < 0.0001
}

fn test_handle_scroll_ignores_zero_delta_and_missing_image() {
	mut app := scroll_test_app()
	app.handle_scroll(300, 250, 0.0)
	assert app.core.viewport.scale == 1.0

	mut empty := &ViewerApp{}
	empty.core = new_app()
	empty.handle_scroll(300, 250, 1.0)
	assert !empty.core.has_image
	assert empty.core.viewport.scale == 0.0
}

fn test_handle_event_routes_scroll_wire_format() {
	mut app := scroll_test_app()

	app.handle_event('scroll:300:250:1.0')
	assert math.abs(app.core.viewport.scale - 1.15) < 0.0001

	app.handle_event('scroll:300:250:-1.0')
	assert math.abs(app.core.viewport.scale - 1.0) < 0.01
}

fn test_handle_event_ignores_malformed_scroll() {
	mut app := scroll_test_app()

	app.handle_event('scroll:oops')
	app.handle_event('scroll:1:2')
	app.handle_event('scroll:')
	app.handle_event('')
	assert app.core.viewport.scale == 1.0
}
