module main

import os
import math
import time
import ui2
import gg
import stbi

// Background for the canvas area outside the image
pub const canvas_bg_hex = u32(0x141416)

// Drop target frame and text styling colors
pub const drop_target_border_hex = u32(0x34343a)
pub const drop_target_text_hex = u32(0xa0a0a8)
pub const drop_target_subtext_hex = u32(0x64646c)
pub const error_text_hex = u32(0xdc5a5a)

@[heap]
pub struct ViewerApp {
pub mut:
	core            App
	window_ready    bool
	is_dragging     bool
	drag_prev_x     f64
	drag_prev_y     f64
	last_click_time i64
	last_click_x    f64
	last_click_y    f64
	scanned_dir          string
	scanner_ch           chan SiblingBatch
	has_scanner_ch       bool
	requested_window_w   int
	requested_window_h   int
	checkerboard_key          string
	checkerboard_pending_key  string
	checkerboard_stable_frames int
	checkerboard_layer        ui2.Element
}

// update_window_title refreshes the window title to show image name, dimensions, and playlist index.
pub fn (mut app ViewerApp) update_window_title() {
	if !app.window_ready {
		return
	}
	if app.core.has_image {
		title := format_window_title_with_index(
			app.core.target_path,
			app.core.img_width,
			app.core.img_height,
			app.core.active_index,
			app.core.playlist.len,
		)
		gg.set_window_title(title)
	} else {
		gg.set_window_title('image-ui')
	}
}

// poll_scanner drains pending sibling scanner batches non-blockingly.
pub fn (mut app ViewerApp) poll_scanner() {
	if !app.has_scanner_ch {
		return
	}
	mut received_any := false
	mut count := 0
	for count < 10 {
		select {
			batch := <-app.scanner_ch {
				app.core.integrate_batch(batch)
				received_any = true
				count++
				if batch.is_last {
					app.has_scanner_ch = false
					break
				}
			}
			else {
				break
			}
		}
	}
	if received_any {
		app.update_window_title()
	}
}

pub fn (mut app ViewerApp) load_image(path string) {
	if path == '' {
		app.core.set_error('', '')
		app.update_window_title()
		return
	}

	if !os.exists(path) {
		app.core.set_error(path, 'File not found: ${path}')
		app.update_window_title()
		return
	}

	// Resolve target image path and parent folder
	mut img_path := path
	mut dir_path := ''
	if os.is_dir(path) {
		first_img := find_first_image_in_dir(path) or {
			app.core.set_error(path, 'No supported images found in directory: ${path}')
			app.update_window_title()
			return
		}
		img_path = first_img
		dir_path = path
	} else {
		dir_path = os.dir(path)
	}

	img_bytes := os.read_bytes(img_path) or {
		app.core.set_error(img_path, 'Unable to read image: ${err.msg()}')
		app.update_window_title()
		return
	}

	stbi_img := stbi.load_from_memory(img_bytes.data, img_bytes.len, stbi.LoadParams{}) or {
		app.core.set_error(img_path, 'Unable to load image: ${err.msg()}')
		app.update_window_title()
		return
	}
	img_w := stbi_img.width
	img_h := stbi_img.height
	stbi_img.free()

	app.core.set_image_loaded(img_path, img_w, img_h)

	// If scanning a new directory, spawn background worker channel
	clean_dir := os.real_path(dir_path)
	if clean_dir != app.scanned_dir {
		app.scanned_dir = clean_dir
		app.scanner_ch = chan SiblingBatch{cap: 32}
		app.has_scanner_ch = true
		app.core.is_scanning = true
		app.core.scan_complete = false
		spawn scan_directory_siblings(clean_dir, img_path, app.scanner_ch)
	}

	app.update_window_title()
}

fn (mut app ViewerApp) get_checkerboard_layer(win_w int, win_h int) ui2.Element {
	key := '${win_w}:${win_h}'
	if app.checkerboard_key.len == 0 {
		app.checkerboard_layer = build_checkerboard_layer(win_w, win_h)
		app.checkerboard_key = key
		return app.checkerboard_layer
	}

	app.checkerboard_layer = ui2.Element{
		...app.checkerboard_layer
		frame: ui2.rect(0, 0, f64(win_w), f64(win_h))
	}
	if key == app.checkerboard_key {
		app.checkerboard_pending_key = ''
		app.checkerboard_stable_frames = 0
		return app.checkerboard_layer
	}
	if app.checkerboard_pending_key != key {
		app.checkerboard_pending_key = key
		app.checkerboard_stable_frames = 0
		return app.checkerboard_layer
	}
	app.checkerboard_stable_frames++
	if app.checkerboard_stable_frames < 2 {
		return app.checkerboard_layer
	}
	app.checkerboard_layer = build_checkerboard_layer(win_w, win_h)
	app.checkerboard_key = key
	app.checkerboard_pending_key = ''
	app.checkerboard_stable_frames = 0
	return app.checkerboard_layer
}

pub fn (mut app ViewerApp) build_screen() ui2.Element {
	app.poll_scanner()
	first_build := !app.window_ready
	if first_build {
		app.window_ready = true
		if app.core.target_path != '' {
			app.load_image(app.core.target_path)
		} else {
			app.update_window_title()
		}
	}

	mut bounds := ui2.bounds()
	if first_build && app.requested_window_w > 0 && app.requested_window_h > 0 {
		bounds = ui2.rect(0, 0, f64(app.requested_window_w), f64(app.requested_window_h))
	}
	win_w := int(bounds.width)
	win_h := int(bounds.height)
	if win_w > 0 && win_h > 0 {
		app.core.set_canvas_size(win_w, win_h)
	}

	if app.core.has_image {
		img_rect, _, _, _ := get_draw_image_params(
			app.core.viewport,
			app.core.img_width,
			app.core.img_height,
		)
		// ui2's rotation is clockwise degrees while get_draw_image_params
		// reports sokol's counterclockwise convention, so pass the viewport
		// rotation directly instead of the negated draw angle.
		norm_rot := (app.core.viewport.rotation % 360 + 360) % 360
		// The image itself stays non-interactive (clickable=false) so it
		// contributes no hit target: ui2 only emits pointer:drag for
		// draggable targets, and a clickable-only image on top would swallow
		// the gesture and break click-and-drag panning. All pointer gestures
		// fall through to the draggable canvas below.
		mut img_el := ui2.transformed_image(
			'viewport_image',
			app.core.target_path,
			ui2.rect(f64(img_rect.x), f64(img_rect.y), f64(img_rect.width), f64(img_rect.height)),
			f64(norm_rot),
			false,
		)
		// Horizontal/vertical mirroring lost in the ui2 port: re-declare it
		// so the h/v keys take visible effect again.
		if app.core.viewport.flip_h {
			img_el = ui2.with_flip_h(img_el)
		}
		if app.core.viewport.flip_v {
			img_el = ui2.with_flip_v(img_el)
		}
		// Magnification past 200% samples nearest-neighbor (crisp pixels);
		// at or below that the default bilinear filtering applies.
		if app.core.filter_mode == .nearest {
			img_el = ui2.with_pixelated(img_el)
		}

		// Subtle neutral checkerboard grid directly under visual image bounds,
		// clipped to canvas. Restores the transparency background lost in the
		// ui2 port; toggle with the `t` key.
		mut screen_children := []ui2.Element{}
		if app.core.show_checkerboard {
			screen_children << app.get_checkerboard_layer(win_w, win_h)
			screen_children << checkerboard_mask_elements(app.core.viewport, win_w, win_h)
		}
		screen_children << ui2.draggable_view_with_cursor('canvas_bg', bounds,
			ui2.BoxStyle{ transparent: true }, 'pointing_hand', [img_el])

		return ui2.screen(canvas_bg_hex, screen_children)
	}

	// Empty drop target
	target_w := f64(if win_w - 120 < 420 { math.max(120, win_w - 60) } else { 420 })
	target_h := f64(if win_h - 120 < 260 { math.max(80, win_h - 60) } else { 260 })
	target_x := (f64(win_w) - target_w) / 2.0
	target_y := (f64(win_h) - target_h) / 2.0

	mut target_children := []ui2.Element{}

	if app.core.error_msg != '' {
		target_children << ui2.label(
			'err_label',
			app.core.error_msg,
			ui2.rect(0, target_h / 2.0 - 24, target_w, 24),
			ui2.TextStyle{
				size:  14
				color: error_text_hex
				align: .center
			},
		)
		target_children << ui2.label(
			'err_sublabel',
			'Drop another image or open via CLI',
			ui2.rect(0, target_h / 2.0 + 8, target_w, 20),
			ui2.TextStyle{
				size:  13
				color: drop_target_subtext_hex
				align: .center
			},
		)
	} else {
		// Subtle geometric icon in the center
		icon_sz := 36.0
		icon_x := (target_w - icon_sz) / 2.0
		icon_y := target_h / 2.0 - 48.0
		target_children << ui2.view(
			'icon_box',
			ui2.rect(icon_x, icon_y, icon_sz, icon_sz * 0.75),
			ui2.BoxStyle{
				border_color:  drop_target_border_hex
				border_left:   1
				border_top:    1
				border_right:  1
				border_bottom: 1
				transparent:   true
				radius:        2
			},
			[],
		)
		target_children << ui2.label(
			'prompt_label',
			'Drop image here to view',
			ui2.rect(0, target_h / 2.0 + 4, target_w, 24),
			ui2.TextStyle{
				size:  15
				color: drop_target_text_hex
				align: .center
			},
		)
		target_children << ui2.label(
			'subprompt_label',
			'or run: image-ui <path>',
			ui2.rect(0, target_h / 2.0 + 30, target_w, 20),
			ui2.TextStyle{
				size:  13
				color: drop_target_subtext_hex
				align: .center
			},
		)
	}

	frame_box := ui2.view(
		'target_frame',
		ui2.rect(target_x, target_y, target_w, target_h),
		ui2.BoxStyle{
			border_color:  drop_target_border_hex
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
			transparent:   true
			radius:        6
		},
		target_children,
	)

	return ui2.screen(canvas_bg_hex, [frame_box])
}

fn parse_pointer_event(event string) ?(string, string, f64, f64) {
	parts := event.split(':')
	if parts.len < 5 || parts[0] != 'pointer' {
		return none
	}
	return parts[1], parts[2], parts[3].f64(), parts[4].f64()
}

// parse_scroll_event decodes the 'scroll:<cursor_x>:<cursor_y>:<delta_y>'
// wire format emitted for wheel and trackpad scroll gestures that no
// scrollable view consumes. Trackpad pinch-to-zoom arrives on this channel
// as well (Ctrl+scroll on the desktop backends).
fn parse_scroll_event(event string) ?(f64, f64, f64) {
	parts := event.split(':')
	if parts.len != 4 || parts[0] != 'scroll' {
		return none
	}
	return parts[1].f64(), parts[2].f64(), parts[3].f64()
}

// handle_scroll zooms the viewport anchored at the cursor position,
// restoring the wheel/trackpad-to-zoom gesture lost in the ui2 port.
// Positive delta_y (wheel up, trackpad scroll up, pinch out) zooms in and
// negative delta_y zooms out. The factor follows zoom_step_factor ^ delta_y
// so a discrete notch (|delta| == 1) reproduces the legacy single-step zoom
// exactly, while fractional high-resolution trackpad deltas scale smoothly.
pub fn (mut app ViewerApp) handle_scroll(cursor_x f64, cursor_y f64, delta_y f64) {
	if !app.core.has_image {
		return
	}
	if delta_y == 0 {
		return
	}
	factor := f32(math.pow(f64(zoom_step_factor), delta_y))
	app.core.zoom_at(f32(cursor_x), f32(cursor_y), factor)
}

pub fn (mut app ViewerApp) handle_event(event string) {
	if event.starts_with('scroll:') {
		x, y, delta := parse_scroll_event(event) or { return }
		app.handle_scroll(x, y, delta)
		return
	}
	phase, id, x, y := parse_pointer_event(event) or { return }
	if id != 'viewport_image' && id != 'canvas_bg' {
		return
	}

	if phase == 'down' {
		app.is_dragging = true
		app.drag_prev_x = x
		app.drag_prev_y = y
	} else if phase == 'drag' {
		if !app.is_dragging {
			app.is_dragging = true
			app.drag_prev_x = x
			app.drag_prev_y = y
			return
		}
		dx := x - app.drag_prev_x
		dy := y - app.drag_prev_y
		app.drag_prev_x = x
		app.drag_prev_y = y
		app.core.pan(f32(dx), f32(dy))
	} else if phase == 'up' {
		app.is_dragging = false
		now := time.ticks()
		dt := now - app.last_click_time
		dx := math.abs(x - app.last_click_x)
		dy := math.abs(y - app.last_click_y)
		if dt < 400 && dx <= 5.0 && dy <= 5.0 {
			app.core.toggle_zoom_fit_actual()
			app.last_click_time = 0
		} else {
			app.last_click_time = now
			app.last_click_x = x
			app.last_click_y = y
		}
	}
}

pub fn (mut app ViewerApp) handle_key_event(e ui2.KeyEvent) {
	if !app.core.has_image && app.core.playlist.len == 0 {
		return
	}
	app.poll_scanner()

	match e.code {
		.left {
			if app.core.prev_sibling() {
				app.load_image(app.core.target_path)
			}
		}
		.right {
			if app.core.next_sibling() {
				app.load_image(app.core.target_path)
			}
		}
		.up {
			if app.core.prev_secondary_step() {
				app.load_image(app.core.target_path)
			}
		}
		.down {
			if app.core.next_secondary_step() {
				app.load_image(app.core.target_path)
			}
		}
		.page_up {
			if app.core.prev_secondary_step() {
				app.load_image(app.core.target_path)
			}
		}
		.page_down {
			if app.core.next_secondary_step() {
				app.load_image(app.core.target_path)
			}
		}
		.r {
			if e.shift {
				app.core.rotate_ccw()
			} else {
				app.core.rotate_cw()
			}
		}
		.h {
			app.core.flip_h()
		}
		.v {
			app.core.flip_v()
		}
		.f {
			app.core.zoom_fit()
		}
		._0, .kp_0 {
			app.core.zoom_actual()
		}
		.equal, .kp_add {
			app.core.zoom_in()
		}
		.minus, .kp_subtract {
			app.core.zoom_out()
		}
		.t {
			app.core.toggle_checkerboard()
		}
		else {}
	}
}

pub fn (mut app ViewerApp) handle_drop(e ui2.DropEvent) {
	if e.paths.len > 0 {
		app.load_image(e.paths[0])
	}
}

const global_viewer_app = &ViewerApp{}

fn build_viewer_screen() ui2.Element {
	mut app := unsafe { global_viewer_app }
	return app.build_screen()
}

fn handle_viewer_event(event string) {
	mut app := unsafe { global_viewer_app }
	app.handle_event(event)
}

fn handle_viewer_key(e ui2.KeyEvent) {
	mut app := unsafe { global_viewer_app }
	app.handle_key_event(e)
}

fn handle_viewer_drop(e ui2.DropEvent) {
	mut app := unsafe { global_viewer_app }
	app.handle_drop(e)
}

fn main() {
	mut cmd := build_cli_command()
	cmd.setup()
	cmd.parse(os.args)
}

// launch_viewer boots the desktop viewer for the given image path.
// An empty path starts with the empty drop target.
pub fn launch_viewer(image_path string) {
	mut app := unsafe { global_viewer_app }
	app.core = new_app()
	app.core.target_path = image_path
	app.requested_window_w = 1024
	app.requested_window_h = 768

	ui2.on_key_event(handle_viewer_key)
	ui2.on_drop(handle_viewer_drop)

	ui2.run_window('image-ui', 1024, 768, build_viewer_screen, handle_viewer_event)
}
