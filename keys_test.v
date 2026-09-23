module main

import ui2

// keys_test_app builds a headless viewer showing an 800x600 image so key
// shortcuts take effect.
fn keys_test_app() &ViewerApp {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(1000, 800)
	app.core.set_image_loaded('sample.png', 800, 600)
	return app
}

fn test_r_rotates_clockwise() {
	mut app := keys_test_app()

	app.handle_key_event(ui2.KeyEvent{
		code: .r
	})
	assert app.core.viewport.rotation == 90
}

fn test_shift_r_rotates_counter_clockwise() {
	mut app := keys_test_app()

	app.handle_key_event(ui2.KeyEvent{
		code:  .r
		shift: true
	})
	assert app.core.viewport.rotation == 270
}

fn test_shift_r_undoes_r() {
	mut app := keys_test_app()

	app.handle_key_event(ui2.KeyEvent{
		code: .r
	})
	app.handle_key_event(ui2.KeyEvent{
		code:  .r
		shift: true
	})
	assert app.core.viewport.rotation == 0
}
