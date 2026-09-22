module main

import math
import gg

pub const min_zoom_scale = f32(0.05)
pub const max_zoom_scale = f32(50.0)
pub const zoom_step_factor = f32(1.15)

pub enum TextureFilterMode {
	linear
	nearest
}

// Viewport represents the visible coordinate frame and transformation state
// mapping image space to screen space.
pub struct Viewport {
pub mut:
	x        f32
	y        f32
	width    f32
	height   f32
	scale    f32
	rotation int  // 0, 90, 180, 270 (degrees clockwise)
	flip_h   bool // horizontal flip
	flip_v   bool // vertical flip
}

// clamp_zoom_scale clamps scale magnification to the defined [min_zoom_scale, max_zoom_scale] boundaries.
pub fn clamp_zoom_scale(scale f32) f32 {
	if scale < min_zoom_scale {
		return min_zoom_scale
	}
	if scale > max_zoom_scale {
		return max_zoom_scale
	}
	return scale
}

// get_effective_dimensions returns the visual bounding dimensions accounting for 90-degree step rotations.
pub fn get_effective_dimensions(w int, h int, rotation int) (int, int) {
	norm_rot := (rotation % 360 + 360) % 360
	if norm_rot == 90 || norm_rot == 270 {
		return h, w
	}
	return w, h
}

// calculate_fit_to_window_rotated scales and centers an image to maximally fill the canvas
// while preserving aspect ratio, respecting the specified rotation.
pub fn calculate_fit_to_window_rotated(canvas_w int, canvas_h int, img_w int, img_h int, rotation int) Viewport {
	norm_rot := (rotation % 360 + 360) % 360
	if canvas_w <= 0 || canvas_h <= 0 || img_w <= 0 || img_h <= 0 {
		return Viewport{
			x:        0
			y:        0
			width:    0
			height:   0
			scale:    1.0
			rotation: norm_rot
		}
	}

	eff_w, eff_h := get_effective_dimensions(img_w, img_h, norm_rot)
	scale_w := f32(canvas_w) / f32(eff_w)
	scale_h := f32(canvas_h) / f32(eff_h)
	scale := clamp_zoom_scale(math.min(scale_w, scale_h))

	w := f32(eff_w) * scale
	h := f32(eff_h) * scale
	x := (f32(canvas_w) - w) / 2.0
	y := (f32(canvas_h) - h) / 2.0

	return Viewport{
		x:        x
		y:        y
		width:    w
		height:   h
		scale:    scale
		rotation: norm_rot
	}
}

// calculate_fit_to_window scales and centers an image to maximally fill the canvas (unrotated).
pub fn calculate_fit_to_window(canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	return calculate_fit_to_window_rotated(canvas_w, canvas_h, img_w, img_h, 0)
}

// calculate_actual_size_rotated sets zoom magnification to exactly 1:1, centered, respecting rotation.
pub fn calculate_actual_size_rotated(canvas_w int, canvas_h int, img_w int, img_h int, rotation int) Viewport {
	norm_rot := (rotation % 360 + 360) % 360
	if canvas_w <= 0 || canvas_h <= 0 || img_w <= 0 || img_h <= 0 {
		return Viewport{
			x:        0
			y:        0
			width:    0
			height:   0
			scale:    1.0
			rotation: norm_rot
		}
	}

	eff_w, eff_h := get_effective_dimensions(img_w, img_h, norm_rot)
	scale := clamp_zoom_scale(1.0)
	w := f32(eff_w) * scale
	h := f32(eff_h) * scale
	x := (f32(canvas_w) - w) / 2.0
	y := (f32(canvas_h) - h) / 2.0

	return Viewport{
		x:        x
		y:        y
		width:    w
		height:   h
		scale:    scale
		rotation: norm_rot
	}
}

// calculate_actual_size sets zoom magnification to exactly 1:1, centered (unrotated).
pub fn calculate_actual_size(canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	return calculate_actual_size_rotated(canvas_w, canvas_h, img_w, img_h, 0)
}

// calculate_initial_viewport_rotated determines initial layout:
// - Downscales large images to fit canvas while preserving aspect ratio.
// - Centers smaller images at 1:1 pixel scale.
pub fn calculate_initial_viewport_rotated(canvas_w int, canvas_h int, img_w int, img_h int, rotation int) Viewport {
	norm_rot := (rotation % 360 + 360) % 360
	if canvas_w <= 0 || canvas_h <= 0 || img_w <= 0 || img_h <= 0 {
		return Viewport{
			x:        0
			y:        0
			width:    0
			height:   0
			scale:    1.0
			rotation: norm_rot
		}
	}

	eff_w, eff_h := get_effective_dimensions(img_w, img_h, norm_rot)
	if eff_w <= canvas_w && eff_h <= canvas_h {
		return calculate_actual_size_rotated(canvas_w, canvas_h, img_w, img_h, norm_rot)
	}
	return calculate_fit_to_window_rotated(canvas_w, canvas_h, img_w, img_h, norm_rot)
}

// calculate_initial_viewport determines initial layout for unrotated image.
pub fn calculate_initial_viewport(canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	return calculate_initial_viewport_rotated(canvas_w, canvas_h, img_w, img_h, 0)
}

// format_window_title generates the window title adhering to the convention:
// `image-ui - <filename> (<width>x<height>)` or `image-ui` when no image is loaded.
pub fn format_window_title(file_path string, img_w int, img_h int) string {
	if file_path == '' || img_w <= 0 || img_h <= 0 {
		return 'image-ui'
	}
	filename := file_path.all_after_last('/').all_after_last('\\')
	return 'image-ui - ${filename} (${img_w}x${img_h})'
}

// zoom_at performs continuous cursor-anchored zoom, guaranteeing that the image point
// directly underneath (cursor_x, cursor_y) maintains invariant canvas position after scale change.
pub fn zoom_at(vp Viewport, cursor_x f32, cursor_y f32, target_scale f32) Viewport {
	if vp.scale <= 0 {
		return vp
	}
	new_scale := clamp_zoom_scale(target_scale)
	if new_scale == vp.scale {
		return vp
	}

	ratio := new_scale / vp.scale
	new_x := cursor_x - (cursor_x - vp.x) * ratio
	new_y := cursor_y - (cursor_y - vp.y) * ratio
	new_w := vp.width * ratio
	new_h := vp.height * ratio

	return Viewport{
		x:        new_x
		y:        new_y
		width:    new_w
		height:   new_h
		scale:    new_scale
		rotation: vp.rotation
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
}

// constrain_pan clamps viewport coordinates during pan gestures:
// 1. If displayed size <= canvas size, the image is kept centered.
// 2. If displayed size > canvas size, the image edges cannot leave the window boundaries.
pub fn constrain_pan(vp Viewport, canvas_w int, canvas_h int) Viewport {
	if canvas_w <= 0 || canvas_h <= 0 {
		return vp
	}

	mut new_x := vp.x
	cw := f32(canvas_w)
	if vp.width <= cw {
		new_x = (cw - vp.width) / 2.0
	} else {
		min_x := cw - vp.width
		max_x := f32(0.0)
		if new_x < min_x {
			new_x = min_x
		} else if new_x > max_x {
			new_x = max_x
		}
	}

	mut new_y := vp.y
	ch := f32(canvas_h)
	if vp.height <= ch {
		new_y = (ch - vp.height) / 2.0
	} else {
		min_y := ch - vp.height
		max_y := f32(0.0)
		if new_y < min_y {
			new_y = min_y
		} else if new_y > max_y {
			new_y = max_y
		}
	}

	return Viewport{
		x:        new_x
		y:        new_y
		width:    vp.width
		height:   vp.height
		scale:    vp.scale
		rotation: vp.rotation
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
}

// constrain_zoom keeps the image within canvas boundaries without forcing centering on smaller dimensions,
// preserving the cursor-anchored position across all zoom levels.
pub fn constrain_zoom(vp Viewport, canvas_w int, canvas_h int) Viewport {
	if canvas_w <= 0 || canvas_h <= 0 {
		return vp
	}

	mut new_x := vp.x
	cw := f32(canvas_w)
	if vp.width <= cw {
		min_x := f32(0.0)
		max_x := cw - vp.width
		if new_x < min_x {
			new_x = min_x
		} else if new_x > max_x {
			new_x = max_x
		}
	} else {
		min_x := cw - vp.width
		max_x := f32(0.0)
		if new_x < min_x {
			new_x = min_x
		} else if new_x > max_x {
			new_x = max_x
		}
	}

	mut new_y := vp.y
	ch := f32(canvas_h)
	if vp.height <= ch {
		min_y := f32(0.0)
		max_y := ch - vp.height
		if new_y < min_y {
			new_y = min_y
		} else if new_y > max_y {
			new_y = max_y
		}
	} else {
		min_y := ch - vp.height
		max_y := f32(0.0)
		if new_y < min_y {
			new_y = min_y
		} else if new_y > max_y {
			new_y = max_y
		}
	}

	return Viewport{
		x:        new_x
		y:        new_y
		width:    vp.width
		height:   vp.height
		scale:    vp.scale
		rotation: vp.rotation
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
}

// pan adds displacement (dx, dy) and constrains the resulting viewport position.
pub fn pan(vp Viewport, dx f32, dy f32, canvas_w int, canvas_h int) Viewport {
	moved := Viewport{
		x:        vp.x + dx
		y:        vp.y + dy
		width:    vp.width
		height:   vp.height
		scale:    vp.scale
		rotation: vp.rotation
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
	return constrain_pan(moved, canvas_w, canvas_h)
}

// rotate_cw rotates the viewport 90 degrees clockwise around its visual center.
pub fn rotate_cw(vp Viewport, canvas_w int, canvas_h int) Viewport {
	cx := vp.x + vp.width / 2.0
	cy := vp.y + vp.height / 2.0
	new_w := vp.height
	new_h := vp.width
	new_x := cx - new_w / 2.0
	new_y := cy - new_h / 2.0
	new_rot := (vp.rotation + 90) % 360

	unconstrained := Viewport{
		x:        new_x
		y:        new_y
		width:    new_w
		height:   new_h
		scale:    vp.scale
		rotation: new_rot
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
	return constrain_pan(unconstrained, canvas_w, canvas_h)
}

// rotate_ccw rotates the viewport 90 degrees counter-clockwise around its visual center.
pub fn rotate_ccw(vp Viewport, canvas_w int, canvas_h int) Viewport {
	cx := vp.x + vp.width / 2.0
	cy := vp.y + vp.height / 2.0
	new_w := vp.height
	new_h := vp.width
	new_x := cx - new_w / 2.0
	new_y := cy - new_h / 2.0
	new_rot := (vp.rotation + 270) % 360

	unconstrained := Viewport{
		x:        new_x
		y:        new_y
		width:    new_w
		height:   new_h
		scale:    vp.scale
		rotation: new_rot
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
	return constrain_pan(unconstrained, canvas_w, canvas_h)
}

// flip_horizontal toggles horizontal flip.
pub fn flip_horizontal(vp Viewport) Viewport {
	return Viewport{
		x:        vp.x
		y:        vp.y
		width:    vp.width
		height:   vp.height
		scale:    vp.scale
		rotation: vp.rotation
		flip_h:   !vp.flip_h
		flip_v:   vp.flip_v
	}
}

// flip_vertical toggles vertical flip.
pub fn flip_vertical(vp Viewport) Viewport {
	return Viewport{
		x:        vp.x
		y:        vp.y
		width:    vp.width
		height:   vp.height
		scale:    vp.scale
		rotation: vp.rotation
		flip_h:   vp.flip_h
		flip_v:   !vp.flip_v
	}
}

// toggle_fit_or_actual toggles between Fit to Window and Actual Size (1:1).
pub fn toggle_fit_or_actual(vp Viewport, canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	fit_vp := calculate_fit_to_window_rotated(canvas_w, canvas_h, img_w, img_h, vp.rotation)
	if math.abs(vp.scale - fit_vp.scale) < 0.001 {
		act_vp := calculate_actual_size_rotated(canvas_w, canvas_h, img_w, img_h, vp.rotation)
		return Viewport{
			x:        act_vp.x
			y:        act_vp.y
			width:    act_vp.width
			height:   act_vp.height
			scale:    act_vp.scale
			rotation: vp.rotation
			flip_h:   vp.flip_h
			flip_v:   vp.flip_v
		}
	}
	return Viewport{
		x:        fit_vp.x
		y:        fit_vp.y
		width:    fit_vp.width
		height:   fit_vp.height
		scale:    fit_vp.scale
		rotation: vp.rotation
		flip_h:   vp.flip_h
		flip_v:   vp.flip_v
	}
}

// get_texture_filter_for_scale determines the texture filter mode:
// Bilinear (.linear) when zoomed out (< 1.0)
// Nearest-neighbor (.nearest) when magnified (> 2.0)
// Unchanged when between 1.0 and 2.0
pub fn get_texture_filter_for_scale(scale f32, current_mode TextureFilterMode) TextureFilterMode {
	if scale > 2.0 {
		return .nearest
	} else if scale < 1.0 {
		return .linear
	}
	return current_mode
}

// get_draw_flips computes texture flip flags for sokol/gg quad rendering.
// Rotation transforms the local axes, so at 90 and 270 degrees horizontal screen flip
// maps to texture V and vertical to texture U.
pub fn get_draw_flips(rotation int, flip_h bool, flip_v bool) (bool, bool) {
	norm_rot := (rotation % 360 + 360) % 360
	match norm_rot {
		90, 270 { return flip_v, flip_h }
		else { return flip_h, flip_v }
	}
}

// get_draw_image_params calculates the unrotated quad rect, rotation degrees, and flip flags
// ready to pass into gg.DrawImageConfig.
pub fn get_draw_image_params(vp Viewport, img_w int, img_h int) (gg.Rect, f32, bool, bool) {
	cx := vp.x + vp.width / 2.0
	cy := vp.y + vp.height / 2.0
	quad_w := f32(img_w) * vp.scale
	quad_h := f32(img_h) * vp.scale

	img_rect := gg.Rect{
		x:      cx - quad_w / 2.0
		y:      cy - quad_h / 2.0
		width:  quad_w
		height: quad_h
	}

	norm_rot := (vp.rotation % 360 + 360) % 360
	// Sokol uses negative rotation angle in degrees for clockwise rotation
	rot_deg := -f32(norm_rot)
	flip_x, flip_y := get_draw_flips(norm_rot, vp.flip_h, vp.flip_v)

	return img_rect, rot_deg, flip_x, flip_y
}

// screen_to_image converts canvas/screen pixel coordinates (sx, sy) to original image pixel coordinates (ix, iy).
pub fn screen_to_image(sx f32, sy f32, vp Viewport, img_w int, img_h int) (f32, f32) {
	if vp.scale <= 0 {
		return 0.0, 0.0
	}
	cx := vp.x + vp.width / 2.0
	cy := vp.y + vp.height / 2.0

	// 1. Relative to visual center on screen
	x4 := sx - cx
	y4 := sy - cy

	// 2. Unscale
	x3 := x4 / vp.scale
	y3 := y4 / vp.scale

	// 3. Inverse rotation (counter-clockwise)
	norm_rot := (vp.rotation % 360 + 360) % 360
	mut x2 := f32(0.0)
	mut y2 := f32(0.0)
	match norm_rot {
		0 {
			x2 = x3
			y2 = y3
		}
		90 {
			x2 = y3
			y2 = -x3
		}
		180 {
			x2 = -x3
			y2 = -y3
		}
		270 {
			x2 = -y3
			y2 = x3
		}
		else {
			rad := f64(-norm_rot) * math.pi / 180.0
			cos_r := f32(math.cos(rad))
			sin_r := f32(math.sin(rad))
			x2 = x3 * cos_r - y3 * sin_r
			y2 = x3 * sin_r + y3 * cos_r
		}
	}

	// 4. Inverse flip
	x1 := if vp.flip_h { -x2 } else { x2 }
	y1 := if vp.flip_v { -y2 } else { y2 }

	// 5. Shift back from image center to top-left origin
	ix := x1 + f32(img_w) / 2.0
	iy := y1 + f32(img_h) / 2.0

	return ix, iy
}

// image_to_screen converts original image pixel coordinates (ix, iy) to canvas/screen coordinates (sx, sy).
pub fn image_to_screen(ix f32, iy f32, vp Viewport, img_w int, img_h int) (f32, f32) {
	cx := vp.x + vp.width / 2.0
	cy := vp.y + vp.height / 2.0

	// 1. Shift from top-left origin to image center
	x1 := ix - f32(img_w) / 2.0
	y1 := iy - f32(img_h) / 2.0

	// 2. Apply flip
	x2 := if vp.flip_h { -x1 } else { x1 }
	y2 := if vp.flip_v { -y1 } else { y1 }

	// 3. Apply rotation (clockwise)
	norm_rot := (vp.rotation % 360 + 360) % 360
	mut x3 := f32(0.0)
	mut y3 := f32(0.0)
	match norm_rot {
		0 {
			x3 = x2
			y3 = y2
		}
		90 {
			x3 = -y2
			y3 = x2
		}
		180 {
			x3 = -x2
			y3 = -y2
		}
		270 {
			x3 = y2
			y3 = -x2
		}
		else {
			rad := f64(norm_rot) * math.pi / 180.0
			cos_r := f32(math.cos(rad))
			sin_r := f32(math.sin(rad))
			x3 = x2 * cos_r - y2 * sin_r
			y3 = x2 * sin_r + y2 * cos_r
		}
	}

	// 4. Scale
	x4 := x3 * vp.scale
	y4 := y3 * vp.scale

	// 5. Translate to visual center on screen
	sx := cx + x4
	sy := cy + y4

	return sx, sy
}
