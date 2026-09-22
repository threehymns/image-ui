module main

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
