module main

import os

fn test_compute_checkerboard_cells_zero_or_negative() {
	assert compute_checkerboard_cells(0, 0, 0, 100, 16).len == 0
	assert compute_checkerboard_cells(0, 0, 100, 0, 16).len == 0
	assert compute_checkerboard_cells(0, 0, 100, 100, 0).len == 0
	assert compute_checkerboard_cells(0, 0, -10, 100, 16).len == 0
}

fn test_compute_checkerboard_cells_exact_grid() {
	// 32x32 area with 16x16 cells -> 2x2 grid = 4 cells
	cells := compute_checkerboard_cells(10, 20, 32, 32, 16)
	assert cells.len == 4

	// Row 0, Col 0: (10, 20), size 16x16, is_alt = (0+0)%2 == 1 -> false
	assert cells[0].x == 10
	assert cells[0].y == 20
	assert cells[0].width == 16
	assert cells[0].height == 16
	assert cells[0].is_alt == false

	// Row 0, Col 1: (26, 20), size 16x16, is_alt = (0+1)%2 == 1 -> true
	assert cells[1].x == 26
	assert cells[1].y == 20
	assert cells[1].width == 16
	assert cells[1].height == 16
	assert cells[1].is_alt == true

	// Row 1, Col 0: (10, 36), size 16x16, is_alt = (1+0)%2 == 1 -> true
	assert cells[2].x == 10
	assert cells[2].y == 36
	assert cells[2].width == 16
	assert cells[2].height == 16
	assert cells[2].is_alt == true

	// Row 1, Col 1: (26, 36), size 16x16, is_alt = (1+1)%2 == 1 -> false
	assert cells[3].x == 26
	assert cells[3].y == 36
	assert cells[3].width == 16
	assert cells[3].height == 16
	assert cells[3].is_alt == false
}

fn test_compute_checkerboard_cells_partial_edges() {
	// 20x20 area with 16x16 cells -> 2x2 grid with partial right and bottom cells
	cells := compute_checkerboard_cells(0, 0, 20, 20, 16)
	assert cells.len == 4

	// Cell 0: 16x16
	assert cells[0].width == 16
	assert cells[0].height == 16

	// Cell 1: 4x16
	assert cells[1].x == 16
	assert cells[1].width == 4
	assert cells[1].height == 16

	// Cell 2: 16x4
	assert cells[2].y == 16
	assert cells[2].width == 16
	assert cells[2].height == 4

	// Cell 3: 4x4
	assert cells[3].x == 16
	assert cells[3].y == 16
	assert cells[3].width == 4
	assert cells[3].height == 4
}

fn test_compute_visible_checkerboard_cells_clipped_to_canvas() {
	// Canvas 800x600, image zoomed to 16000x12000 (extreme zoom)
	// Viewport x = -4000, y = -3000
	cells := compute_visible_checkerboard_cells(-4000, -3000, 16000, 12000, 16, 800, 600)
	// Without clipping, 16000x12000 would be 1000x750 = 750,000 cells!
	// With canvas clipping to 800x600, cells cannot exceed (800/16 + 2) * (600/16 + 2) = 52 * 40 = 2080 cells!
	assert cells.len > 0
	assert cells.len <= 2100

	// Every generated cell must be within canvas bounds
	for c in cells {
		assert c.x >= 0.0
		assert c.y >= 0.0
		assert c.x + c.width <= 800.01
		assert c.y + c.height <= 600.01
	}
}

fn test_compute_visible_checkerboard_cells_off_screen() {
	// Completely off screen image
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

fn test_checkerboard_elements_base_and_alternating_tiles() {
	vp := checker_test_viewport(100, 100, 32, 32)
	els := checkerboard_elements(vp, 800, 600, 16)
	// Base + 2 alternating 16x16 tiles in a 2x2 grid
	assert els.len == 3
	assert els[0].id == 'checker_base'
	assert els[0].box.bg == checker_dark_hex
	// Base covers visible image bounds
	assert els[0].frame.x == 100.0
	assert els[0].frame.y == 100.0
	assert els[0].frame.width == 32.0
	assert els[0].frame.height == 32.0
	for i in 1 .. els.len {
		assert els[i].box.bg == checker_light_hex
	}
}

fn test_checkerboard_elements_unique_ids() {
	vp := checker_test_viewport(0, 0, 64, 64)
	els := checkerboard_elements(vp, 800, 600, 16)
	mut seen := map[string]bool{}
	for el in els {
		assert !(el.id in seen)
		seen[el.id] = true
	}
}

fn test_checkerboard_elements_clipped_to_canvas() {
	// Extreme zoom: 16000x12000 viewport must stay bounded by canvas
	vp := checker_test_viewport(-4000, -3000, 16000, 12000)
	els := checkerboard_elements(vp, 800, 600, 16)
	assert els.len > 0
	assert els.len <= 2100
	for el in els {
		assert el.frame.x >= 0.0
		assert el.frame.y >= 0.0
		assert el.frame.x + el.frame.width <= 800.01
		assert el.frame.y + el.frame.height <= 600.01
	}
}

fn test_checkerboard_elements_empty_when_off_screen_or_degenerate() {
	assert checkerboard_elements(checker_test_viewport(-2000, -2000, 500, 500), 800,
		600, 16).len == 0
	assert checkerboard_elements(checker_test_viewport(0, 0, 0, 100), 800, 600, 16).len == 0
	assert checkerboard_elements(checker_test_viewport(0, 0, 100, 100), 0, 600, 16).len == 0
}

fn test_checkerboard_elements_uses_default_size_on_non_positive() {
	vp := checker_test_viewport(0, 0, 32, 32)
	default_els := checkerboard_elements(vp, 800, 600, 16)
	zero_els := checkerboard_elements(vp, 800, 600, 0)
	assert zero_els.len == default_els.len
}

fn test_app_show_checkerboard_defaults_true_and_toggles() {
	mut app := new_app()
	assert app.show_checkerboard == true
	app.toggle_checkerboard()
	assert app.show_checkerboard == false
	app.toggle_checkerboard()
	assert app.show_checkerboard == true
}

fn test_checkerboard_masks_cover_only_outside_image_bounds() {
	masks := checkerboard_mask_elements(checker_test_viewport(100, 100, 400, 300), 800, 600)
	assert masks.len == 4
	full := checkerboard_mask_elements(checker_test_viewport(-100, -100, 1000, 800), 800, 600)
	assert full.len == 0
}

fn test_build_screen_shows_checker_behind_image_by_default() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.window_ready = true
	screen := app.build_screen()
	assert screen.children.len >= 2
	assert screen.children[0].id == 'checkerboard_layer'
	assert screen.children[0].kind == .image
	assert os.exists(screen.children[0].image_path)
	canvas := screen.children[screen.children.len - 1]
	assert canvas.id == 'canvas_bg'
	assert canvas.children.len == 1
	assert canvas.children[0].id == 'viewport_image'
}

fn test_build_screen_reuses_checker_layer_for_unchanged_geometry() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.window_ready = true

	first := app.build_screen()
	key := app.checkerboard_key
	first_frame := first.children[0].frame
	second := app.build_screen()
	assert app.checkerboard_key == key
	assert second.children[0].frame == first_frame
}

fn test_build_screen_reuses_checker_layer_after_zoom() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.window_ready = true

	_ := app.build_screen()
	old_key := app.checkerboard_key
	app.core.zoom_in()
	_ = app.build_screen()
	assert app.checkerboard_key == old_key
}

fn test_checker_layer_defers_resize_regeneration() {
	mut app := &ViewerApp{}
	app.get_checkerboard_layer(800, 600)
	old_key := app.checkerboard_key

	first := app.get_checkerboard_layer(801, 601)
	assert app.checkerboard_key == old_key
	assert first.frame.width == 801.0

	second := app.get_checkerboard_layer(801, 601)
	assert app.checkerboard_key == old_key
	assert second.frame.height == 601.0

	_ = app.get_checkerboard_layer(801, 601)
	assert app.checkerboard_key == '801:601'
}

fn test_build_screen_hides_checker_when_toggled_off() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.core.set_canvas_size(800, 600)
	app.core.set_image_loaded('sample.png', 400, 300)
	app.core.toggle_checkerboard()
	app.window_ready = true
	screen := app.build_screen()
	assert screen.children.len == 1
	assert screen.children[0].id == 'canvas_bg'
	assert screen.children[0].children.len == 1
	assert screen.children[0].children[0].id == 'viewport_image'
}
