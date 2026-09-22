module main

import os
import math
import ui
import gg
import sokol.sapp

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
	window        &ui.Window = unsafe { nil }
	target_path   string
	image         gg.Image
	has_image     bool
	viewport      Viewport
	last_canvas_w int
	last_canvas_h int
	error_msg     string
}

// draw_checkerboard renders the subtle neutral checkerboard grid directly via gg context.
pub fn draw_checkerboard(ctx &gg.Context, x f32, y f32, w f32, h f32, cell_size f32) {
	if w <= 0 || h <= 0 {
		return
	}
	sz := if cell_size > 0 { cell_size } else { default_checker_size }

	// Draw base dark neutral rectangle covering the entire image viewport
	ctx.draw_rect_filled(x, y, w, h, checker_color_dark)

	// Draw alternating lighter tiles clipped at the boundary
	mut cur_y := y
	mut row := 0
	for cur_y < y + h {
		cell_h := if cur_y + sz > y + h { y + h - cur_y } else { sz }
		mut cur_x := x
		mut col := 0
		for cur_x < x + w {
			cell_w := if cur_x + sz > x + w { x + w - cur_x } else { sz }
			if (row + col) % 2 == 1 {
				ctx.draw_rect_filled(cur_x, cur_y, cell_w, cell_h, checker_color_light)
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
		app.has_image = false
		app.target_path = ''
		app.error_msg = ''
		if app.window != unsafe { nil } {
			app.window.set_title(format_window_title('', 0, 0))
			app.window.refresh()
		}
		return
	}

	if !os.exists(path) {
		app.has_image = false
		app.target_path = ''
		app.error_msg = 'File not found: ${path}'
		if app.window != unsafe { nil } {
			app.window.set_title(format_window_title('', 0, 0))
			app.window.refresh()
		}
		return
	}

	mut gg_ctx := app.window.ui.gg
	img := gg_ctx.create_image(path) or {
		app.has_image = false
		app.target_path = ''
		app.error_msg = 'Unable to load image: ${err.msg()}'
		if app.window != unsafe { nil } {
			app.window.set_title(format_window_title('', 0, 0))
			app.window.refresh()
		}
		return
	}

	app.image = img
	app.has_image = true
	app.target_path = path
	app.error_msg = ''

	// Calculate initial viewport fit if canvas dimensions are known
	if app.last_canvas_w > 0 && app.last_canvas_h > 0 {
		app.viewport = calculate_initial_viewport(app.last_canvas_w, app.last_canvas_h, img.width, img.height)
	}

	// Update window title: image-ui - photo.png (1920x1080)
	title := format_window_title(path, img.width, img.height)
	if app.window != unsafe { nil } {
		app.window.set_title(title)
		app.window.refresh()
	}
}

pub fn (mut app ViewerApp) win_init(w &ui.Window) {
	app.window = unsafe { w }
	if app.target_path != '' {
		app.load_image(app.target_path)
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

pub fn (mut app ViewerApp) draw_canvas(mut d ui.DrawDevice, c &ui.CanvasLayout) {
	ctx := c.ui.gg
	canvas_w := c.width
	canvas_h := c.height

	// 1. Fill entire canvas background with neutral dark color
	ctx.draw_rect_filled(0, 0, f32(canvas_w), f32(canvas_h), canvas_bg_color)

	if app.has_image {
		// If canvas size changed or initial calculation needed
		if canvas_w != app.last_canvas_w || canvas_h != app.last_canvas_h {
			app.viewport = calculate_initial_viewport(canvas_w, canvas_h, app.image.width, app.image.height)
			app.last_canvas_w = canvas_w
			app.last_canvas_h = canvas_h
		}

		// 2. Draw subtle neutral checkerboard grid directly under image bounds
		draw_checkerboard(ctx, app.viewport.x, app.viewport.y, app.viewport.width, app.viewport.height, default_checker_size)

		// 3. Draw image with config (Sokol pipeline alpha blending)
		ctx.draw_image_with_config(gg.DrawImageConfig{
			img: &app.image
			img_rect: gg.Rect{
				x: app.viewport.x
				y: app.viewport.y
				width: app.viewport.width
				height: app.viewport.height
			}
		})
	} else {
		app.last_canvas_w = canvas_w
		app.last_canvas_h = canvas_h
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

	if app.error_msg != '' {
		ctx.draw_text(center_x, center_y - 20, app.error_msg, gg.TextCfg{
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
		target_path: config.image_path
	}

	app.window = ui.window(
		width:             1024
		height:            768
		title:             'image-ui'
		mode:              .resizable
		on_init:           app.win_init
		on_files_dropped:  app.on_files_dropped
		enable_dragndrop:  true
		layout:            ui.canvas_layout(
			id:      'viewport_canvas'
			on_draw: app.draw_canvas
		)
	)

	ui.run(app.window)
}
