module main

import math
import ui2

pub const default_checker_size = f32(16.0)

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

pub fn compute_visible_checkerboard_cells(x f32, y f32, w f32, h f32, cell_size f32, canvas_w int, canvas_h int) []CheckerCell {
	if w <= 0 || h <= 0 || cell_size <= 0 || canvas_w <= 0 || canvas_h <= 0 {
		return []
	}

	vis_x0 := math.max(f32(0.0), x)
	vis_y0 := math.max(f32(0.0), y)
	vis_x1 := math.min(f32(canvas_w), x + w)
	vis_y1 := math.min(f32(canvas_h), y + h)
	if vis_x0 >= vis_x1 || vis_y0 >= vis_y1 {
		return []
	}

	start_col := int(math.floor((vis_x0 - x) / cell_size))
	start_row := int(math.floor((vis_y0 - y) / cell_size))
	mut cells := []CheckerCell{}
	mut cur_y := y + f32(start_row) * cell_size
	mut row := start_row

	for cur_y < vis_y1 {
		cell_y0 := math.max(vis_y0, cur_y)
		cell_y1 := math.min(vis_y1, cur_y + cell_size)
		cell_h := cell_y1 - cell_y0
		mut cur_x := x + f32(start_col) * cell_size
		mut col := start_col

		for cur_x < vis_x1 {
			cell_x0 := math.max(vis_x0, cur_x)
			cell_x1 := math.min(vis_x1, cur_x + cell_size)
			cell_w := cell_x1 - cell_x0
			cells << CheckerCell{
				x:      cell_x0
				y:      cell_y0
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

pub fn checkerboard_pattern() ui2.RepeatPattern {
	cell_size := int(default_checker_size)
	tile_size := cell_size * 2
	mut pixels := []u8{len: tile_size * tile_size * 4, init: 255}
	for y in 0 .. tile_size {
		for x in 0 .. tile_size {
			color := if (x / cell_size + y / cell_size) % 2 == 1 {
				checker_light_hex
			} else {
				checker_dark_hex
			}
			offset := (y * tile_size + x) * 4
			pixels[offset] = u8((color >> 16) & 0xff)
			pixels[offset + 1] = u8((color >> 8) & 0xff)
			pixels[offset + 2] = u8(color & 0xff)
			pixels[offset + 3] = 255
		}
	}
	return ui2.RepeatPattern{
		id:           'viewer-transparency-tile-v1'
		tile_width:   f64(tile_size)
		tile_height:  f64(tile_size)
		pixel_width:  tile_size
		pixel_height: tile_size
		channels:     4
		pixels:       pixels
		origin_x:     0
		origin_y:     0
	}
}

pub fn checkerboard_reveal_rect(vp Viewport) ui2.Rect {
	return ui2.rect(f64(vp.x), f64(vp.y), f64(vp.width), f64(vp.height))
}
