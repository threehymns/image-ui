module main

import ui2

fn test_compute_checkerboard_cells_zero_or_negative() {
	assert compute_checkerboard_cells(0, 0, 0, 100, 16).len == 0
	assert compute_checkerboard_cells(0, 0, 100, 0, 16).len == 0
	assert compute_checkerboard_cells(0, 0, 100, 100, 0).len == 0
	assert compute_checkerboard_cells(0, 0, -10, 100, 16).len == 0
}

fn test_compute_checkerboard_cells_exact_grid() {
	cells := compute_checkerboard_cells(10, 20, 32, 32, 16)
	assert cells.len == 4
	assert cells[0].x == 10
	assert cells[0].y == 20
	assert cells[0].width == 16
	assert cells[0].height == 16
	assert cells[0].is_alt == false
	assert cells[1].x == 26
	assert cells[1].y == 20
	assert cells[1].width == 16
	assert cells[1].height == 16
	assert cells[1].is_alt == true
	assert cells[2].x == 10
	assert cells[2].y == 36
	assert cells[2].width == 16
	assert cells[2].height == 16
	assert cells[2].is_alt == true
	assert cells[3].x == 26
	assert cells[3].y == 36
	assert cells[3].width == 16
	assert cells[3].height == 16
	assert cells[3].is_alt == false
}

fn test_compute_checkerboard_cells_partial_edges() {
	cells := compute_checkerboard_cells(0, 0, 20, 20, 16)
	assert cells.len == 4
	assert cells[0].width == 16
	assert cells[0].height == 16
	assert cells[1].x == 16
	assert cells[1].width == 4
	assert cells[1].height == 16
	assert cells[2].y == 16
	assert cells[2].width == 16
	assert cells[2].height == 4
	assert cells[3].x == 16
	assert cells[3].y == 16
	assert cells[3].width == 4
	assert cells[3].height == 4
}

fn test_compute_visible_checkerboard_cells_clipped_to_canvas() {
	cells := compute_visible_checkerboard_cells(-4000, -3000, 16000, 12000, 16, 800, 600)
	assert cells.len > 0
	assert cells.len <= 2100
	for c in cells {
		assert c.x >= 0.0
		assert c.y >= 0.0
		assert c.x + c.width <= 800.01
		assert c.y + c.height <= 600.01
	}
}

fn test_compute_visible_checkerboard_cells_off_screen() {
	cells := compute_visible_checkerboard_cells(-2000, -2000, 500, 500, 16, 800, 600)
	assert cells.len == 0
}

fn checker_test_viewport(x f32, y f32, w f32, h f32) Viewport {
	return Viewport{
		x:      x
		y:      y
		width:  w
		height: h
		scale:  1.0
	}
}

fn test_checkerboard_pattern_uses_existing_colors_and_16px_cells() {
	pattern := checkerboard_pattern()
	assert pattern.valid()
	assert pattern.tile_width == 32.0
	assert pattern.tile_height == 32.0
	assert pattern.pixel_width == 32
	assert pattern.pixel_height == 32
	assert pattern.origin_x == 0.0
	assert pattern.origin_y == 0.0
	assert pattern.pixels[0] == u8((checker_dark_hex >> 16) & 0xff)
	assert pattern.pixels[1] == u8((checker_dark_hex >> 8) & 0xff)
	assert pattern.pixels[2] == u8(checker_dark_hex & 0xff)
	light := 16 * 4
	assert pattern.pixels[light] == u8((checker_light_hex >> 16) & 0xff)
	assert pattern.pixels[light + 1] == u8((checker_light_hex >> 8) & 0xff)
	assert pattern.pixels[light + 2] == u8(checker_light_hex & 0xff)
	row := 16 * 32 * 4
	assert pattern.pixels[row] == u8((checker_light_hex >> 16) & 0xff)
}

fn test_checkerboard_reveal_rect_uses_transformed_viewport() {
	mut vp := checker_test_viewport(100, 120, 320, 240)
	vp.rotation = 90
	assert checkerboard_reveal_rect(vp) == ui2.rect(100, 120, 320, 240)
	assert checkerboard_reveal_rect(vp) != ui2.rect(0, 0, 800, 600)
}

fn test_app_show_checkerboard_defaults_true_and_toggles() {
	mut app := new_app()
	assert app.show_checkerboard == true
	app.toggle_checkerboard()
	assert app.show_checkerboard == false
	app.toggle_checkerboard()
	assert app.show_checkerboard == true
}

fn checkerboard_test_resource(id string, opacity ui2.ImageOpacity) ui2.ImageResource {
	return ui2.ready_image_resource(id, 'sample.png', ui2.ImageResourceInput{
		width:    1
		height:   1
		channels: 4
		pixels:   []u8{len: 4, init: 255}
	}, opacity)
}

fn test_transparency_background_opacity_gating() {
	mut app := new_app()
	app.set_image_resource(checkerboard_test_resource('opaque', .proven_opaque))
	assert !app.transparency_background_visible()
	app.set_image_resource(checkerboard_test_resource('alpha', .has_alpha))
	assert app.transparency_background_visible()
	app.set_image_resource(checkerboard_test_resource('unknown', .unknown))
	assert app.transparency_background_visible()
	app.set_image_resource(ui2.loading_image_resource('loading', 'next.png'))
	assert app.transparency_background_visible()
	app.toggle_checkerboard()
	assert !app.transparency_background_visible()
}

fn test_build_screen_uses_repeat_pattern_and_reuses_tile() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.window_ready = true

	first := app.build_screen_at_size(800, 600)
	assert first.children.len == 2
	pattern_element := first.children[0]
	assert pattern_element.id == 'transparency_background'
	assert pattern_element.kind == .view
	assert pattern_element.image_path == ''
	assert pattern_element.background.pattern.valid()
	assert pattern_element.background.clip == pattern_element.frame
	assert pattern_element.frame == checkerboard_reveal_rect(app.core.viewport)
	assert pattern_element.frame.width < 800.0 || pattern_element.frame.height < 600.0
	pattern_id := pattern_element.background.pattern.id
	pixels := pattern_element.background.pattern.pixels.clone()

	app.core.zoom_in()
	app.core.pan(20, 10)
	app.core.rotate_cw()
	app.core.flip_h()
	app.core.set_canvas_size(1024, 768)
	second := app.build_screen_at_size(1024, 768)
	assert second.children.len == 2
	assert second.children[0].background.pattern.id == pattern_id
	assert second.children[0].background.pattern.pixels == pixels
	assert second.children[0].background.pattern.pixel_width * second.children[0].background.pattern.pixel_height < 800 * 600
}

fn test_build_screen_omits_pattern_for_proven_opaque_image() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_resource(checkerboard_test_resource('opaque', .proven_opaque))
	app.window_ready = true
	screen := app.build_screen_at_size(800, 600)
	assert screen.children.len == 1
	assert screen.children[0].id == 'canvas_bg'
}

fn test_build_screen_retains_pattern_for_loading_image() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.core.set_image_resource(ui2.loading_image_resource('loading', 'next.png'))
	app.window_ready = true
	screen := app.build_screen_at_size(800, 600)
	assert screen.children.len == 2
	assert screen.children[0].id == 'transparency_background'
}

fn test_build_screen_hides_checker_when_toggled_off() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.core.toggle_checkerboard()
	app.window_ready = true
	screen := app.build_screen_at_size(800, 600)
	assert screen.children.len == 1
	assert screen.children[0].id == 'canvas_bg'
	assert screen.children[0].children.len == 1
	assert screen.children[0].children[0].id == 'viewport_image'
}
