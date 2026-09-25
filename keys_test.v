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

fn test_t_toggles_checkerboard() {
	mut app := keys_test_app()
	assert app.core.show_checkerboard == true

	app.handle_key_event(ui2.KeyEvent{
		code: .t
	})
	assert app.core.show_checkerboard == false

	app.handle_key_event(ui2.KeyEvent{
		code: .t
	})
	assert app.core.show_checkerboard == true
}

fn test_t_toggle_reflects_in_build_screen() {
	mut app := keys_test_app()
	app.window_ready = true

	mut screen := app.build_screen()
	assert screen.children[0].id == 'transparency_background'
	assert screen.children[screen.children.len - 1].id == 'canvas_bg'

	app.handle_key_event(ui2.KeyEvent{
		code: .t
	})
	screen = app.build_screen()
	assert screen.children.len == 1
	assert screen.children[0].id == 'canvas_bg'
}
