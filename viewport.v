module main

import math

// Viewport represents the visible coordinate frame and transformation state
// mapping image space to screen space.
pub struct Viewport {
pub mut:
	x      f32
	y      f32
	width  f32
	height f32
	scale  f32
}

// calculate_fit_to_window scales and centers an image to maximally fill the canvas
// while preserving aspect ratio.
pub fn calculate_fit_to_window(canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	if canvas_w <= 0 || canvas_h <= 0 || img_w <= 0 || img_h <= 0 {
		return Viewport{
			x:      0
			y:      0
			width:  0
			height: 0
			scale:  1.0
		}
	}

	scale_w := f32(canvas_w) / f32(img_w)
	scale_h := f32(canvas_h) / f32(img_h)
	scale := math.min(scale_w, scale_h)

	w := f32(img_w) * scale
	h := f32(img_h) * scale
	x := (f32(canvas_w) - w) / 2.0
	y := (f32(canvas_h) - h) / 2.0

	return Viewport{
		x:      x
		y:      y
		width:  w
		height: h
		scale:  scale
	}
}

// calculate_actual_size sets zoom magnification to exactly 1:1, centered.
pub fn calculate_actual_size(canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	if canvas_w <= 0 || canvas_h <= 0 || img_w <= 0 || img_h <= 0 {
		return Viewport{
			x:      0
			y:      0
			width:  0
			height: 0
			scale:  1.0
		}
	}

	w := f32(img_w)
	h := f32(img_h)
	x := (f32(canvas_w) - w) / 2.0
	y := (f32(canvas_h) - h) / 2.0

	return Viewport{
		x:      x
		y:      y
		width:  w
		height: h
		scale:  1.0
	}
}

// calculate_initial_viewport determines the initial viewport layout when an image is loaded.
// Small images are displayed at actual size (1:1) centered; images exceeding canvas bounds
// are scaled down via fit-to-window while preserving aspect ratio.
pub fn calculate_initial_viewport(canvas_w int, canvas_h int, img_w int, img_h int) Viewport {
	if canvas_w <= 0 || canvas_h <= 0 || img_w <= 0 || img_h <= 0 {
		return Viewport{
			x:      0
			y:      0
			width:  0
			height: 0
			scale:  1.0
		}
	}

	if img_w <= canvas_w && img_h <= canvas_h {
		return calculate_actual_size(canvas_w, canvas_h, img_w, img_h)
	}

	return calculate_fit_to_window(canvas_w, canvas_h, img_w, img_h)
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
