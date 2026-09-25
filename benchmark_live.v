@[has_globals]
module main

import os
import strconv
import time
import sokol.sapp
import ui2

__global benchmark_process_launch_ns = u64(0)

fn benchmark_wall_time_us() i64 {
	return time.utc().unix_micro()
}

fn parse_benchmark_launch_us(value string) ?u64 {
	normalized := value.trim_space()
	if normalized.len == 0 {
		return none
	}
	parsed := strconv.common_parse_uint(normalized, 10, 64, true, true) or { return none }
	if parsed == 0 {
		return none
	}
	return parsed
}

fn benchmark_fallback_launch_ns(process_launch_ns u64, mono_now_ns u64) u64 {
	if process_launch_ns > 0 && process_launch_ns <= mono_now_ns {
		return process_launch_ns
	}
	return mono_now_ns
}

fn benchmark_launch_mono_ns(launch_value string, wall_now_us i64, mono_now_ns u64,
	process_launch_ns u64) u64 {
	fallback := benchmark_fallback_launch_ns(process_launch_ns, mono_now_ns)
	wall_launch_us := parse_benchmark_launch_us(launch_value) or { return fallback }
	if wall_now_us <= 0 {
		return fallback
	}
	wall_now := u64(wall_now_us)
	if wall_launch_us > wall_now {
		return fallback
	}
	delta_us := wall_now - wall_launch_us
	if delta_us > (u64(1) << 63) / 1000 {
		return fallback
	}
	delta_ns := delta_us * 1000
	if delta_ns > mono_now_ns {
		return fallback
	}
	launch_ns := mono_now_ns - delta_ns
	if launch_ns == 0 {
		return fallback
	}
	return launch_ns
}

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
	enabled             bool
	path                string
	launch_us           i64
	launch_mono_us      i64
	last_frame_us       i64
	last_width          int
	last_height         int
	frame_count         int
	frame_target        int
	warmup_frames       int
	has_frame           bool
	has_content         bool
	has_input           bool
	has_scan            bool
	frame_content_ready bool
	frame_scan_complete bool
	pending_actions     []LivePendingAction
	pending_resize      bool
	finished            bool
	transform_counts    map[string]int
	toggle_count        int
	frames              []LiveFrameSample
	phase_trace         StartupPhaseTrace
	pipeline_metrics    ImagePipelineMetrics
	prefetch_metrics    ImagePrefetchMetrics
	cache_metrics       SiblingResourceCacheMetrics
	left_input_count    int
	right_input_count   int
}

pub struct LiveTraceSummary {
pub mut:
	process_to_first_content_ns  i64 = -1
	process_to_first_input_ns    i64 = -1
	toggle_to_frame_ns           i64 = -1
	switch_to_frame_ns           i64 = -1
	pan_transparent_to_frame_ns  i64 = -1
	pan_opaque_to_frame_ns       i64 = -1
	zoom_transparent_to_frame_ns i64 = -1
	zoom_opaque_to_frame_ns      i64 = -1
	pan_transparent_median_ns    i64 = -1
	pan_transparent_p95_ns       i64 = -1
	pan_transparent_samples      int
	pan_opaque_median_ns         i64 = -1
	pan_opaque_p95_ns            i64 = -1
	pan_opaque_samples           int
	zoom_transparent_median_ns   i64 = -1
	zoom_transparent_p95_ns      i64 = -1
	zoom_transparent_samples     int
	zoom_opaque_median_ns        i64 = -1
	zoom_opaque_p95_ns           i64 = -1
	zoom_opaque_samples          int
	resize_to_frame_ns           i64 = -1
	frame_median_ns              i64 = -1
	frame_p95_ns                 i64 = -1
	frame_samples                int
	viewport_width               int
	viewport_height              int
	checksum                     u64
	complete                     bool
	phase_ns                     map[string]i64
	phase_order                  []string
	phase_monotonic              bool = true
	last_phase_us                i64  = -1
	counters                     BenchmarkCounters
	prefetch_cached_events       int
	left_input_count             int
	right_input_count            int
}

pub fn summarize_live_trace(path string, warmup_frames int, frame_target int) !LiveTraceSummary {
	rows := os.read_lines(path) or { return err }
	mut frames := []i64{}
	mut pan_transparent_samples := []i64{}
	mut pan_opaque_samples := []i64{}
	mut zoom_transparent_samples := []i64{}
	mut zoom_opaque_samples := []i64{}
	mut summary := LiveTraceSummary{
		phase_ns: map[string]i64{}
	}
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
			'phase' {
				if row.detail.len > 0 {
					summary.phase_ns[row.detail] = row.value_us * 1000
					summary.phase_order << row.detail
					if summary.last_phase_us >= 0 && row.at_us < summary.last_phase_us {
						summary.phase_monotonic = false
					}
					summary.last_phase_us = row.at_us
				}
			}
			'first_content' {
				summary.process_to_first_content_ns = row.value_us * 1000
			}
			'first_input' {
				summary.process_to_first_input_ns = row.value_us * 1000
			}
			'action_presented' {
				action := row.detail.split(':')[0]
				match action {
					'toggle' { summary.toggle_to_frame_ns = row.value_us * 1000 }
					'switch' { summary.switch_to_frame_ns = row.value_us * 1000 }
					'pan_transparent' { pan_transparent_samples << row.value_us * 1000 }
					'pan_opaque' { pan_opaque_samples << row.value_us * 1000 }
					'zoom_transparent' { zoom_transparent_samples << row.value_us * 1000 }
					'zoom_opaque' { zoom_opaque_samples << row.value_us * 1000 }
					else {}
				}
			}
			'prefetch_cached' {
				summary.prefetch_cached_events++
			}
			'pipeline_counters' {
				summary.counters = benchmark_counters_from_report(row.detail, int(row.value_us))
			}
			'repeat_counters' {
				for item in row.detail.split(',') {
					counter_parts := item.split(':')
					if counter_parts.len != 2 {
						continue
					}
					match counter_parts[0] {
						'left' { summary.left_input_count = counter_parts[1].int() }
						'right' { summary.right_input_count = counter_parts[1].int() }
						else {}
					}
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
	if pan_transparent_samples.len > 0 {
		stats := summarize_samples(pan_transparent_samples)
		summary.pan_transparent_to_frame_ns = stats.median_ns
		summary.pan_transparent_median_ns = stats.median_ns
		summary.pan_transparent_p95_ns = stats.p95_ns
		summary.pan_transparent_samples = pan_transparent_samples.len
	}
	if pan_opaque_samples.len > 0 {
		stats := summarize_samples(pan_opaque_samples)
		summary.pan_opaque_to_frame_ns = stats.median_ns
		summary.pan_opaque_median_ns = stats.median_ns
		summary.pan_opaque_p95_ns = stats.p95_ns
		summary.pan_opaque_samples = pan_opaque_samples.len
	}
	if zoom_transparent_samples.len > 0 {
		stats := summarize_samples(zoom_transparent_samples)
		summary.zoom_transparent_to_frame_ns = stats.median_ns
		summary.zoom_transparent_median_ns = stats.median_ns
		summary.zoom_transparent_p95_ns = stats.p95_ns
		summary.zoom_transparent_samples = zoom_transparent_samples.len
	}
	if zoom_opaque_samples.len > 0 {
		stats := summarize_samples(zoom_opaque_samples)
		summary.zoom_opaque_to_frame_ns = stats.median_ns
		summary.zoom_opaque_median_ns = stats.median_ns
		summary.zoom_opaque_p95_ns = stats.p95_ns
		summary.zoom_opaque_samples = zoom_opaque_samples.len
	}
	summary.frame_samples = frames.len
	summary.checksum = checksum
	return summary
}

fn new_benchmark_live_trace_with_clock(path string, launch_value string, wall_now_us i64,
	mono_now_ns u64, process_launch_ns u64) BenchmarkLiveTrace {
	launch_ns := benchmark_launch_mono_ns(launch_value, wall_now_us, mono_now_ns, process_launch_ns)
	launch_mono_us := i64(launch_ns / 1000)
	mut trace := BenchmarkLiveTrace{
		path:             path
		launch_us:        launch_mono_us
		launch_mono_us:   launch_mono_us
		frame_target:     1440
		warmup_frames:    60
		transform_counts: map[string]int{}
		phase_trace:      new_startup_phase_trace(launch_ns)
	}
	trace.frame_target = os.getenv('IMAGE_UI_BENCHMARK_FRAME_TARGET').int()
	if trace.frame_target < 2 {
		trace.frame_target = 1440
	}
	trace.warmup_frames = os.getenv('IMAGE_UI_BENCHMARK_WARMUP_FRAMES').int()
	if trace.warmup_frames < 0 || trace.warmup_frames >= trace.frame_target {
		trace.warmup_frames = trace.frame_target / 6
	}
	trace.enabled = path.len > 0
	trace.mark_phase(.process_launch, launch_ns)
	return trace
}

pub fn new_benchmark_live_trace() BenchmarkLiveTrace {
	path := os.getenv('IMAGE_UI_BENCHMARK_TRACE')
	launch_value := os.getenv('IMAGE_UI_BENCHMARK_LAUNCH_US')
	wall_now_us := benchmark_wall_time_us()
	mono_now_ns := time.sys_mono_now()
	return new_benchmark_live_trace_with_clock(path, launch_value, wall_now_us, mono_now_ns,
		benchmark_process_launch_ns)
}

fn (mut trace BenchmarkLiveTrace) begin_frame(width int, height int) {
	if !trace.enabled {
		return
	}
	now := i64(time.sys_mono_now() / 1000)
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

fn (mut trace BenchmarkLiveTrace) end_frame(path string, scan_complete bool, content_ready bool) {
	if !trace.enabled {
		return
	}
	now_mono_us := i64(time.sys_mono_now() / 1000)
	trace.frame_count++
	trace.frame_content_ready = content_ready
	trace.frame_scan_complete = scan_complete
	if trace.pending_resize {
		trace.write_event('resize_observed', trace.last_width, trace.last_height, trace.frame_count, 0, '')
		trace.pending_resize = false
	}
	for pending in trace.pending_actions {
		trace.write_event('action_presented', trace.last_width, trace.last_height, trace.frame_count,
			now_mono_us - pending.at_us, pending.action)
	}
	trace.pending_actions.clear()
	if trace.frame_count >= trace.frame_target && !trace.finished {
		trace.write_event('repeat_counters', trace.last_width, trace.last_height, trace.frame_count,
			trace.left_input_count + trace.right_input_count,
			'left:${trace.left_input_count},right:${trace.right_input_count}')
		counters := benchmark_counters_from_metrics(trace.pipeline_metrics, trace.prefetch_metrics,
			trace.cache_metrics)
		trace.write_event('pipeline_counters', trace.last_width, trace.last_height, trace.frame_count,
			counters.requested, benchmark_counters_report(counters))
		for frame in trace.frames {
			trace.write_event('frame_interval', frame.width, frame.height, frame.order, frame.interval_us, '')
		}
		trace.write_event('complete', trace.last_width, trace.last_height, trace.frame_count, 0, path)
		trace.finished = true
		sapp.request_quit()
	}
}

pub fn (mut trace BenchmarkLiveTrace) complete_frame() {
	if !trace.enabled {
		return
	}
	now_mono_us := i64(time.sys_mono_now() / 1000)
	if trace.frame_content_ready && !trace.has_content {
		trace.has_content = true
		trace.mark_phase(.first_content, u64(now_mono_us) * 1000)
		trace.write_event('first_content', trace.last_width, trace.last_height, trace.frame_count,
			now_mono_us - trace.launch_mono_us, '')
	}
	if trace.frame_scan_complete && !trace.has_scan {
		trace.has_scan = true
		trace.mark_phase(.directory_completion, u64(now_mono_us) * 1000)
		trace.write_event('scan_complete', trace.last_width, trace.last_height, trace.frame_count, 0, '')
	}
}

pub fn (mut trace BenchmarkLiveTrace) on_prefetch(path string) {
	if !trace.enabled || path.len == 0 {
		return
	}
	trace.write_event('prefetch_cached', trace.last_width, trace.last_height, trace.frame_count, 0, path)
}

pub fn (mut trace BenchmarkLiveTrace) on_pipeline(metrics ImagePipelineMetrics, prefetch ImagePrefetchMetrics, cache SiblingResourceCacheMetrics) {
	if !trace.enabled {
		return
	}
	trace.pipeline_metrics = metrics
	trace.prefetch_metrics = prefetch
	trace.cache_metrics = cache
}

fn (mut trace BenchmarkLiveTrace) action_detail(action string) string {
	if action == 'toggle' {
		trace.toggle_count++
		return if trace.toggle_count == 1 { action } else { 'toggle_restore' }
	}
	if action.starts_with('pan_') || action.starts_with('zoom_') {
		count := (trace.transform_counts[action] or { 0 }) + 1
		trace.transform_counts[action] = count
		return '${action}:${count}'
	}
	return action
}

fn (mut trace BenchmarkLiveTrace) on_key(code ui2.KeyCode) {
	if !trace.enabled {
		return
	}
	action := trace.action_detail(benchmark_key_action(code))
	if code == .left {
		trace.left_input_count++
	} else if code == .right {
		trace.right_input_count++
	}
	now_mono_us := i64(time.sys_mono_now() / 1000)
	if !trace.has_input {
		trace.has_input = true
		trace.mark_phase(.first_input, u64(now_mono_us) * 1000)
		trace.write_event('first_input', trace.last_width, trace.last_height, trace.frame_count,
			now_mono_us - trace.launch_mono_us, action)
	}
	trace.write_event('input_key', trace.last_width, trace.last_height, trace.frame_count,
		now_mono_us - trace.launch_mono_us, action)
	if action != '' {
		trace.pending_actions << LivePendingAction{ action: action, at_us: now_mono_us }
	}
}

fn (mut trace BenchmarkLiveTrace) on_pointer(action string) {
	if !trace.enabled {
		return
	}
	now_mono_us := i64(time.sys_mono_now() / 1000)
	if !trace.has_input {
		trace.has_input = true
		trace.mark_phase(.first_input, u64(now_mono_us) * 1000)
		trace.write_event('first_input', trace.last_width, trace.last_height, trace.frame_count,
			now_mono_us - trace.launch_mono_us, action)
	}
	trace.write_event('input_pointer', trace.last_width, trace.last_height, trace.frame_count,
		now_mono_us - trace.launch_mono_us, action)
	if action != '' {
		trace.pending_actions << LivePendingAction{ action: trace.action_detail(action), at_us: now_mono_us }
	}
}

pub fn (mut trace BenchmarkLiveTrace) mark_phase(phase ui2.StartupPhase, at_ns u64) {
	if !trace.phase_trace.mark_at(phase, at_ns) {
		return
	}
	if mark := trace.phase_trace.mark_for(phase) {
		trace.write_phase_event(mark)
	}
}

fn (mut trace BenchmarkLiveTrace) write_phase_event(mark StartupPhaseMark) {
	if !trace.enabled || trace.path == '' {
		return
	}
	mut file := os.open_append(trace.path) or { return }
	file.writeln('phase\t${mark.elapsed_ns / 1000}\t0\t0\t${mark.order}\t${mark.elapsed_ns / 1000}\t${ui2.startup_phase_name(mark.phase)}') or {}
	file.close()
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
		else { '' }
	}
}
