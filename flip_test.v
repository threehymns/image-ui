module main

import ui2

// flip_test_app builds a headless viewer showing an 800x600 image on a
// 1000x800 canvas without touching disk: window_ready skips the load path.
fn flip_test_app() &ViewerApp {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(1000, 800)
	app.core.set_image_loaded('sample.png', 800, 600)
	app.window_ready = true
	return app
}

fn flip_viewer_image(mut app &ViewerApp) ui2.Element {
	root := app.build_screen()
	assert root.kind == .screen
	for layer in root.children {
		if layer.id == 'canvas_bg' {
			for child in layer.children {
				if child.kind == .image && child.id == 'viewport_image' {
					return child
				}
			}
		}
	}
	panic('viewport_image missing')
}

fn test_h_key_mirror_declared_on_image() {
	mut app := flip_test_app()
	assert !flip_viewer_image(mut app).flip_h

	app.core.flip_h()

	img := flip_viewer_image(mut app)
	assert img.flip_h
	assert !img.flip_v
}

fn test_v_key_mirror_declared_on_image() {
	mut app := flip_test_app()

	app.core.flip_v()

	img := flip_viewer_image(mut app)
	assert !img.flip_h
	assert img.flip_v
}

fn test_flips_toggle_off() {
	mut app := flip_test_app()

	app.core.flip_h()
	app.core.flip_h()
	assert !flip_viewer_image(mut app).flip_h
}

fn test_clockwise_rotation_declared_in_clockwise_degrees() {
	mut app := flip_test_app()

	app.core.rotate_cw()
	assert app.core.viewport.rotation == 90

	// ui2's rotation is clockwise degrees; declaring the negated sokol draw
	// angle here would spin the image the wrong way.
	assert flip_viewer_image(mut app).rotation == 90.0
}

fn test_flip_survives_rotation() {
	mut app := flip_test_app()

	app.core.rotate_cw()
	app.core.flip_h()

	img := flip_viewer_image(mut app)
	assert img.rotation == 90.0
	assert img.flip_h
	assert !img.flip_v
}
