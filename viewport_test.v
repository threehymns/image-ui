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
	// scale_w = 960 / 1920 = 0.5
	// scale_h = 1000 / 1080 = 0.9259
	// scale = 0.5
	vp := calculate_fit_to_window(960, 1000, 1920, 1080)
	assert math.abs(vp.scale - 0.5) < 0.001
	assert math.abs(vp.width - 960) < 0.001
	assert math.abs(vp.height - 540) < 0.001
	assert math.abs(vp.x - 0) < 0.001
	assert math.abs(vp.y - (1000 - 540) / 2.0) < 0.001
}

fn test_viewport_fit_to_window_aspect_ratio_tall() {
	// Image 1000x2000 on canvas 800x1000
	// scale_w = 800 / 1000 = 0.8
	// scale_h = 1000 / 2000 = 0.5
	// scale = 0.5
	vp := calculate_fit_to_window(800, 1000, 1000, 2000)
	assert math.abs(vp.scale - 0.5) < 0.001
	assert math.abs(vp.width - 500) < 0.001
	assert math.abs(vp.height - 1000) < 0.001
	assert math.abs(vp.x - (800 - 500) / 2.0) < 0.001
	assert math.abs(vp.y - 0) < 0.001
}
