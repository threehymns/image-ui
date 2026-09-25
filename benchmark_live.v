module main

import os
import time
import sokol.sapp
import ui2

struct LiveTraceRow {
pub:
	event    string
	at_us    i64
	width    int
	height   int
	order    int
	value_us i64
	detail   string
}

struct LiveFrameSample {
pub mut:
	at_us       i64
	width       int
	height      int
	order       int
	interval_us i64
}

struct LivePendingAction {
pub mut:
	action string
	at_us  i64
}

pub struct BenchmarkLiveTrace {
pub mut:
	enabled         bool
	path            string
	launch_us       i64
	last_frame_us   i64
	last_width      int
	last_height     int
	frame_count     int
	frame_target    int
	warmup_frames   int
	has_frame       bool
	has_content     bool
	has_input       bool
	has_scan        bool
	pending_actions []LivePendingAction
	pending_resize  bool
	finished        bool
	frames          []LiveFrameSample
}

pub struct LiveTraceSummary {
pub mut:
	process_to_first_content_ns i64 = -1
	process_to_first_input_ns   i64 = -1
	toggle_to_frame_ns          i64 = -1
	switch_to_frame_ns          i64 = -1
	pan_to_frame_ns             i64 = -1
	zoom_to_frame_ns            i64 = -1
	resize_to_frame_ns          i64 = -1
	frame_median_ns             i64 = -1
	frame_p95_ns                i64 = -1
	frame_samples               int
	viewport_width              int
	viewport_height             int
	checksum                    u64
	complete                    bool
}

pub fn summarize_live_trace(path string, warmup_frames int, frame_target int) !LiveTraceSummary {
	rows := os.read_lines(path) or { return err }
	mut frames := []i64{}
	mut summary := LiveTraceSummary{}
	mut checksum := u64(14695981039346656037)
	mut resize_request_us := i64(0)
	resize_path := path + '.resize_request_us'
	if request := os.read_file(resize_path) {
		resize_request_us = request.trim_space().i64()
	}
	mut resize_request_width := 0
	if width_file := os.read_file(path + '.resize_request_width') {
		resize_request_width = width_file.trim_space().int()
	}
	for line in rows {
		parts := line.split('\t')
		if parts.len < 6 {
			continue
		}
		row := LiveTraceRow{
			event:    parts[0]
			at_us:    parts[1].i64()
			width:    parts[2].int()
			height:   parts[3].int()
			order:    parts[4].int()
			value_us: parts[5].i64()
			detail:   if parts.len > 6 { parts[6..].join('\t') } else { '' }
		}
		checksum = benchmark_checksum_text(checksum, row.event)
		checksum = benchmark_checksum_text(checksum, row.detail)
		match row.event {
			'first_content' {
				summary.process_to_first_content_ns = row.value_us * 1000
			}
			'first_input' {
				summary.process_to_first_input_ns = row.value_us * 1000
			}
			'action_presented' {
				match row.detail {
					'toggle' { summary.toggle_to_frame_ns = row.value_us * 1000 }
					'switch' { summary.switch_to_frame_ns = row.value_us * 1000 }
					'pan' { summary.pan_to_frame_ns = row.value_us * 1000 }
					'zoom' { summary.zoom_to_frame_ns = row.value_us * 1000 }
					else {}
				}
			}
			'resize_observed' {
				if resize_request_width > 0 && row.width != resize_request_width {
					continue
				}
				summary.viewport_width = row.width
				summary.viewport_height = row.height
				summary.resize_to_frame_ns = if resize_request_us > 0 {
					(row.at_us - resize_request_us) * 1000
				} else {
					row.value_us * 1000
				}
			}
			'frame_interval' {
				if row.order > warmup_frames && row.order <= frame_target {
					frames << row.value_us * 1000
				}
			}
			'complete' {
				summary.complete = true
				if summary.viewport_width == 0 {
					summary.viewport_width = row.width
					summary.viewport_height = row.height
				}
			}
			else {}
		}
	}
	if frames.len > 0 {
		stats := summarize_samples(frames)
		summary.frame_median_ns = stats.median_ns
		summary.frame_p95_ns = stats.p95_ns
	}
	summary.frame_samples = frames.len
	summary.checksum = checksum
	return summary
}

pub fn new_benchmark_live_trace() BenchmarkLiveTrace {
	path := os.getenv('IMAGE_UI_BENCHMARK_TRACE')
	now := time.now().unix_micro()
	mut trace := BenchmarkLiveTrace{
		path:          path
		launch_us:     now
		frame_target:  360
		warmup_frames: 60
	}
	if path == '' {
		return trace
	}
	requested_launch := os.getenv('IMAGE_UI_BENCHMARK_LAUNCH_US').i64()
	if requested_launch > 0 {
		trace.launch_us = requested_launch
	}
	trace.frame_target = os.getenv('IMAGE_UI_BENCHMARK_FRAME_TARGET').int()
	if trace.frame_target < 2 {
		trace.frame_target = 360
	}
	trace.warmup_frames = os.getenv('IMAGE_UI_BENCHMARK_WARMUP_FRAMES').int()
	if trace.warmup_frames < 0 || trace.warmup_frames >= trace.frame_target {
		trace.warmup_frames = trace.frame_target / 6
	}
	trace.enabled = true
	trace.write_event('process_launch', 0, 0, 0, now - trace.launch_us, '')
	return trace
}

fn (mut trace BenchmarkLiveTrace) begin_frame(width int, height int) {
	if !trace.enabled {
		return
	}
	now := time.now().unix_micro()
	if trace.has_frame {
		trace.pending_resize = trace.last_width != width || trace.last_height != height
		trace.frames << LiveFrameSample{
			at_us:       now
			width:       width
			height:      height
			order:       trace.frame_count + 1
			interval_us: now - trace.last_frame_us
		}
	}
	trace.last_frame_us = now
	trace.last_width = width
	trace.last_height = height
	trace.has_frame = true
}

fn (mut trace BenchmarkLiveTrace) end_frame(path string, scan_complete bool) {
	if !trace.enabled {
		return
	}
	now := time.now().unix_micro()
	trace.frame_count++
	if !trace.has_content {
		trace.has_content = true
		trace.write_event('first_content', trace.last_width, trace.last_height, trace.frame_count, now - trace.launch_us, '')
	}
	if trace.pending_resize {
		trace.write_event('resize_observed', trace.last_width, trace.last_height, trace.frame_count, 0, '')
		trace.pending_resize = false
	}
	for pending in trace.pending_actions {
		trace.write_event('action_presented', trace.last_width, trace.last_height, trace.frame_count, now - pending.at_us, pending.action)
	}
	trace.pending_actions.clear()
	if scan_complete && !trace.has_scan {
		trace.has_scan = true
		trace.write_event('scan_complete', trace.last_width, trace.last_height, trace.frame_count, 0, '')
	}
	if trace.frame_count >= trace.frame_target && !trace.finished {
		for frame in trace.frames {
			trace.write_event('frame_interval', frame.width, frame.height, frame.order, frame.interval_us, '')
		}
		trace.write_event('complete', trace.last_width, trace.last_height, trace.frame_count, 0, path)
		trace.finished = true
		sapp.request_quit()
	}
}

fn (mut trace BenchmarkLiveTrace) on_key(code ui2.KeyCode) {
	if !trace.enabled {
		return
	}
	action := benchmark_key_action(code)
	now := time.now().unix_micro()
	if !trace.has_input {
		trace.has_input = true
		trace.write_event('first_input', trace.last_width, trace.last_height, trace.frame_count, now - trace.launch_us, action)
	}
	trace.write_event('input_key', trace.last_width, trace.last_height, trace.frame_count, now - trace.launch_us, action)
	if action != '' {
		trace.pending_actions << LivePendingAction{ action: action, at_us: now }
	}
}

fn (mut trace BenchmarkLiveTrace) on_pointer(action string) {
	if !trace.enabled {
		return
	}
	now := time.now().unix_micro()
	if !trace.has_input {
		trace.has_input = true
		trace.write_event('first_input', trace.last_width, trace.last_height, trace.frame_count, now - trace.launch_us, action)
	}
	trace.write_event('input_pointer', trace.last_width, trace.last_height, trace.frame_count, now - trace.launch_us, action)
	if action != '' {
		trace.pending_actions << LivePendingAction{ action: action, at_us: now }
	}
}

fn (mut trace BenchmarkLiveTrace) write_event(event string, width int, height int, order int, value i64, detail string) {
	if !trace.enabled || trace.path == '' {
		return
	}
	mut file := os.open_append(trace.path) or { return }
	file.writeln('${event}\t${time.now().unix_micro()}\t${width}\t${height}\t${order}\t${value}\t${detail}') or {}
	file.close()
}

fn benchmark_key_action(code ui2.KeyCode) string {
	return match code {
		.t { 'toggle' }
		.right, .left { 'switch' }
		.equal, .kp_add, .minus, .kp_subtract { 'zoom' }
		.p { 'pan' }
		.z { 'zoom' }
		else { '' }
	}
}
