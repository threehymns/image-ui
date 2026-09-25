module main

import ui2

// filter_test_app builds a headless viewer showing the image without touching
// disk: window_ready skips the load path in build_screen.
fn filter_test_app(canvas_w int, canvas_h int, img_w int, img_h int) &ViewerApp {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(canvas_w, canvas_h)
	app.core.set_image_loaded('sample.png', img_w, img_h)
	app.window_ready = true
	return app
}

fn viewer_image_element(mut app &ViewerApp) ui2.Element {
	root := app.build_screen()
	assert root.kind == .screen
	assert root.children.len == 1
	assert root.children[0].children.len == 1
	return root.children[0].children[0]
}

fn test_build_screen_marks_image_pixelated_above_200_percent() {
	mut app := filter_test_app(1000, 800, 400, 300)
	assert app.core.viewport.scale == 1.0

	app.core.zoom_at(500, 400, 3.0)
	assert app.core.viewport.scale == 3.0
	assert app.core.filter_mode == .nearest

	assert viewer_image_element(mut app).pixelated
}

fn test_build_screen_keeps_image_smooth_when_fitted() {
	// 1600x1200 fitted on 1000x800 scales to 0.625 (< 100% -> bilinear).
	mut app := filter_test_app(1000, 800, 1600, 1200)
	assert app.core.filter_mode == .linear

	assert !viewer_image_element(mut app).pixelated
}

fn test_build_screen_keeps_image_smooth_between_100_and_200_percent() {
	mut app := filter_test_app(1000, 800, 400, 300)

	app.core.zoom_at(500, 400, 1.5)
	assert app.core.viewport.scale == 1.5
	assert app.core.filter_mode == .linear

	assert !viewer_image_element(mut app).pixelated
}
