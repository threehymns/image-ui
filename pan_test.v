module main

import ui2

// pan_test_app builds a headless viewer with a 1600x1200 image on a
// 1000x800 canvas at actual size, so the viewport (-300, -200) has room to
// pan in every direction.
fn pan_test_app() &ViewerApp {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(1000, 800)
	app.core.set_image_loaded('sample.png', 1600, 1200)
	app.core.zoom_actual()
	return app
}

fn test_build_screen_canvas_receives_image_area_drags() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(1000, 800)
	app.core.set_image_loaded('sample.png', 1600, 1200)
	// Pretend the window loop already ran once so build_screen does not try
	// to (re)load the image from disk headlessly.
	app.window_ready = true

	root := app.build_screen()
	assert root.kind == .screen
	mut canvas := ui2.Element{}
	for layer in root.children {
		if layer.id == 'canvas_bg' {
			canvas = layer
		}
	}
	assert canvas.id == 'canvas_bg'
	assert canvas.draggable

	mut found_image := false
	for child in canvas.children {
		if child.id == 'viewport_image' {
			assert !child.clickable
			assert !child.draggable
			found_image = true
		}
	}
	assert found_image
	img := canvas.children[0]
	assert img.id == 'viewport_image'
	// A clickable-only image would own the hit target on top and swallow
	// drag gestures (ui2 emits pointer:drag solely for draggable targets),
	// so it must stay non-interactive and let gestures fall through.
	assert !img.clickable
	assert !img.draggable
}

fn test_pointer_drag_pans_viewport() {
	mut app := pan_test_app()
	assert app.core.viewport.x == -300.0
	assert app.core.viewport.y == -200.0

	app.handle_event('pointer:down:canvas_bg:300.0:250.0')
	assert app.is_dragging

	app.handle_event('pointer:drag:canvas_bg:320.0:260.0')
	assert app.core.viewport.x == -280.0
	assert app.core.viewport.y == -190.0

	app.handle_event('pointer:up:canvas_bg:320.0:260.0')
	assert !app.is_dragging
	// A drag that moved is a pan, not a click: zoom must not toggle.
	assert app.core.viewport.scale == 1.0
}

fn test_pointer_drag_without_press_starts_gracefully() {
	mut app := pan_test_app()

	// ui2 may deliver a drag without a preceding down after a rebuild moves
	// the view; the first drag only anchors, the second one pans.
	app.handle_event('pointer:drag:canvas_bg:300.0:250.0')
	assert app.core.viewport.x == -300.0
	app.handle_event('pointer:drag:canvas_bg:320.0:260.0')
	assert app.core.viewport.x == -280.0
}
