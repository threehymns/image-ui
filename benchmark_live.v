@[has_globals]
module main

import os
import time
import sokol.sapp
import ui2

__global benchmark_process_launch_ns = u64(0)

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
	phase_ns                    map[string]i64
	phase_order                 []string
	phase_monotonic             bool = true
	last_phase_us               i64  = -1
	requested                   int
	displayed                   int
	skipped                     int
	coalesced                   int
	prefetch_requested          int
	prefetched                  int
	prefetch_skipped            int
	prefetch_coalesced          int
	prefetch_cancelled          int
	prefetch_cached             int
	decode_count                int
	prefetch_decodes            int
	cache_hits                  int
	cache_misses                int
	cache_updates               int
	cache_evictions             int
	cache_invalidations         int
	cache_resident_bytes        int
	cache_peak_bytes            int
	cache_cpu_bytes             int
	cache_renderer_bytes        int
	cache_budget                int
	left_input_count            int
	right_input_count           int
}

pub fn summarize_live_trace(path string, warmup_frames int, frame_target int) !LiveTraceSummary {
	rows := os.read_lines(path) or { return err }
	mut frames := []i64{}
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
				match row.detail {
					'toggle' { summary.toggle_to_frame_ns = row.value_us * 1000 }
					'switch' { summary.switch_to_frame_ns = row.value_us * 1000 }
					'pan' { summary.pan_to_frame_ns = row.value_us * 1000 }
					'zoom' { summary.zoom_to_frame_ns = row.value_us * 1000 }
					else {}
				}
			}
			'prefetch_cached' {
				summary.prefetch_cached++
			}
			'pipeline_counters' {
				summary.requested = row.value_us
				for item in row.detail.split(',') {
					counter_parts := item.split(':')
					if counter_parts.len != 2 {
						continue
					}
					match counter_parts[0] {
						'displayed' { summary.displayed = counter_parts[1].int() }
						'skipped' { summary.skipped = counter_parts[1].int() }
						'coalesced' { summary.coalesced = counter_parts[1].int() }
						'prefetch_requested' { summary.prefetch_requested = counter_parts[1].int() }
						'prefetched' { summary.prefetched = counter_parts[1].int() }
						'prefetch_skipped' { summary.prefetch_skipped = counter_parts[1].int() }
						'prefetch_coalesced' { summary.prefetch_coalesced = counter_parts[1].int() }
						'prefetch_cancelled' { summary.prefetch_cancelled = counter_parts[1].int() }
						'decodes' { summary.decode_count = counter_parts[1].int() }
						'prefetch_decodes' { summary.prefetch_decodes = counter_parts[1].int() }
						'cache_hits' { summary.cache_hits = counter_parts[1].int() }
						'cache_misses' { summary.cache_misses = counter_parts[1].int() }
						'cache_updates' { summary.cache_updates = counter_parts[1].int() }
						'cache_evictions' { summary.cache_evictions = counter_parts[1].int() }
						'cache_invalidations' {
							summary.cache_invalidations = counter_parts[1].int()
						}
						'cache_resident_bytes' {
							summary.cache_resident_bytes = counter_parts[1].int()
						}
						'cache_peak_bytes' { summary.cache_peak_bytes = counter_parts[1].int() }
						'cache_cpu_bytes' { summary.cache_cpu_bytes = counter_parts[1].int() }
						'cache_renderer_bytes' {
							summary.cache_renderer_bytes = counter_parts[1].int()
						}
						'cache_budget' { summary.cache_budget = counter_parts[1].int() }
						else {}
					}
				}
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
	summary.frame_samples = frames.len
	summary.checksum = checksum
	return summary
}

pub fn new_benchmark_live_trace() BenchmarkLiveTrace {
	path := os.getenv('IMAGE_UI_BENCHMARK_TRACE')
	launch_ns := if benchmark_process_launch_ns > 0 {
		benchmark_process_launch_ns
	} else {
		time.sys_mono_now()
	}
	launch_mono_us := i64(launch_ns / 1000)
	mut trace := BenchmarkLiveTrace{
		path:           path
		launch_us:      launch_mono_us
		launch_mono_us: launch_mono_us
		frame_target:   360
		warmup_frames:  60
		phase_trace:    new_startup_phase_trace(launch_ns)
	}
	trace.frame_target = os.getenv('IMAGE_UI_BENCHMARK_FRAME_TARGET').int()
	if trace.frame_target < 2 {
		trace.frame_target = 360
	}
	trace.warmup_frames = os.getenv('IMAGE_UI_BENCHMARK_WARMUP_FRAMES').int()
	if trace.warmup_frames < 0 || trace.warmup_frames >= trace.frame_target {
		trace.warmup_frames = trace.frame_target / 6
	}
	trace.enabled = path.len > 0
	trace.mark_phase('process_launch', launch_ns)
	return trace
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
		trace.write_event('pipeline_counters', trace.last_width, trace.last_height, trace.frame_count,
			trace.pipeline_metrics.requested,
			'displayed:${trace.pipeline_metrics.displayed},skipped:${trace.pipeline_metrics.skipped},coalesced:${trace.pipeline_metrics.coalesced},prefetch_requested:${trace.prefetch_metrics.requested},prefetched:${trace.prefetch_metrics.prefetched},prefetch_skipped:${trace.prefetch_metrics.skipped},prefetch_coalesced:${trace.prefetch_metrics.coalesced},prefetch_cancelled:${trace.prefetch_metrics.cancelled},decodes:${trace.pipeline_metrics.decode_count},prefetch_decodes:${trace.prefetch_metrics.decode_count},cache_hits:${trace.cache_metrics.hits},cache_misses:${trace.cache_metrics.misses},cache_updates:${trace.cache_metrics.updates},cache_evictions:${trace.cache_metrics.evictions},cache_invalidations:${trace.cache_metrics.invalidations},cache_resident_bytes:${trace.cache_metrics.resident_bytes},cache_peak_bytes:${trace.cache_metrics.peak_bytes},cache_cpu_bytes:${trace.cache_metrics.cpu_bytes},cache_renderer_bytes:${trace.cache_metrics.renderer_bytes},cache_budget:${trace.pipeline_metrics.cache_budget}')
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
		trace.mark_phase('first_content', u64(now_mono_us) * 1000)
		trace.write_event('first_content', trace.last_width, trace.last_height, trace.frame_count,
			now_mono_us - trace.launch_mono_us, '')
	}
	if trace.frame_scan_complete && !trace.has_scan {
		trace.has_scan = true
		trace.mark_phase('directory_completion', u64(now_mono_us) * 1000)
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

fn (mut trace BenchmarkLiveTrace) on_key(code ui2.KeyCode) {
	if !trace.enabled {
		return
	}
	action := benchmark_key_action(code)
	if code == .left {
		trace.left_input_count++
	} else if code == .right {
		trace.right_input_count++
	}
	now_mono_us := i64(time.sys_mono_now() / 1000)
	if !trace.has_input {
		trace.has_input = true
		trace.mark_phase('first_input', u64(now_mono_us) * 1000)
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
		trace.mark_phase('first_input', u64(now_mono_us) * 1000)
		trace.write_event('first_input', trace.last_width, trace.last_height, trace.frame_count,
			now_mono_us - trace.launch_mono_us, action)
	}
	trace.write_event('input_pointer', trace.last_width, trace.last_height, trace.frame_count,
		now_mono_us - trace.launch_mono_us, action)
	if action != '' {
		trace.pending_actions << LivePendingAction{ action: action, at_us: now_mono_us }
	}
}

pub fn (mut trace BenchmarkLiveTrace) mark_phase(phase string, at_ns u64) {
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
	file.writeln('phase\t${mark.elapsed_ns / 1000}\t0\t0\t${mark.order}\t${mark.elapsed_ns / 1000}\t${mark.phase}') or {}
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
		.p { 'pan' }
		.z { 'zoom' }
		else { '' }
	}
}
