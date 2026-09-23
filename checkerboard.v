module main

import math

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
