module main

import math
import os
import ui2

pub const default_checker_size = f32(16.0)

// Subtle neutral colors for alpha checkerboard rendering, as ui2 hex.
// Matches legacy gg colors (dark 36,36,38 / light 48,48,52).
pub const checker_dark_hex = u32(0x242426)
pub const checker_light_hex = u32(0x303034)

pub struct CheckerCell {
pub:
	x      f32
	y      f32
	width  f32
	height f32
	is_alt bool
}

// compute_checkerboard_cells calculates the geometry and alternating state of cells
// within a given rectangle. Pure and headless-testable.
pub fn compute_checkerboard_cells(x f32, y f32, w f32, h f32, cell_size f32) []CheckerCell {
	if w <= 0 || h <= 0 || cell_size <= 0 {
		return []
	}

	mut cells := []CheckerCell{}
	mut cur_y := y
	mut row := 0

	for cur_y < y + h {
		cell_h := if cur_y + cell_size > y + h { y + h - cur_y } else { cell_size }
		mut cur_x := x
		mut col := 0

		for cur_x < x + w {
			cell_w := if cur_x + cell_size > x + w { x + w - cur_x } else { cell_size }
			cells << CheckerCell{
				x:      cur_x
				y:      cur_y
				width:  cell_w
				height: cell_h
				is_alt: (row + col) % 2 == 1
			}
			cur_x += cell_size
			col++
		}

		cur_y += cell_size
		row++
	}

	return cells
}

// compute_visible_checkerboard_cells calculates checkerboard cells strictly clipped
// to the visible canvas area [0, 0, canvas_w, canvas_h]. This guarantees that cell count
// and vertex generation remain bounded regardless of zoom magnification.
pub fn compute_visible_checkerboard_cells(x f32, y f32, w f32, h f32, cell_size f32, canvas_w int, canvas_h int) []CheckerCell {
	if w <= 0 || h <= 0 || cell_size <= 0 || canvas_w <= 0 || canvas_h <= 0 {
		return []
	}
	sz := cell_size

	vis_x0 := math.max(f32(0.0), x)
	vis_y0 := math.max(f32(0.0), y)
	vis_x1 := math.min(f32(canvas_w), x + w)
	vis_y1 := math.min(f32(canvas_h), y + h)

	if vis_x0 >= vis_x1 || vis_y0 >= vis_y1 {
		return []
	}

	start_col := int(math.floor((vis_x0 - x) / sz))
	start_row := int(math.floor((vis_y0 - y) / sz))

	mut cells := []CheckerCell{}
	mut cur_y := y + f32(start_row) * sz
	mut row := start_row

	for cur_y < vis_y1 {
		cell_y0 := math.max(vis_y0, cur_y)
		cell_y1 := math.min(vis_y1, cur_y + sz)
		cell_h := cell_y1 - cell_y0

		mut cur_x := x + f32(start_col) * sz
		mut col := start_col

		for cur_x < vis_x1 {
			cell_x0 := math.max(vis_x0, cur_x)
			cell_x1 := math.min(vis_x1, cur_x + sz)
			cell_w := cell_x1 - cell_x0

			cells << CheckerCell{
				x:      cell_x0
				y:      cell_y0
				width:  cell_w
				height: cell_h
				is_alt: (row + col) % 2 == 1
			}

			cur_x += sz
			col++
		}

		cur_y += sz
		row++
	}

	return cells
}

// checkerboard_elements builds ui2 view elements rendering the subtle neutral
// checkerboard grid clipped to the visible canvas. The first element is the
// dark base covering the visible image bounds; subsequent elements are the
// alternating lighter tiles. Frames are absolute screen coordinates, matching
// the canvas_bg parent at origin. Returns empty when disabled dimensions occur.
pub fn checkerboard_elements(vp Viewport, canvas_w int, canvas_h int, cell_size f32) []ui2.Element {
	if vp.width <= 0 || vp.height <= 0 || canvas_w <= 0 || canvas_h <= 0 {
		return []
	}
	sz := if cell_size > 0 { cell_size } else { default_checker_size }

	vis_x0 := math.max(f32(0.0), vp.x)
	vis_y0 := math.max(f32(0.0), vp.y)
	vis_x1 := math.min(f32(canvas_w), vp.x + vp.width)
	vis_y1 := math.min(f32(canvas_h), vp.y + vp.height)
	if vis_x0 >= vis_x1 || vis_y0 >= vis_y1 {
		return []
	}

	mut els := []ui2.Element{}
	els << ui2.view('checker_base', ui2.rect(f64(vis_x0), f64(vis_y0), f64(vis_x1 - vis_x0),
		f64(vis_y1 - vis_y0)), ui2.BoxStyle{
		bg: checker_dark_hex
	}, [])

	cells := compute_visible_checkerboard_cells(vp.x, vp.y, vp.width, vp.height, sz,
		canvas_w, canvas_h)
	mut alt_idx := 0
	for c in cells {
		if !c.is_alt {
			continue
		}
		els << ui2.view('checker_alt_${alt_idx}', ui2.rect(f64(c.x), f64(c.y), f64(c.width),
			f64(c.height)), ui2.BoxStyle{
			bg: checker_light_hex
		}, [])
		alt_idx++
	}
	return els
}

fn put_u16_le(mut data []u8, offset int, value int) {
	data[offset] = u8(value & 0xff)
	data[offset + 1] = u8((value >> 8) & 0xff)
}

fn put_u32_le(mut data []u8, offset int, value int) {
	data[offset] = u8(value & 0xff)
	data[offset + 1] = u8((value >> 8) & 0xff)
	data[offset + 2] = u8((value >> 16) & 0xff)
	data[offset + 3] = u8((value >> 24) & 0xff)
}

fn encode_checkerboard_bmp(canvas_w int, canvas_h int) []u8 {
	row_size := ((canvas_w * 3 + 3) / 4) * 4
	pixel_bytes := row_size * canvas_h
	mut data := []u8{len: 54 + pixel_bytes}
	data[0] = `B`
	data[1] = `M`
	put_u32_le(mut data, 2, data.len)
	put_u32_le(mut data, 10, 54)
	put_u32_le(mut data, 14, 40)
	put_u32_le(mut data, 18, canvas_w)
	put_u32_le(mut data, 22, canvas_h)
	put_u16_le(mut data, 26, 1)
	put_u16_le(mut data, 28, 24)
	put_u32_le(mut data, 34, pixel_bytes)

	mut offset := 54
	for row in 0 .. canvas_h {
		y := canvas_h - row - 1
		for x in 0 .. canvas_w {
			color := if (x / int(default_checker_size) + y / int(default_checker_size)) % 2 == 1 {
				checker_light_hex
			} else {
				checker_dark_hex
			}
			data[offset] = u8(color & 0xff)
			data[offset + 1] = u8((color >> 8) & 0xff)
			data[offset + 2] = u8((color >> 16) & 0xff)
			offset += 3
		}
		offset += row_size - canvas_w * 3
	}
	return data
}

fn checkerboard_bmp_path(canvas_w int, canvas_h int) string {
	return os.join_path(os.temp_dir(), 'image-ui-checkerboard-v1-${canvas_w}x${canvas_h}.bmp')
}

pub fn build_checkerboard_layer(canvas_w int, canvas_h int) ui2.Element {
	path := checkerboard_bmp_path(canvas_w, canvas_h)
	if !os.exists(path) {
		os.write_bytes(path, encode_checkerboard_bmp(canvas_w, canvas_h)) or {
			return ui2.view('checkerboard_layer', ui2.rect(0, 0, f64(canvas_w), f64(canvas_h)),
				ui2.BoxStyle{ transparent: true }, [])
		}
	}
	return ui2.image('checkerboard_layer', path, ui2.rect(0, 0, f64(canvas_w), f64(canvas_h)))
}

pub fn checkerboard_mask_elements(vp Viewport, canvas_w int, canvas_h int) []ui2.Element {
	if vp.width <= 0 || vp.height <= 0 || canvas_w <= 0 || canvas_h <= 0 {
		return []
	}
	vis_x0 := math.max(f32(0.0), vp.x)
	vis_y0 := math.max(f32(0.0), vp.y)
	vis_x1 := math.min(f32(canvas_w), vp.x + vp.width)
	vis_y1 := math.min(f32(canvas_h), vp.y + vp.height)
	if vis_x0 >= vis_x1 || vis_y0 >= vis_y1 {
		return []
	}

	mut masks := []ui2.Element{}
	if vis_y0 > 0 {
		masks << ui2.view('checker_mask_top', ui2.rect(0, 0, f64(canvas_w), f64(vis_y0)),
			ui2.BoxStyle{ bg: canvas_bg_hex }, [])
	}
	if vis_y1 < f32(canvas_h) {
		masks << ui2.view('checker_mask_bottom', ui2.rect(0, f64(vis_y1), f64(canvas_w),
			f64(f32(canvas_h) - vis_y1)), ui2.BoxStyle{ bg: canvas_bg_hex }, [])
	}
	if vis_x0 > 0 {
		masks << ui2.view('checker_mask_left', ui2.rect(0, f64(vis_y0), f64(vis_x0),
			f64(vis_y1 - vis_y0)), ui2.BoxStyle{ bg: canvas_bg_hex }, [])
	}
	if vis_x1 < f32(canvas_w) {
		masks << ui2.view('checker_mask_right', ui2.rect(f64(vis_x1), f64(vis_y0),
			f64(f32(canvas_w) - vis_x1), f64(vis_y1 - vis_y0)), ui2.BoxStyle{ bg: canvas_bg_hex }, [])
	}
	return masks
}
