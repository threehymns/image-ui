module main

import math

fn test_format_window_title() {
	assert format_window_title('', 0, 0) == 'image-ui'
	assert format_window_title('photo.png', 1920, 1080) == 'image-ui - photo.png (1920x1080)'
	assert format_window_title('/home/user/images/sample.jpg', 800, 600) == 'image-ui - sample.jpg (800x600)'
	assert format_window_title('C:\\Photos\\test.png', 100, 200) == 'image-ui - test.png (100x200)'
}

fn test_viewport_zero_or_negative_dimensions() {
	vp1 := calculate_initial_viewport(0, 0, 100, 100)
	assert vp1.width == 0
	assert vp1.height == 0

	vp2 := calculate_initial_viewport(800, 600, 0, 0)
	assert vp2.width == 0
	assert vp2.height == 0

	vp3 := calculate_fit_to_window(-10, 600, 100, 100)
	assert vp3.width == 0
	assert vp3.height == 0
}

fn test_viewport_actual_size_centered() {
	// Canvas 800x600, image 400x200
	vp := calculate_actual_size(800, 600, 400, 200)
	assert vp.scale == 1.0
	assert vp.width == 400
	assert vp.height == 200
	assert vp.x == 200
	assert vp.y == 200
}

fn test_viewport_initial_small_image() {
	// Image fits inside canvas: should stay 1:1 and centered
	vp := calculate_initial_viewport(800, 600, 300, 150)
	assert vp.scale == 1.0
	assert vp.width == 300
	assert vp.height == 150
	assert vp.x == 250
	assert vp.y == 225
}

fn test_viewport_initial_large_image_scaled_down() {
	// Image 1600x1200 on canvas 800x600: scale factor should be 0.5
	vp := calculate_initial_viewport(800, 600, 1600, 1200)
	assert math.abs(vp.scale - 0.5) < 0.001
	assert math.abs(vp.width - 800) < 0.001
	assert math.abs(vp.height - 600) < 0.001
	assert math.abs(vp.x - 0.0) < 0.001
	assert math.abs(vp.y - 0.0) < 0.001
}

fn test_viewport_fit_to_window_aspect_ratio_wide() {
	// Image 1920x1080 on canvas 960x1000
	vp := calculate_fit_to_window(960, 1000, 1920, 1080)
	assert math.abs(vp.scale - 0.5) < 0.001
	assert math.abs(vp.width - 960) < 0.001
	assert math.abs(vp.height - 540) < 0.001
	assert math.abs(vp.x - 0) < 0.001
	assert math.abs(vp.y - (1000 - 540) / 2.0) < 0.001
}

fn test_viewport_fit_to_window_aspect_ratio_tall() {
	// Image 1000x2000 on canvas 800x1000
	vp := calculate_fit_to_window(800, 1000, 1000, 2000)
	assert math.abs(vp.scale - 0.5) < 0.001
	assert math.abs(vp.width - 500) < 0.001
	assert math.abs(vp.height - 1000) < 0.001
	assert math.abs(vp.x - (800 - 500) / 2.0) < 0.001
	assert math.abs(vp.y - 0) < 0.001
}

fn test_clamp_zoom_scale() {
	assert clamp_zoom_scale(0.01) == min_zoom_scale
	assert clamp_zoom_scale(0.05) == min_zoom_scale
	assert clamp_zoom_scale(1.0) == 1.0
	assert clamp_zoom_scale(50.0) == 50.0
	assert clamp_zoom_scale(100.0) == max_zoom_scale
}

fn test_cursor_anchored_zoom() {
	// Start with image 800x600 at 1:1, centered in 1000x800 canvas
	vp0 := calculate_actual_size(1000, 800, 800, 600)
	assert vp0.x == 100
	assert vp0.y == 100
	assert vp0.scale == 1.0

	// Cursor is at canvas position (300, 250)
	cursor_x := f32(300.0)
	cursor_y := f32(250.0)

	// Image coordinate before zoom under cursor
	ix0, iy0 := screen_to_image(cursor_x, cursor_y, vp0, 800, 600)

	// Zoom in to 2.0x
	vp1 := zoom_at(vp0, cursor_x, cursor_y, 2.0)
	assert vp1.scale == 2.0
	assert vp1.width == 1600.0
	assert vp1.height == 1200.0

	// Verify the image coordinate under the cursor is EXACTLY unchanged
	ix1, iy1 := screen_to_image(cursor_x, cursor_y, vp1, 800, 600)
	assert math.abs(ix1 - ix0) < 0.001
	assert math.abs(iy1 - iy0) < 0.001

	// Zoom out to 0.5x
	vp2 := zoom_at(vp1, cursor_x, cursor_y, 0.5)
	assert vp2.scale == 0.5
	assert vp2.width == 400.0
	assert vp2.height == 300.0

	ix2, iy2 := screen_to_image(cursor_x, cursor_y, vp2, 800, 600)
	assert math.abs(ix2 - ix0) < 0.001
	assert math.abs(iy2 - iy0) < 0.001
}

fn test_cursor_anchored_zoom_at_center_and_edges() {
	vp := Viewport{
		x: 50.0
		y: 50.0
		width: 400.0
		height: 300.0
		scale: 1.0
	}

	// 1. Zoom with cursor at top-left corner (50, 50)
	vp_tl := zoom_at(vp, 50.0, 50.0, 2.0)
	assert math.abs(vp_tl.x - 50.0) < 0.001
	assert math.abs(vp_tl.y - 50.0) < 0.001

	// 2. Zoom with cursor at center (250, 200)
	vp_center := zoom_at(vp, 250.0, 200.0, 2.0)
	// Center should stay at (250, 200), so new x = 250 - 400 = -150, new y = 200 - 300 = -100
	assert math.abs(vp_center.x - (-150.0)) < 0.001
	assert math.abs(vp_center.y - (-100.0)) < 0.001
	assert math.abs((vp_center.x + vp_center.width / 2.0) - 250.0) < 0.001
	assert math.abs((vp_center.y + vp_center.height / 2.0) - 200.0) < 0.001
}

fn test_constrain_pan_when_smaller_than_canvas() {
	// If image is 400x300 in 800x600 canvas, it must remain centered
	vp := Viewport{
		x: 10.0 // Attempt to position off-center
		y: 10.0
		width: 400.0
		height: 300.0
		scale: 1.0
	}
	constrained := constrain_pan(vp, 800, 600)
	assert constrained.x == 200.0
	assert constrained.y == 150.0
}

fn test_constrain_pan_when_larger_than_canvas() {
	// Canvas 800x600, image 1600x1200
	// Allowed X range: [800 - 1600, 0] = [-800, 0]
	// Allowed Y range: [600 - 1200, 0] = [-600, 0]
	vp := Viewport{
		x: -400.0
		y: -300.0
		width: 1600.0
		height: 1200.0
		scale: 2.0
	}

	// Within bounds: preserved
	c1 := constrain_pan(vp, 800, 600)
	assert c1.x == -400.0
	assert c1.y == -300.0

	// Drag too far right (x > 0): clamped to 0
	vp_right := Viewport{
		x: 150.0
		y: -300.0
		width: 1600.0
		height: 1200.0
		scale: 2.0
	}
	c2 := constrain_pan(vp_right, 800, 600)
	assert c2.x == 0.0
	assert c2.y == -300.0

	// Drag too far left (x < -800): clamped to -800
	vp_left := Viewport{
		x: -1200.0
		y: -300.0
		width: 1600.0
		height: 1200.0
		scale: 2.0
	}
	c3 := constrain_pan(vp_left, 800, 600)
	assert c3.x == -800.0
	assert c3.y == -300.0

	// Drag too far down (y > 0): clamped to 0
	vp_down := Viewport{
		x: -400.0
		y: 80.0
		width: 1600.0
		height: 1200.0
		scale: 2.0
	}
	c4 := constrain_pan(vp_down, 800, 600)
	assert c4.y == 0.0

	// Drag too far up (y < -600): clamped to -600
	vp_up := Viewport{
		x: -400.0
		y: -950.0
		width: 1600.0
		height: 1200.0
		scale: 2.0
	}
	c5 := constrain_pan(vp_up, 800, 600)
	assert c5.y == -600.0
}

fn test_subpixel_panning() {
	vp := Viewport{
		x: -400.0
		y: -300.0
		width: 1600.0
		height: 1200.0
		scale: 2.0
	}
	// Pan by fractional sub-pixel delta
	panned := pan(vp, 2.75, -3.125, 800, 600)
	assert math.abs(panned.x - (-397.25)) < 0.001
	assert math.abs(panned.y - (-303.125)) < 0.001
}

fn test_rotation_step_cycling() {
	mut vp := Viewport{
		x: 200.0
		y: 150.0
		width: 400.0
		height: 300.0
		scale: 1.0
		rotation: 0
	}

	// Clockwise cycle
	vp = rotate_cw(vp, 800, 600)
	assert vp.rotation == 90
	assert vp.width == 300.0
	assert vp.height == 400.0

	vp = rotate_cw(vp, 800, 600)
	assert vp.rotation == 180
	assert vp.width == 400.0
	assert vp.height == 300.0

	vp = rotate_cw(vp, 800, 600)
	assert vp.rotation == 270
	assert vp.width == 300.0
	assert vp.height == 400.0

	vp = rotate_cw(vp, 800, 600)
	assert vp.rotation == 0
	assert vp.width == 400.0
	assert vp.height == 300.0

	// Counter-clockwise cycle
	vp = rotate_ccw(vp, 800, 600)
	assert vp.rotation == 270

	vp = rotate_ccw(vp, 800, 600)
	assert vp.rotation == 180

	vp = rotate_ccw(vp, 800, 600)
	assert vp.rotation == 90

	vp = rotate_ccw(vp, 800, 600)
	assert vp.rotation == 0
}

fn test_flip_toggling() {
	mut vp := Viewport{
		x: 0
		y: 0
		width: 100
		height: 100
		scale: 1.0
		flip_h: false
		flip_v: false
	}

	// Flip H
	vp = flip_horizontal(vp)
	assert vp.flip_h == true
	assert vp.flip_v == false

	// Flip H again resets
	vp = flip_horizontal(vp)
	assert vp.flip_h == false
	assert vp.flip_v == false

	// Flip V
	vp = flip_vertical(vp)
	assert vp.flip_h == false
	assert vp.flip_v == true

	// Flip V again resets
	vp = flip_vertical(vp)
	assert vp.flip_h == false
	assert vp.flip_v == false
}

fn test_fit_to_window_with_rotation() {
	// Image 1920x1080 rotated 90 degrees in canvas 1080x1920
	// Rotated effective dimensions: 1080x1920
	// Should fit perfectly at scale 1.0
	vp := calculate_fit_to_window_rotated(1080, 1920, 1920, 1080, 90)
	assert math.abs(vp.scale - 1.0) < 0.001
	assert math.abs(vp.width - 1080) < 0.001
	assert math.abs(vp.height - 1920) < 0.001
	assert math.abs(vp.x - 0.0) < 0.001
	assert math.abs(vp.y - 0.0) < 0.001
}

fn test_double_click_toggle_fit_and_actual() {
	// Image 1920x1080 on canvas 960x540
	// Fit scale = 0.5, Actual scale = 1.0
	fit_vp := calculate_fit_to_window(960, 540, 1920, 1080)
	assert math.abs(fit_vp.scale - 0.5) < 0.001

	// Starting at Fit to Window -> toggles to Actual Size
	toggled1 := toggle_fit_or_actual(fit_vp, 960, 540, 1920, 1080)
	assert math.abs(toggled1.scale - 1.0) < 0.001
	assert math.abs(toggled1.width - 1920.0) < 0.001
	assert math.abs(toggled1.height - 1080.0) < 0.001

	// Starting at Actual Size -> toggles back to Fit to Window
	toggled2 := toggle_fit_or_actual(toggled1, 960, 540, 1920, 1080)
	assert math.abs(toggled2.scale - 0.5) < 0.001
	assert math.abs(toggled2.width - 960.0) < 0.001
	assert math.abs(toggled2.height - 540.0) < 0.001
}

fn test_texture_filter_selection() {
	// Downscaled (< 1.0) -> bilinear (.linear)
	assert get_texture_filter_for_scale(0.5, .nearest) == .linear
	assert get_texture_filter_for_scale(0.99, .nearest) == .linear

	// Magnified (> 2.0) -> nearest-neighbor (.nearest)
	assert get_texture_filter_for_scale(2.01, .linear) == .nearest
	assert get_texture_filter_for_scale(5.0, .linear) == .nearest

	// Between 1.0 and 2.0 -> keeps existing mode
	assert get_texture_filter_for_scale(1.0, .linear) == .linear
	assert get_texture_filter_for_scale(1.5, .nearest) == .nearest
	assert get_texture_filter_for_scale(2.0, .linear) == .linear
}

fn test_coordinate_transforms_roundtrip() {
	img_w := 600
	img_h := 400

	// Test all 4 rotation angles and flip combinations
	rotations := [0, 90, 180, 270]
	flips := [
		[false, false],
		[true, false],
		[false, true],
		[true, true],
	]

	test_points_x := [0.0, 150.0, 300.0, 450.0, 600.0]
	test_points_y := [0.0, 100.0, 200.0, 300.0, 400.0]

	for rot in rotations {
		for f in flips {
			vp := Viewport{
				x: 120.0
				y: 80.0
				width: if rot % 180 != 0 { f32(img_h) * 1.5 } else { f32(img_w) * 1.5 }
				height: if rot % 180 != 0 { f32(img_w) * 1.5 } else { f32(img_h) * 1.5 }
				scale: 1.5
				rotation: rot
				flip_h: f[0]
				flip_v: f[1]
			}

			for ix in test_points_x {
				for iy in test_points_y {
					sx, sy := image_to_screen(f32(ix), f32(iy), vp, img_w, img_h)
					round_ix, round_iy := screen_to_image(sx, sy, vp, img_w, img_h)

					assert math.abs(round_ix - f32(ix)) < 0.05
					assert math.abs(round_iy - f32(iy)) < 0.05
				}
			}
		}
	}
}

fn test_draw_image_params() {
	vp := Viewport{
		x: 100.0
		y: 50.0
		width: 400.0
		height: 800.0
		scale: 2.0
		rotation: 90
		flip_h: true
		flip_v: false
	}
	// Image 400x200 rotated 90 degrees
	img_rect, rot_deg, flip_x, flip_y := get_draw_image_params(vp, 400, 200)

	// Visual center: x = 100 + 200 = 300, y = 50 + 400 = 450
	// Unrotated quad: w = 400 * 2 = 800, h = 200 * 2 = 400
	// Top-left of quad: 300 - 400 = -100, 450 - 200 = 250
	assert math.abs(img_rect.x - (-100.0)) < 0.001
	assert math.abs(img_rect.y - 250.0) < 0.001
	assert math.abs(img_rect.width - 800.0) < 0.001
	assert math.abs(img_rect.height - 400.0) < 0.001

	// Clockwise 90 degrees -> -90.0 in sokol
	assert rot_deg == -90.0
	// At 90 deg rotation, horizontal screen flip maps to texture Y (flip_y)
	assert flip_x == false
	assert flip_y == true
}
