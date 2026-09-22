module main

pub const default_checker_size = f32(16.0)

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
