module main

import os

// App represents the headless application controller and state machine.
// It maintains playlist, image metadata, and viewport transformation state
// without requiring an active OpenGL/Wayland display server.
pub struct App {
pub mut:
	target_path       string
	has_image         bool
	img_width         int
	img_height        int
	viewport          Viewport
	canvas_w          int
	canvas_h          int
	error_msg         string
	filter_mode       TextureFilterMode = .linear
	viewport_init     bool
	show_checkerboard bool = true
	// Sibling playlist and traversal state
	playlist          []string
	active_index      int
	is_scanning       bool
	scan_complete     bool
	scan_generation   int
	has_first_content bool
}

// new_app initializes a new headless App instance.
pub fn new_app() App {
	return App{
		filter_mode:       .linear
		show_checkerboard: true
	}
}

fn clamp_int(val int, min int, max int) int {
	if val < min {
		return min
	}
	if val > max {
		return max
	}
	return val
}

// set_canvas_size updates the canvas dimensions and initializes viewport if needed.
// If the canvas size changes while the viewport still holds its pristine
// auto-computed initial value (no user transform yet), the viewport is
// recomputed for the new size. This covers the first-frame preload where
// the viewport is initialized with fallback bounds before the real window
// size is known, ensuring the first image opens centered.
pub fn (mut app App) set_canvas_size(w int, h int) {
	old_w := app.canvas_w
	old_h := app.canvas_h
	app.canvas_w = w
	app.canvas_h = h
	if !app.has_image || w <= 0 || h <= 0 {
		return
	}
	if !app.viewport_init {
		app.reset_viewport()
		return
	}
	if (w == old_w && h == old_h) || old_w <= 0 || old_h <= 0 {
		return
	}
	// Only auto-reset pristine viewports; preserve any user transform.
	if app.viewport.rotation != 0 || app.viewport.flip_h || app.viewport.flip_v {
		return
	}
	expected := calculate_initial_viewport_rotated(old_w, old_h, app.img_width, app.img_height, 0)
	if app.viewport.x == expected.x && app.viewport.y == expected.y
		&& app.viewport.width == expected.width && app.viewport.height == expected.height
		&& app.viewport.scale == expected.scale {
		app.reset_viewport()
	}
}

// set_image_loaded updates image metadata and resets viewport to initial fit.
pub fn (mut app App) set_image_loaded(path string, w int, h int) {
	app.target_path = path
	app.has_image = true
	app.has_first_content = true
	app.img_width = w
	app.img_height = h
	app.error_msg = ''
	app.viewport_init = false

	if app.playlist.len == 0 && path != '' {
		app.playlist = [path]
		app.active_index = 0
	} else if path != '' {
		for i, p in app.playlist {
			if p == path || os.file_name(p) == os.file_name(path) {
				app.active_index = i
				break
			}
		}
	}

	if app.canvas_w > 0 && app.canvas_h > 0 {
		app.reset_viewport()
	}
}

// set_error registers a file load or system failure.
pub fn (mut app App) set_error(path string, msg string) {
	app.target_path = path
	app.has_image = false
	app.has_first_content = false
	app.img_width = 0
	app.img_height = 0
	app.error_msg = msg
	app.viewport_init = false
}

fn (mut app App) invalidate_scan() {
	app.scan_generation++
}

fn (mut app App) begin_scan(generation int) {
	if generation > app.scan_generation {
		app.scan_generation = generation
	}
	app.is_scanning = true
	app.scan_complete = false
}

fn (app &App) accepts_batch(batch SiblingBatch) bool {
	return batch.generation == app.scan_generation
}

fn merge_sorted_paths(current []string, incoming []string) []string {
	mut result := []string{}
	mut seen := map[string]bool{}
	mut current_index := 0
	mut incoming_index := 0
	for current_index < current.len || incoming_index < incoming.len {
		mut item := ''
		if incoming_index >= incoming.len {
			item = current[current_index]
			current_index++
		} else if current_index >= current.len {
			item = incoming[incoming_index]
			incoming_index++
		} else if natural_compare_paths(current[current_index], incoming[incoming_index]) <= 0 {
			item = current[current_index]
			current_index++
		} else {
			item = incoming[incoming_index]
			incoming_index++
		}
		if !seen[item] {
			result << item
			seen[item] = true
		}
	}
	return result
}

// open_path opens a target image file or directory.
pub fn (mut app App) open_path(path string) {
	app.invalidate_scan()
	app.target_path = path
	app.has_image = false
	app.has_first_content = false
	app.img_width = 0
	app.img_height = 0
	app.playlist = []
	app.active_index = 0
	app.error_msg = ''
	app.is_scanning = false
	app.scan_complete = false

	if path == '' {
		return
	}

	if os.is_dir(path) {
		app.is_scanning = true
		return
	}

	app.playlist = [path]
	app.is_scanning = true
}

// integrate_batch merges streamed sibling scanner batches into the playlist,
// ensuring natural sort order and preserving the active image pointer.
pub fn (mut app App) integrate_batch(batch SiblingBatch) {
	if !app.accepts_batch(batch) {
		return
	}
	if batch.items.len == 0 {
		if batch.is_last {
			app.is_scanning = false
			app.scan_complete = true
		}
		return
	}

	current_active := if app.active_index >= 0 && app.active_index < app.playlist.len {
		app.playlist[app.active_index]
	} else {
		app.target_path
	}
	mut incoming := batch.items.clone()
	natural_sort(mut incoming)
	had_playlist := app.playlist.len > 0
	app.playlist = merge_sorted_paths(app.playlist, incoming)
	if batch.is_first_content || batch.is_neighborhood || !had_playlist {
		app.has_first_content = true
	}

	mut new_idx := -1
	for i, p in app.playlist {
		if p == current_active || (current_active != '' && os.file_name(p) == os.file_name(current_active)) {
			new_idx = i
			break
		}
	}
	if new_idx >= 0 {
		app.active_index = new_idx
		app.target_path = app.playlist[new_idx]
	} else if app.playlist.len > 0 {
		app.active_index = clamp_int(app.active_index, 0, app.playlist.len - 1)
		app.target_path = app.playlist[app.active_index]
	}

	if batch.is_last {
		app.is_scanning = false
		app.scan_complete = true
	} else {
		app.is_scanning = true
		app.scan_complete = false
	}
}

// step_sibling navigates the playlist by delta steps (e.g. +1, -1, +10, -10).
// Returns true if navigation changed the active image.
pub fn (mut app App) step_sibling(delta int) bool {
	if app.playlist.len <= 1 || delta == 0 {
		return false
	}
	target_idx := clamp_int(app.active_index + delta, 0, app.playlist.len - 1)
	if target_idx == app.active_index {
		return false
	}
	app.active_index = target_idx
	app.target_path = app.playlist[target_idx]
	app.viewport_init = false
	return true
}

// next_sibling steps forward to the adjacent next sibling (+1).
pub fn (mut app App) next_sibling() bool {
	return app.step_sibling(1)
}

// prev_sibling steps backward to the adjacent previous sibling (-1).
pub fn (mut app App) prev_sibling() bool {
	return app.step_sibling(-1)
}

// next_secondary_step steps forward by secondary navigation chunk (+10).
pub fn (mut app App) next_secondary_step() bool {
	return app.step_sibling(10)
}

// prev_secondary_step steps backward by secondary navigation chunk (-10).
pub fn (mut app App) prev_secondary_step() bool {
	return app.step_sibling(-10)
}

// sibling_count returns total number of images currently discovered in the playlist.
pub fn (app &App) sibling_count() int {
	return app.playlist.len
}

// active_sibling_path returns the file path of the currently active sibling image.
pub fn (app &App) active_sibling_path() string {
	if app.active_index >= 0 && app.active_index < app.playlist.len {
		return app.playlist[app.active_index]
	}
	return app.target_path
}

// reset_viewport computes the initial fit/actual-size viewport for the current image.
pub fn (mut app App) reset_viewport() {
	if !app.has_image || app.canvas_w <= 0 || app.canvas_h <= 0 {
		return
	}
	app.viewport = calculate_initial_viewport_rotated(app.canvas_w, app.canvas_h, app.img_width, app.img_height, 0)
	app.filter_mode = get_texture_filter_for_scale(app.viewport.scale, .linear)
	app.viewport_init = true
}

// zoom_at zooms continuously centered on the specified canvas cursor coordinates,
// ensuring the image point under (cursor_x, cursor_y) remains invariant.
pub fn (mut app App) zoom_at(cursor_x f32, cursor_y f32, factor f32) {
	if !app.has_image || app.viewport.scale <= 0 {
		return
	}
	target_scale := app.viewport.scale * factor
	app.viewport = zoom_at(app.viewport, cursor_x, cursor_y, target_scale)
	app.filter_mode = get_texture_filter_for_scale(app.viewport.scale, app.filter_mode)
}

// zoom_in zooms in centered at canvas midpoint.
pub fn (mut app App) zoom_in() {
	app.zoom_at(f32(app.canvas_w) / 2.0, f32(app.canvas_h) / 2.0, zoom_step_factor)
}

// zoom_out zooms out centered at canvas midpoint.
pub fn (mut app App) zoom_out() {
	app.zoom_at(f32(app.canvas_w) / 2.0, f32(app.canvas_h) / 2.0, 1.0 / zoom_step_factor)
}

// zoom_actual sets scale to 1:1 physical pixel mapping, keeping rotation and flip.
pub fn (mut app App) zoom_actual() {
	if !app.has_image {
		return
	}
	act_vp := calculate_actual_size_rotated(app.canvas_w, app.canvas_h, app.img_width, app.img_height, app.viewport.rotation)
	app.viewport = Viewport{
		x:        act_vp.x
		y:        act_vp.y
		width:    act_vp.width
		height:   act_vp.height
		scale:    act_vp.scale
		rotation: app.viewport.rotation
		flip_h:   app.viewport.flip_h
		flip_v:   app.viewport.flip_v
	}
	app.filter_mode = get_texture_filter_for_scale(app.viewport.scale, app.filter_mode)
}

// zoom_fit sets scale to maximally fit window, keeping rotation and flip.
pub fn (mut app App) zoom_fit() {
	if !app.has_image {
		return
	}
	fit_vp := calculate_fit_to_window_rotated(app.canvas_w, app.canvas_h, app.img_width, app.img_height, app.viewport.rotation)
	app.viewport = Viewport{
		x:        fit_vp.x
		y:        fit_vp.y
		width:    fit_vp.width
		height:   fit_vp.height
		scale:    fit_vp.scale
		rotation: app.viewport.rotation
		flip_h:   fit_vp.flip_h
		flip_v:   fit_vp.flip_v
	}
	app.filter_mode = get_texture_filter_for_scale(app.viewport.scale, app.filter_mode)
}

// toggle_zoom_fit_actual toggles between Fit to Window and Actual Size.
pub fn (mut app App) toggle_zoom_fit_actual() {
	if !app.has_image {
		return
	}
	app.viewport = toggle_fit_or_actual(app.viewport, app.canvas_w, app.canvas_h, app.img_width, app.img_height)
	app.filter_mode = get_texture_filter_for_scale(app.viewport.scale, app.filter_mode)
}

// pan shifts the viewport position by (dx, dy), clamped to window boundaries.
pub fn (mut app App) pan(dx f32, dy f32) {
	if !app.has_image {
		return
	}
	app.viewport = pan(app.viewport, dx, dy, app.canvas_w, app.canvas_h)
}

// rotate_cw rotates 90 degrees clockwise in place.
pub fn (mut app App) rotate_cw() {
	if !app.has_image {
		return
	}
	app.viewport = rotate_cw(app.viewport, app.canvas_w, app.canvas_h)
}

// rotate_ccw rotates 90 degrees counter-clockwise in place.
pub fn (mut app App) rotate_ccw() {
	if !app.has_image {
		return
	}
	app.viewport = rotate_ccw(app.viewport, app.canvas_w, app.canvas_h)
}

// flip_h toggles horizontal mirroring.
pub fn (mut app App) flip_h() {
	if !app.has_image {
		return
	}
	app.viewport = flip_horizontal(app.viewport)
}

// flip_v toggles vertical mirroring.
pub fn (mut app App) flip_v() {
	if !app.has_image {
		return
	}
	app.viewport = flip_vertical(app.viewport)
}

// toggle_checkerboard flips the transparency grid behind the image.
pub fn (mut app App) toggle_checkerboard() {
	app.show_checkerboard = !app.show_checkerboard
}
