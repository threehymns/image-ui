module main

import os
import math
import time
import ui
import gg
import sokol.sapp
import sokol.gfx

// Subtle neutral colors for alpha checkerboard rendering
pub const checker_color_dark = gg.Color{
	r: 36
	g: 36
	b: 38
	a: 255
}

pub const checker_color_light = gg.Color{
	r: 48
	g: 48
	b: 52
	a: 255
}

// Background for the canvas area outside the image
pub const canvas_bg_color = gg.Color{
	r: 20
	g: 20
	b: 22
	a: 255
}

// Drop target frame and text styling colors
pub const drop_target_border_color = gg.Color{
	r: 52
	g: 52
	b: 58
	a: 255
}

pub const drop_target_text_color = gg.Color{
	r: 160
	g: 160
	b: 168
	a: 255
}

pub const drop_target_subtext_color = gg.Color{
	r: 100
	g: 100
	b: 108
	a: 255
}

pub const error_text_color = gg.Color{
	r: 220
	g: 90
	b: 90
	a: 255
}

@[heap]
pub struct ViewerApp {
pub mut:
	window          &ui.Window = unsafe { nil }
	core            App
	image           gg.Image
	sampler_linear  gfx.Sampler
	sampler_nearest gfx.Sampler
	samplers_init   bool
	is_dragging     bool
	drag_prev_x     f32
	drag_prev_y     f32
	last_click_time i64
	last_click_x    f32
	last_click_y    f32
}

// init_samplers allocates bilinear and nearest-neighbor Sokol samplers.
pub fn (mut app ViewerApp) init_samplers() {
	if app.samplers_init {
		return
	}
	mut smp_linear := gfx.SamplerDesc{
		min_filter:    .linear
		mag_filter:    .linear
		mipmap_filter: .linear
		wrap_u:        .clamp_to_edge
		wrap_v:        .clamp_to_edge
	}
	app.sampler_linear = gfx.make_sampler(&smp_linear)

	mut smp_nearest := gfx.SamplerDesc{
		min_filter:    .nearest
		mag_filter:    .nearest
		mipmap_filter: .linear
		wrap_u:        .clamp_to_edge
		wrap_v:        .clamp_to_edge
	}
	app.sampler_nearest = gfx.make_sampler(&smp_nearest)
	app.samplers_init = true
}

// draw_checkerboard renders the subtle neutral checkerboard grid clipped to visible canvas.
pub fn draw_checkerboard(ctx &gg.Context, x f32, y f32, w f32, h f32, cell_size f32, canvas_w int, canvas_h int) {
	if w <= 0 || h <= 0 || canvas_w <= 0 || canvas_h <= 0 {
		return
	}
	sz := if cell_size > 0 { cell_size } else { default_checker_size }

	// Calculate intersection of image bounds and visible canvas area
	vis_x0 := math.max(f32(0.0), x)
	vis_y0 := math.max(f32(0.0), y)
	vis_x1 := math.min(f32(canvas_w), x + w)
	vis_y1 := math.min(f32(canvas_h), y + h)

	if vis_x0 >= vis_x1 || vis_y0 >= vis_y1 {
		return
	}

	// Draw base dark neutral rectangle covering only the visible portion of the image
	ctx.draw_rect_filled(vis_x0, vis_y0, vis_x1 - vis_x0, vis_y1 - vis_y0, checker_color_dark)

	// Draw alternating lighter tiles clipped at the boundary
	start_col := int(math.floor((vis_x0 - x) / sz))
	start_row := int(math.floor((vis_y0 - y) / sz))

	mut cur_y := y + f32(start_row) * sz
	mut row := start_row
	for cur_y < vis_y1 {
		cell_y0 := math.max(vis_y0, cur_y)
		cell_y1 := math.min(vis_y1, cur_y + sz)
		cell_h := cell_y1 - cell_y0

		mut cur_x := x + f32(start_col) * sz
		mut col := start_col
		for cur_x < vis_x1 {
			if (row + col) % 2 != 0 {
				cell_x0 := math.max(vis_x0, cur_x)
				cell_x1 := math.min(vis_x1, cur_x + sz)
				cell_w := cell_x1 - cell_x0
				ctx.draw_rect_filled(cell_x0, cell_y0, cell_w, cell_h, checker_color_light)
			}
			cur_x += sz
			col++
		}
		cur_y += sz
		row++
	}
}

pub fn (mut app ViewerApp) load_image(path string) {
	if path == '' {
		app.core.set_error('', '')
		if app.window != unsafe { nil } {
			app.window.set_title(format_window_title('', 0, 0))
			app.window.refresh()
		}
		return
	}

	if !os.exists(path) {
		app.core.set_error(path, 'File not found: ${path}')
		if app.window != unsafe { nil } {
			app.window.set_title(format_window_title('', 0, 0))
			app.window.refresh()
		}
		return
	}

	mut gg_ctx := app.window.ui.gg
	loaded_img := gg_ctx.create_image(path) or {
		app.core.set_error(path, 'Unable to load image: ${err.msg()}')
		if app.window != unsafe { nil } {
			app.window.set_title(format_window_title('', 0, 0))
			app.window.refresh()
		}
		return
	}

	app.image = loaded_img
	app.core.set_image_loaded(path, loaded_img.width, loaded_img.height)

	if app.window != unsafe { nil } {
		app.window.set_title(format_window_title(path, loaded_img.width, loaded_img.height))
		app.window.refresh()
	}
}

pub fn (mut app ViewerApp) win_init(w &ui.Window) {
	app.window = unsafe { w }
	if app.core.target_path != '' {
		app.load_image(app.core.target_path)
	} else {
		app.window.set_title(format_window_title('', 0, 0))
	}
}

pub fn (mut app ViewerApp) on_files_dropped(w &ui.Window, e ui.MouseEvent) {
	num_files := sapp.get_num_dropped_files()
	if num_files > 0 {
		dropped_path := sapp.get_dropped_file_path(0)
		if dropped_path != '' {
			app.load_image(dropped_path)
		}
	}
}

pub fn (mut app ViewerApp) on_key_down(w &ui.Window, e ui.KeyEvent) {
	if !app.core.has_image {
		return
	}

	mut changed := false
	if e.key == .r {
		if e.mods.has(.shift) {
			app.core.rotate_ccw()
		} else {
			app.core.rotate_cw()
		}
		changed = true
	} else if e.key == .h {
		app.core.flip_h()
		changed = true
	} else if e.key == .v {
		app.core.flip_v()
		changed = true
	} else if e.key == .f {
		app.core.zoom_fit()
		changed = true
	} else if e.key == ._0 || e.key == .kp_0 {
		app.core.zoom_actual()
		changed = true
	}

	if changed && app.window != unsafe { nil } {
		app.window.refresh()
	}
}

pub fn (mut app ViewerApp) on_canvas_scroll(c &ui.CanvasLayout, e ui.ScrollEvent) {
	if !app.core.has_image {
		return
	}
	cursor_x := f32(e.mouse_x)
	cursor_y := f32(e.mouse_y)
	delta := f32(e.y)
	if delta != 0 {
		factor := if delta > 0 { zoom_step_factor } else { f32(1.0 / zoom_step_factor) }
		app.core.zoom_at(cursor_x, cursor_y, factor)
		if app.window != unsafe { nil } {
			app.window.refresh()
		}
	}
}

pub fn (mut app ViewerApp) on_canvas_mouse_down(c &ui.CanvasLayout, e ui.MouseEvent) {
	if !app.core.has_image {
		return
	}
	if e.button == .left {
		app.is_dragging = true
		app.drag_prev_x = f32(e.x)
		app.drag_prev_y = f32(e.y)
	}
}

pub fn (mut app ViewerApp) on_canvas_mouse_up(c &ui.CanvasLayout, e ui.MouseEvent) {
	if e.button == .left {
		app.is_dragging = false
	}
}

pub fn (mut app ViewerApp) on_canvas_mouse_move(c &ui.CanvasLayout, e ui.MouseMoveEvent) {
	if !app.core.has_image || !app.is_dragging {
		return
	}
	dx := f32(e.x) - app.drag_prev_x
	dy := f32(e.y) - app.drag_prev_y
	app.drag_prev_x = f32(e.x)
	app.drag_prev_y = f32(e.y)

	app.core.pan(dx, dy)
	if app.window != unsafe { nil } {
		app.window.refresh()
	}
}

pub fn (mut app ViewerApp) on_canvas_click(c &ui.CanvasLayout, e ui.MouseEvent) {
	if !app.core.has_image {
		return
	}
	now := time.ticks()
	dt := now - app.last_click_time
	dx := math.abs(f32(e.x) - app.last_click_x)
	dy := math.abs(f32(e.y) - app.last_click_y)

	// Double-click threshold: within 400ms and 5px radius
	if dt < 400 && dx <= 5.0 && dy <= 5.0 {
		app.core.toggle_zoom_fit_actual()
		app.last_click_time = 0
		if app.window != unsafe { nil } {
			app.window.refresh()
		}
	} else {
		app.last_click_time = now
		app.last_click_x = f32(e.x)
		app.last_click_y = f32(e.y)
	}
}

pub fn (mut app ViewerApp) draw_canvas(mut d ui.DrawDevice, c &ui.CanvasLayout) {
	mut ctx := c.ui.gg
	canvas_w := c.width
	canvas_h := c.height

	app.init_samplers()
	app.core.set_canvas_size(canvas_w, canvas_h)

	// 1. Fill entire canvas background with neutral dark color
	ctx.draw_rect_filled(0, 0, f32(canvas_w), f32(canvas_h), canvas_bg_color)

	if app.core.has_image {
		// Update sampler on the Sokol image cache according to filter mode
		active_sampler := if app.core.filter_mode == .nearest {
			app.sampler_nearest
		} else {
			app.sampler_linear
		}
		app.image.ssmp = active_sampler
		mut cached_img := ctx.get_cached_image_by_idx(app.image.id)
		if cached_img.ok {
			cached_img.ssmp = active_sampler
		}

		// 2. Draw subtle neutral checkerboard grid directly under visual image bounds clipped to canvas
		draw_checkerboard(ctx, app.core.viewport.x, app.core.viewport.y, app.core.viewport.width,
			app.core.viewport.height, default_checker_size, canvas_w, canvas_h)

		// 3. Draw image with config
		img_rect, rot_deg, flip_x, flip_y := get_draw_image_params(app.core.viewport,
			app.image.width, app.image.height)
		ctx.draw_image_with_config(gg.DrawImageConfig{
			img:      &app.image
			img_rect: img_rect
			rotation: rot_deg
			flip_x:   flip_x
			flip_y:   flip_y
		})
	} else {
		// Clean empty viewport drop target
		app.draw_empty_target(ctx, canvas_w, canvas_h)
	}
}

pub fn (app &ViewerApp) draw_empty_target(ctx &gg.Context, canvas_w int, canvas_h int) {
	target_w := f32(if canvas_w - 120 < 420 { math.max(120, canvas_w - 60) } else { 420 })
	target_h := f32(if canvas_h - 120 < 260 { math.max(80, canvas_h - 60) } else { 260 })
	target_x := (f32(canvas_w) - target_w) / 2.0
	target_y := (f32(canvas_h) - target_h) / 2.0

	// Draw subtle drop target bounding frame
	ctx.draw_rect_empty(target_x, target_y, target_w, target_h, drop_target_border_color)

	center_x := int(f32(canvas_w) / 2.0)
	center_y := int(f32(canvas_h) / 2.0)

	if app.core.error_msg != '' {
		ctx.draw_text(center_x, center_y - 20, app.core.error_msg, gg.TextCfg{
			size:           14
			color:          error_text_color
			align:          .center
			vertical_align: .middle
		})
		ctx.draw_text(center_x, center_y + 16, 'Drop another image or open via CLI', gg.TextCfg{
			size:           13
			color:          drop_target_subtext_color
			align:          .center
			vertical_align: .middle
		})
	} else {
		// Subtle geometric icon in the center: inner frame / image glyph
		icon_sz := f32(36.0)
		icon_x := f32(center_x) - icon_sz / 2.0
		icon_y := f32(center_y) - 44.0
		ctx.draw_rect_empty(icon_x, icon_y, icon_sz, icon_sz * 0.75, drop_target_border_color)

		ctx.draw_text(center_x, center_y + 6, 'Drop image here to view', gg.TextCfg{
			size:           15
			color:          drop_target_text_color
			align:          .center
			vertical_align: .middle
		})
		ctx.draw_text(center_x, center_y + 32, 'or run: image-ui <path>', gg.TextCfg{
			size:           13
			color:          drop_target_subtext_color
			align:          .center
			vertical_align: .middle
		})
	}
}

fn main() {
	config := parse_cli_args(os.args) or {
		eprintln('Error: ${err}')
		exit(1)
	}

	if config.show_help {
		println('image-ui - fast, lightweight desktop image viewer')
		println('')
		println('Usage:')
		println('  image-ui [path_to_image]')
		println('  image-ui --help')
		println('')
		println('Arguments:')
		println('  path_to_image    Optional file path of an image to display on launch')
		return
	}

	mut app := &ViewerApp{
		core: App{
			target_path: config.image_path
		}
	}

	app.window = ui.window(
		width:            1024
		height:           768
		title:            'image-ui'
		mode:             .resizable
		on_init:          app.win_init
		on_files_dropped: app.on_files_dropped
		on_key_down:      app.on_key_down
		enable_dragndrop: true
		layout:           ui.canvas_layout(
			id:            'viewport_canvas'
			on_draw:       app.draw_canvas
			on_click:      app.on_canvas_click
			on_mouse_down: app.on_canvas_mouse_down
			on_mouse_up:   app.on_canvas_mouse_up
			on_mouse_move: app.on_canvas_mouse_move
			on_scroll:     app.on_canvas_scroll
		)
	)

	ui.run(app.window)
}
