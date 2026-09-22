module main

// App represents the headless application controller and state machine.
// It maintains playlist, image metadata, and viewport transformation state
// without requiring an active OpenGL/Wayland display server.
pub struct App {
pub mut:
	target_path   string
	has_image     bool
	img_width     int
	img_height    int
	viewport      Viewport
	canvas_w      int
	canvas_h      int
	error_msg     string
	filter_mode   TextureFilterMode = .linear
	viewport_init bool
}

// new_app initializes a new headless App instance.
pub fn new_app() App {
	return App{
		filter_mode: .linear
	}
}

// set_canvas_size updates the canvas dimensions and initializes viewport if needed.
pub fn (mut app App) set_canvas_size(w int, h int) {
	app.canvas_w = w
	app.canvas_h = h
	if app.has_image && !app.viewport_init && w > 0 && h > 0 {
		app.reset_viewport()
	}
}

// set_image_loaded updates image metadata and resets viewport to initial fit.
pub fn (mut app App) set_image_loaded(path string, w int, h int) {
	app.target_path = path
	app.has_image = true
	app.img_width = w
	app.img_height = h
	app.error_msg = ''
	app.viewport_init = false

	if app.canvas_w > 0 && app.canvas_h > 0 {
		app.reset_viewport()
	}
}

// set_error registers a file load or system failure.
pub fn (mut app App) set_error(path string, msg string) {
	app.target_path = path
	app.has_image = false
	app.img_width = 0
	app.img_height = 0
	app.error_msg = msg
	app.viewport_init = false
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

// zoom_at zooms continuously centered on the specified canvas cursor coordinates.
pub fn (mut app App) zoom_at(cursor_x f32, cursor_y f32, factor f32) {
	if !app.has_image || app.viewport.scale <= 0 {
		return
	}
	target_scale := app.viewport.scale * factor
	new_vp := zoom_at(app.viewport, cursor_x, cursor_y, target_scale)
	app.viewport = constrain_pan(new_vp, app.canvas_w, app.canvas_h)
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
		flip_h:   app.viewport.flip_h
		flip_v:   app.viewport.flip_v
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
