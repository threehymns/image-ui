module main

import os
import math
import time
import ui2
import gg

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
	core                          App
	image_loader                  ImageResourceLoader
	image_pipeline                ImagePipeline
	sibling_cache_budget_bytes    int
	sibling_cache_neighbor_radius int = -1
	window_ready                  bool
	is_dragging                   bool
	drag_prev_x                   f64
	drag_prev_y                   f64
	last_click_time               i64
	last_click_x                  f64
	last_click_y                  f64
	scanned_dir                   string
	scanner_ch                    chan SiblingBatch
	has_scanner_ch                bool
	scanner_cancel                chan bool
	has_scanner_cancel            bool
	requested_window_w            int
	requested_window_h            int
	transparency_pattern          ui2.RepeatPattern
	benchmark_live                BenchmarkLiveTrace
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
				if !app.core.accepts_batch(batch) {
					count++
					continue
				}
				app.core.integrate_batch(batch)
				if batch.items.len == 0 && batch.is_last && !app.core.has_image && os.is_dir(app.core.target_path) {
					app.core.set_error(app.core.target_path, 'No supported images found in directory: ${app.core.target_path}')
				}
				received_any = true
				count++
				if batch.is_first_content && batch.items.len > 0 && !app.core.has_image {
					app.load_image_internal(app.core.target_path, false, false)
				}
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
		app.sync_sibling_cache_retention()
		app.update_window_title()
	}
}

fn (mut app ViewerApp) ensure_image_loader() {
	if voidptr(app.image_loader.decoder) == unsafe { nil } {
		app.image_loader = new_image_resource_loader(decode_stbi_image)
	}
}

fn (mut app ViewerApp) ensure_image_pipeline() {
	app.ensure_image_loader()
	mut pipeline_created := false
	if !app.image_pipeline.configured {
		mut budget_bytes := app.sibling_cache_budget_bytes
		if budget_bytes == 0 {
			budget_bytes = configured_sibling_cache_budget_bytes()
		}
		app.image_pipeline = new_image_pipeline_with_cache(app.image_loader.decoder, budget_bytes)
		pipeline_created = true
	} else if !app.image_pipeline.manual && voidptr(app.image_pipeline.decoder) == unsafe { nil } {
		app.image_pipeline.decoder = app.image_loader.decoder
	}
	if app.sibling_cache_neighbor_radius >= 0 {
		app.image_pipeline.neighbor_radius = app.sibling_cache_neighbor_radius
	} else if pipeline_created {
		app.image_pipeline.neighbor_radius = configured_sibling_cache_neighbor_radius()
	}
	if app.sibling_cache_budget_bytes > 0 {
		app.image_pipeline.set_cache_budget(app.sibling_cache_budget_bytes)
	}
	if !app.core.has_image {
		app.image_pipeline.clear_resident()
	} else if app.core.displayed_resource.state == .ready
		&& (app.image_pipeline.resident_resource.state != .ready
			|| app.image_pipeline.resident_resource.source != app.core.displayed_resource.source) {
		app.image_pipeline.set_resident(app.core.displayed_resource)
	}
	app.sync_sibling_cache_retention()
}

fn (mut app ViewerApp) sync_sibling_cache_retention() {
	if !app.image_pipeline.configured {
		return
	}
	mut radius := app.image_pipeline.neighbor_radius
	if radius < 0 {
		radius = 0
	}
	mut start := app.core.active_index - radius
	if start < 0 {
		start = 0
	}
	mut end := app.core.active_index + radius + 1
	if end > app.core.playlist.len {
		end = app.core.playlist.len
	}
	mut nearby := []string{}
	if start < end {
		for index in start .. end {
			if index != app.core.active_index {
				nearby << app.core.playlist[index]
			}
		}
	}
	app.image_pipeline.set_nearby_paths(nearby)
}

pub fn (mut app ViewerApp) poll_image_pipeline() {
	if !app.image_pipeline.configured {
		return
	}
	results := app.image_pipeline.poll()
	for result in results {
		if app.core.commit_image_request(result.request, result.resource) {
			if result.resource.state == .ready {
				app.image_pipeline.set_resident(result.resource)
			}
			app.image_pipeline.mark_committed(result.request)
			app.update_window_title()
		}
	}
}

pub fn (mut app ViewerApp) request_image(path string, reason string) {
	if path == '' {
		app.core.set_error('', '')
		app.update_window_title()
		return
	}
	if os.is_dir(path) {
		app.start_scanner(path, '', false)
		app.update_window_title()
		return
	}
	app.ensure_image_pipeline()
	app.sync_sibling_cache_retention()
	request := app.core.request_image(path, reason)
	app.image_pipeline.request_with_generation(path, reason, request.generation)
	app.update_window_title()
}

fn (mut app ViewerApp) start_scanner(dir_path string, target_path string, force bool) {
	mut clean_dir := os.real_path(dir_path)
	if clean_dir == '' {
		clean_dir = dir_path
	}
	if !force && app.scanned_dir == clean_dir {
		return
	}
	if app.has_scanner_cancel {
		app.scanner_cancel.close()
		app.has_scanner_cancel = false
	}
	if app.has_scanner_ch || app.scanned_dir.len > 0 {
		app.core.invalidate_scan()
	}
	mut generation := app.core.scan_generation
	if generation == 0 {
		app.core.invalidate_scan()
		generation = app.core.scan_generation
	}
	app.scanned_dir = clean_dir
	app.scanner_ch = chan SiblingBatch{cap: 32}
	app.has_scanner_ch = true
	app.scanner_cancel = chan bool{}
	app.has_scanner_cancel = true
	app.core.begin_scan(generation)
	spawn scan_directory_siblings_with_generation_and_cancel(clean_dir, target_path, generation, app.scanner_ch, app.scanner_cancel)
}

fn (mut app ViewerApp) load_image_internal(path string, start_scan bool, force_scan bool) {
	if path == '' {
		app.core.set_error('', '')
		app.update_window_title()
		return
	}

	if os.is_dir(path) {
		app.start_scanner(path, '', force_scan)
		app.update_window_title()
		return
	}

	app.request_image(path, 'load')
	if start_scan {
		app.start_scanner(os.dir(path), path, force_scan)
	}
	app.update_window_title()
}

fn playlist_contains_path(playlist []string, path string) bool {
	for item in playlist {
		if item == path {
			return true
		}
	}
	return false
}

pub fn (mut app ViewerApp) load_image(path string) {
	if !playlist_contains_path(app.core.playlist, path) {
		app.core.open_path(path)
		app.load_image_internal(path, true, true)
		return
	}
	app.load_image_internal(path, true, false)
}

fn (mut app ViewerApp) get_transparency_pattern() ui2.RepeatPattern {
	if !app.transparency_pattern.valid() {
		app.transparency_pattern = checkerboard_pattern()
	}
	return app.transparency_pattern
}

pub fn (mut app ViewerApp) build_screen() ui2.Element {
	app.poll_scanner()
	first_build := !app.window_ready
	if first_build {
		app.window_ready = true
		if app.core.target_path != '' && !app.core.has_image {
			app.load_image_internal(app.core.target_path, true, true)
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
	return app.build_screen_at_size(win_w, win_h)
}

pub fn (mut app ViewerApp) build_screen_at_size(win_w int, win_h int) ui2.Element {
	app.poll_image_pipeline()
	$if viewer_benchmark ? {
		app.benchmark_live.begin_frame(win_w, win_h)
	}
	if win_w > 0 && win_h > 0 {
		app.core.set_canvas_size(win_w, win_h)
	}

	mut screen := ui2.Element{}
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
		displayed_resource := app.core.displayed_image_resource()
		mut displayed_path := displayed_resource.source
		if displayed_path.len == 0 {
			displayed_path = app.core.target_path
		}
		mut img_el := if displayed_resource.id.len > 0
			&& displayed_resource.state == .ready {
			ui2.transformed_image_resource(
				'viewport_image',
				displayed_resource,
				ui2.rect(f64(img_rect.x), f64(img_rect.y), f64(img_rect.width), f64(img_rect.height)),
				f64(norm_rot),
				false,
			)
		} else {
			ui2.transformed_image(
				'viewport_image',
				displayed_path,
				ui2.rect(f64(img_rect.x), f64(img_rect.y), f64(img_rect.width), f64(img_rect.height)),
				f64(norm_rot),
				false,
			)
		}
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

		mut screen_children := []ui2.Element{}
		if app.core.transparency_background_visible() {
			screen_children << ui2.pattern_background('transparency_background',
				app.get_transparency_pattern(), checkerboard_reveal_rect(app.core.viewport))
		}
		screen_children << ui2.draggable_view_with_cursor('canvas_bg',
			ui2.rect(0, 0, f64(win_w), f64(win_h)),
			ui2.BoxStyle{ transparent: true }, 'pointing_hand', [img_el])
		if app.core.error_msg != '' {
			error_w := f64(if win_w - 80 < 420 { math.max(120, win_w - 40) } else { 420 })
			error_h := f64(112)
			error_x := (f64(win_w) - error_w) / 2.0
			error_y := (f64(win_h) - error_h) / 2.0
			screen_children << ui2.view('error_card', ui2.rect(error_x, error_y, error_w, error_h),
				ui2.BoxStyle{
					bg:            canvas_bg_hex
					border_color:  drop_target_border_hex
					border_left:   1
					border_top:    1
					border_right:  1
					border_bottom: 1
					radius:        6
				}, [
					ui2.label('err_label', app.core.error_msg,
						ui2.rect(12, 28, error_w - 24, 24), ui2.TextStyle{
							size:  14
							color: error_text_hex
							align: .center
						}),
					ui2.label('err_sublabel', 'Drop another image or open via CLI',
						ui2.rect(12, 62, error_w - 24, 20), ui2.TextStyle{
							size:  13
							color: drop_target_subtext_hex
							align: .center
						}),
				])
		}

		screen = ui2.screen(canvas_bg_hex, screen_children)
	} else {
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

		screen = ui2.screen(canvas_bg_hex, [frame_box])
	}
	$if viewer_benchmark ? {
		app.benchmark_live.end_frame(app.core.active_sibling_path(), app.core.scan_complete)
	}
	return screen
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
		$if viewer_benchmark ? {
			app.benchmark_live.on_pointer('zoom')
		}
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
	$if viewer_benchmark ? {
		if phase == 'drag' {
			app.benchmark_live.on_pointer('pan')
		}
	}
}

pub fn (mut app ViewerApp) handle_key_event(e ui2.KeyEvent) {
	if !app.core.has_image && app.core.playlist.len == 0 {
		return
	}
	app.poll_scanner()
	$if viewer_benchmark ? {
		if app.benchmark_live.enabled {
			if e.code == .p {
				app.core.pan(24.0, 24.0)
			} else if e.code == .z {
				app.core.zoom_in()
			}
		}
	}

	match e.code {
		.left {
			if app.core.prev_sibling() {
				app.request_image(app.core.target_path, 'sibling')
			}
		}
		.right {
			if app.core.next_sibling() {
				app.request_image(app.core.target_path, 'sibling')
			}
		}
		.up {
			if app.core.prev_secondary_step() {
				app.request_image(app.core.target_path, 'sibling')
			}
		}
		.down {
			if app.core.next_secondary_step() {
				app.request_image(app.core.target_path, 'sibling')
			}
		}
		.page_up {
			if app.core.prev_secondary_step() {
				app.request_image(app.core.target_path, 'sibling')
			}
		}
		.page_down {
			if app.core.next_secondary_step() {
				app.request_image(app.core.target_path, 'sibling')
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
	$if viewer_benchmark ? {
		app.benchmark_live.on_key(e.code)
	}
}

pub fn (mut app ViewerApp) handle_drop(e ui2.DropEvent) {
	if e.paths.len > 0 {
		app.core.open_path(e.paths[0])
		app.load_image_internal(e.paths[0], true, true)
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
	$if viewer_benchmark ? {
		benchmark_main()
	} $else {
		mut cmd := build_cli_command()
		cmd.setup()
		cmd.parse(os.args)
	}
}

// launch_viewer boots the desktop viewer for the given image path.
// An empty path starts with the empty drop target.
pub fn launch_viewer(image_path string) {
	mut app := unsafe { global_viewer_app }
	app.core = new_app()
	app.image_pipeline = ImagePipeline{}
	app.core.open_path(image_path)
	if app.has_scanner_cancel {
		app.scanner_cancel.close()
	}
	app.scanned_dir = ''
	app.has_scanner_ch = false
	app.has_scanner_cancel = false
	app.requested_window_w = 1024
	app.requested_window_h = 768
	$if viewer_benchmark ? {
		app.benchmark_live = new_benchmark_live_trace()
	}

	ui2.on_key_event(handle_viewer_key)
	ui2.on_drop(handle_viewer_drop)

	ui2.run_window('image-ui', 1024, 768, build_viewer_screen, handle_viewer_event)
}
