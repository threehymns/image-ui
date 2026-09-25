module main

import ui2

fn reference_composite_pixel(red u8, green u8, blue u8, alpha u8, background u32) u32 {
	mut source := [red, green, blue]
	mut result := u32(0)
	for index in 0 .. 3 {
		channel := int(source[index]) * int(alpha) + int((background >> u32((2 - index) * 8)) & 0xff) * (255 - int(alpha))
		result |= u32((channel + 127) / 255) << u32((2 - index) * 8)
	}
	return result
}

fn visual_test_resource(opacity ui2.ImageOpacity) ui2.ImageResource {
	return ui2.ready_image_resource('visual-resource', 'visual.png', ui2.ImageResourceInput{
		width:    2
		height:   2
		channels: 4
		pixels:   []u8{len: 16, init: 255}
	}, opacity)
}

fn test_visual_checkerboard_phase_is_window_anchored_across_geometry() {
	pattern := checkerboard_pattern()
	first := pattern.phase(ui2.rect(100, 50, 64, 48))
	second := pattern.phase(ui2.rect(132, 82, 128, 96))
	assert first.x == 28
	assert first.y == 14
	assert second.x == first.x
	assert second.y == first.y
	assert pattern.source_rect(ui2.rect(100, 50, 64, 48)) == ui2.rect(100, 50, 64, 48)
	assert pattern.source_rect(ui2.rect(132, 82, 128, 96)) == ui2.rect(132, 82, 128, 96)
}

fn test_visual_checkerboard_clipping_tracks_image_reveal_and_resize() {
	pattern := checkerboard_pattern()
	clip := ui2.rect(-32, 24, 96, 80)
	background := ui2.pattern_background('visual-pattern', pattern, clip).background
	assert background.visible_rect(0, 0, clip, ui2.rect(0, 0, 64, 64)) == ui2.rect(0, 24, 64, 40)
	resized := ui2.pattern_background('visual-pattern', pattern, ui2.rect(32, 8, 96, 80))
	assert resized.background.pattern.id == pattern.id
	assert resized.background.clip == resized.frame
}

fn test_visual_alpha_compositing_reference_is_deterministic() {
	transparent := reference_composite_pixel(255, 0, 0, 0, checker_dark_hex)
	assert transparent == checker_dark_hex
	opaque := reference_composite_pixel(255, 0, 0, 255, checker_dark_hex)
	assert opaque == 0xff0000
	blended := reference_composite_pixel(255, 0, 0, 128, checker_dark_hex)
	assert (blended >> 16) & 0xff >= 140
	assert (blended >> 16) & 0xff <= 150
	assert (blended >> 8) & 0xff >= 10
	assert (blended >> 8) & 0xff <= 20
	assert blended & 0xff >= 10
	assert blended & 0xff <= 20
}

fn test_visual_transform_contract_preserves_resource_and_sampling_flags() {
	resource := visual_test_resource(.has_alpha)
	mut element := ui2.transformed_image_resource('visual-image', resource, ui2.rect(10, 20, 40, 20), 90, false)
	element = ui2.with_flip_h(element)
	element = ui2.with_flip_v(element)
	element = ui2.with_pixelated(element)
	assert element.image_resource.id == resource.id
	assert element.rotation == 90
	assert element.flip_h
	assert element.flip_v
	assert element.pixelated
	assert ui2.transformed_image_bounds(element.frame, element.rotation) == ui2.rect(20, 10, 20, 40)
	flip_x, flip_y := ui2.image_texture_flips(element.rotation, element.flip_h, element.flip_v)
	assert flip_x
	assert flip_y
}

fn test_visual_viewer_resize_reuses_pattern_and_preserves_transform_state() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.window_ready = true
	app.core.set_canvas_size(800, 600)
	app.core.set_image_resource(visual_test_resource(.has_alpha))
	app.core.zoom_in()
	app.core.pan(24, 18)
	app.core.rotate_cw()
	app.core.flip_h()
	first := app.build_screen_at_size(800, 600)
	app.core.set_canvas_size(1024, 768)
	second := app.build_screen_at_size(1024, 768)
	assert first.children[0].background.pattern.id == second.children[0].background.pattern.id
	assert first.children[0].background.pattern.pixels == second.children[0].background.pattern.pixels
	assert second.children[0].background.clip == second.children[0].frame
	assert second.children[0].frame.x >= -10000.0
	image := second.children[1].children[0]
	assert image.rotation == 90
	assert image.flip_h
}
