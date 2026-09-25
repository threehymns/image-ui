module main

import os

fn test_benchmark_sample_summary_uses_fixed_percentiles() {
	mut samples := []i64{}
	for value in [20, 1, 10, 2, 19, 3, 18, 4, 17, 5, 16, 6, 15, 7, 14, 8, 13, 9, 12, 11] {
		samples << i64(value)
	}
	summary := summarize_samples(samples)
	assert summary.median_ns == 10
	assert summary.p95_ns == 19
}

fn test_benchmark_counter_encoder_round_trips_trace_report() {
	counters := BenchmarkCounters{
		requested:                 7
		displayed:                 2
		skipped:                   3
		coalesced:                 1
		prefetch_requested:        4
		prefetched:                2
		prefetch_skipped:          1
		prefetch_coalesced:        1
		prefetch_cancelled:        1
		prefetch_decodes:          2
		decode_count:              3
		max_pending:               0
		max_total_pending:         0
		cache_hits:                5
		cache_misses:              4
		cache_updates:             1
		cache_evictions:           0
		cache_invalidations:       1
		cache_content_validations: 2
		cache_bytes:               100
		cache_peak_bytes:          120
		cache_cpu_bytes:           60
		cache_renderer_bytes:      40
		cache_budget:              200
	}
	report := benchmark_counters_report(counters)
	assert report == 'displayed:2,skipped:3,coalesced:1,prefetch_requested:4,prefetched:2,prefetch_skipped:1,prefetch_coalesced:1,prefetch_cancelled:1,decodes:3,prefetch_decodes:2,cache_hits:5,cache_misses:4,cache_updates:1,cache_evictions:0,cache_invalidations:1,cache_content_validations:2,cache_resident_bytes:100,cache_peak_bytes:120,cache_cpu_bytes:60,cache_renderer_bytes:40,cache_budget:200'
	assert benchmark_counters_observation(counters).starts_with('requested:7:displayed:2')
	assert benchmark_counters_from_report(report, counters.requested) == counters
}

fn test_benchmark_launch_clock_conversion_and_fallback() {
	assert benchmark_launch_mono_ns('9000', 10000, 8_000_000, 7_800_000) == 7_000_000
	assert benchmark_launch_mono_ns('10000', 10000, 8_000_000, 7_800_000) == 8_000_000
	assert benchmark_launch_mono_ns('', 10000, 8_000_000, 7_800_000) == 7_800_000
	assert benchmark_launch_mono_ns('0', 10000, 8_000_000, 7_800_000) == 7_800_000
	assert benchmark_launch_mono_ns('not-a-time', 10000, 8_000_000, 7_800_000) == 7_800_000
	assert benchmark_launch_mono_ns('10001', 10000, 8_000_000, 7_800_000) == 7_800_000
	assert benchmark_launch_mono_ns('100000000000000000000000', 10000, 8_000_000, 7_800_000) == 7_800_000
	assert benchmark_fallback_launch_ns(0, 8_000_000) == 8_000_000
	assert benchmark_fallback_launch_ns(9_000_000, 8_000_000) == 8_000_000
}

fn test_live_trace_uses_converted_launch_for_phase_output() {
	path := os.join_path(os.temp_dir(), 'image-ui-launch-trace-${os.getpid()}.tsv')
	os.rm(path) or {}
	defer {
		os.rm(path) or {}
	}
	mut trace := new_benchmark_live_trace_with_clock(path, '9000', 10000, 8_000_000, 7_800_000)
	assert trace.launch_us == 7000
	assert trace.launch_mono_us == 7000
	process_mark := trace.phase_trace.mark_for(.process_launch) or { panic('missing process launch mark') }
	assert process_mark.monotonic_ns == 7_000_000
	trace.mark_phase(.window_creation, 8_000_000)
	rows := os.read_lines(path) or { panic(err) }
	assert rows.len == 2
	process_row := rows[0].split('\t')
	window_row := rows[1].split('\t')
	assert process_row[6] == 'process_launch'
	assert window_row[1] == '1000'
	assert window_row[6] == 'window_creation'
}

fn test_benchmark_fixture_generation_is_deterministic_and_decodable() {
	root := os.join_path(os.temp_dir(), 'image-ui-benchmark-fixtures-${os.getpid()}')
	os.rmdir_all(root) or {}
	defer {
		os.rmdir_all(root) or {}
	}

	fixtures := generate_benchmark_fixtures(root, 128) or { panic(err) }
	assert os.exists(fixtures.alpha)
	assert os.exists(fixtures.opaque)
	assert os.exists(fixtures.large_4k)
	assert os.exists(fixtures.large_alpha)
	assert os.exists(fixtures.large_sibling_previous)
	assert os.exists(fixtures.large_sibling_next)
	assert os.file_name(fixtures.alpha) == 'alpha.tga'
	assert os.file_name(fixtures.opaque) == 'opaque.bmp'
	assert os.file_name(fixtures.large_4k) == 'large-4k.bmp'
	assert os.file_name(fixtures.large_alpha) == 'large-alpha.tga'
	assert fixtures.sibling_count == 128

	alpha := load_image_metadata(fixtures.alpha) or { panic(err) }
	opaque := load_image_metadata(fixtures.opaque) or { panic(err) }
	large := load_image_metadata(fixtures.large_4k) or { panic(err) }
	assert alpha.width == 64
	assert alpha.height == 64
	assert alpha.original_channels == 4
	assert opaque.width == 96
	assert opaque.height == 64
	assert opaque.original_channels == 3
	assert large.width == 3840
	assert large.height == 2160
	assert find_first_image_in_dir(fixtures.siblings) or { panic(err) } == fixtures.sibling(0)

	opaque_bytes := os.read_bytes(fixtures.opaque) or { panic(err) }
	assert benchmark_checksum(opaque_bytes) == benchmark_checksum(encode_opaque_bmp(96, 64, 17))
}

fn test_viewer_screen_can_be_built_at_explicit_size() {
	mut app := &ViewerApp{}
	app.core = new_app()
	app.window_ready = true
	app.core.set_image_loaded('sample.png', 3840, 2160)

	screen := app.build_screen_at_size(3840, 2160)
	assert screen.children.len == 2
	assert screen.children[0].id == 'transparency_background'
	assert screen.children[0].background.pattern.valid()
	assert screen.children[0].background.pattern.pixel_width == 32
	assert screen.children[0].background.pattern.pixel_height == 32
	assert screen.children[0].background.pattern.pixel_width < 3840
	assert screen.children[0].background.pattern.pixel_height < 2160
	assert app.core.canvas_w == 3840
	assert app.core.canvas_h == 2160
}

fn test_resident_switch_benchmark_reports_sibling_request_counters() {
	root := os.join_path(os.temp_dir(), 'image-ui-benchmark-switch-${os.getpid()}')
	os.rmdir_all(root) or {}
	defer {
		os.rmdir_all(root) or {}
	}
	fixtures := generate_benchmark_fixtures(root, 4) or { panic(err) }
	sample := execute_benchmark_operation(BenchmarkOperation{
		kind:               .resident_sibling_switch
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(1)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 1024 * 1024
	}, 0)
	assert sample.checksum != 0
	assert sample.counters.requested == 1
	assert sample.counters.displayed == 1
	assert sample.counters.skipped == 0
	assert sample.counters.coalesced == 0
}

fn test_integration_benchmark_rows_cover_transform_variants_and_invalidation() {
	root := os.join_path(os.temp_dir(), 'image-ui-benchmark-integration-${os.getpid()}')
	os.rmdir_all(root) or {}
	defer {
		os.rmdir_all(root) or {}
	}
	fixtures := generate_benchmark_fixtures(root, 4) or { panic(err) }
	for operation in [
		BenchmarkOperation{
			kind:         .pan_4k_transparent
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'visual-contract'
			frame_action: .pan
			opacity:      .has_alpha
		},
		BenchmarkOperation{
			kind:         .pan_4k_opaque
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'visual-contract'
			frame_action: .pan
			opacity:      .proven_opaque
		},
		BenchmarkOperation{
			kind:         .zoom_4k_transparent
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'visual-contract'
			frame_action: .zoom
			opacity:      .has_alpha
		},
		BenchmarkOperation{
			kind:         .zoom_4k_opaque
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'visual-contract'
			frame_action: .zoom
			opacity:      .proven_opaque
		},
		BenchmarkOperation{
			kind:   .toggle_checkerboard_4k
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'visual-contract'
		},
	] {
		sample := execute_benchmark_operation(operation, 0)
		assert sample.checksum != 0
		assert sample.elapsed_ns >= 0
	}
	invalidation := execute_benchmark_operation(BenchmarkOperation{
		kind:               .sibling_cache_invalidation
		path:               fixtures.opaque
		cache:              'sibling-lru-invalidation'
		cache_budget_bytes: 64 * 1024
	}, 0)
	assert invalidation.counters.decode_count == 1
	assert invalidation.counters.cache_invalidations == 1
	assert invalidation.counters.cache_misses == 1
}

fn test_benchmark_config_exposes_fixed_sample_and_cache_controls() {
	config := parse_benchmark_config(['--warmup', '3', '--iterations', '7', '--cache', 'cold']) or {
		panic(err)
	}
	assert config.warmup == 3
	assert config.iterations == 7
	assert config.cache == .cold
	assert parse_benchmark_config(['--cache', 'warm']) or { panic(err) }.cache == .warm
	config_with_budget := parse_benchmark_config(['--cache-budget', '65536']) or { panic(err) }
	assert config_with_budget.cache_budget_bytes == 65536
	assert benchmark_cache_budgets(config_with_budget) == [65536]
}

fn test_live_trace_benchmark_keys_use_variant_pointer_actions() {
	assert benchmark_key_action(.p) == ''
	assert benchmark_key_action(.z) == ''
	assert benchmark_key_action(.t) == 'toggle'
	mut trace := new_benchmark_live_trace()
	trace.enabled = true
	trace.on_pointer('pan_transparent')
	assert trace.has_input
	assert trace.pending_actions.len == 1
	assert trace.pending_actions[0].action == 'pan_transparent:1'
	trace.pending_actions.clear()
	trace.on_pointer('zoom_opaque')
	assert trace.pending_actions.len == 1
	assert trace.pending_actions[0].action == 'zoom_opaque:1'
	trace.pending_actions.clear()
	trace.on_key(.t)
	assert trace.pending_actions[0].action == 'toggle'
	trace.pending_actions.clear()
	trace.on_key(.t)
	assert trace.pending_actions[0].action == 'toggle_restore'
}

fn test_live_trace_marks_content_after_frame_completion() {
	mut trace := new_benchmark_live_trace()
	trace.enabled = true
	trace.path = ''
	trace.end_frame('sample.bmp', false, true)
	assert trace.phase_trace.mark_for(.first_content) == none
	trace.complete_frame()
	assert trace.phase_trace.mark_for(.first_content) != none
}

fn test_live_trace_summary_reports_required_phases_and_frame_percentiles() {
	path := os.join_path(os.temp_dir(), 'image-ui-live-trace-${os.getpid()}.tsv')
	trace := [
		'phase\t1000\t0\t0\t0\t0\tprocess_launch',
		'phase\t2000\t0\t0\t1\t1000\twindow_creation',
		'phase\t3000\t0\t0\t2\t2000\tfont_work',
		'phase\t4000\t0\t0\t3\t3000\tui2_setup',
		'phase\t5000\t0\t0\t4\t4000\tgpu_context_initialization',
		'phase\t16000\t0\t0\t5\t15000\tfirst_content',
		'phase\t19500\t0\t0\t6\t18500\tdirectory_completion',
		'phase\t21000\t0\t0\t7\t20000\tfirst_input',
		'process_launch\t1000\t0\t0\t0\t0',
		'first_content\t16000\t3840\t2160\t0\t15000',
		'first_input\t21000\t3840\t2160\t0\t20000',
		'input_key\t21000\t3840\t2160\t1\t10000',
		'action_presented\t22667\t3840\t2160\t2\t1667\ttoggle',
		'action_presented\t23000\t3840\t2160\t2\t300\tpan_transparent:1',
		'action_presented\t23100\t3840\t2160\t2\t500\tpan_transparent:2',
		'action_presented\t23333\t3840\t2160\t2\t600\tpan_opaque:1',
		'action_presented\t23433\t3840\t2160\t2\t800\tpan_opaque:2',
		'action_presented\t23666\t3840\t2160\t2\t900\tzoom_transparent:1',
		'action_presented\t23766\t3840\t2160\t2\t1100\tzoom_transparent:2',
		'action_presented\t24000\t3840\t2160\t2\t1200\tzoom_opaque:1',
		'action_presented\t24100\t3840\t2160\t2\t1400\tzoom_opaque:2',
		'prefetch_cached\t22000\t3840\t2160\t1\t0\tsibling.bmp',
		'pipeline_counters\t89335\t2560\t1440\t6\t2\tdisplayed:2,skipped:0,coalesced:0,prefetch_requested:3,prefetched:1,prefetch_skipped:2,prefetch_coalesced:0,prefetch_cancelled:1,decodes:2,prefetch_decodes:1,cache_hits:4,cache_misses:2,cache_updates:1,cache_evictions:0,cache_invalidations:1,cache_content_validations:1,cache_resident_bytes:100,cache_peak_bytes:120,cache_cpu_bytes:60,cache_renderer_bytes:60,cache_budget:200',
		'repeat_counters\t89335\t2560\t1440\t6\t16\tleft:8,right:8',
		'frame_interval\t22667\t3840\t2160\t3\t16667',
		'frame_interval\t39334\t3840\t2160\t4\t16667',
		'resize_observed\t56001\t2560\t1440\t5\t0',
		'complete\t89335\t2560\t1440\t6\t0\tsibling-007.bmp',
	].join('\n')
	os.write_file(path, trace) or { panic(err) }
	defer {
		os.rm(path) or {}
	}

	summary := summarize_live_trace(path, 1, 60) or { panic(err) }
	assert summary.process_to_first_content_ns == 15_000_000
	assert summary.process_to_first_input_ns == 20_000_000
	assert summary.toggle_to_frame_ns == 1_667_000
	assert summary.prefetch_cached_events == 1
	assert summary.counters.requested == 2
	assert summary.counters.displayed == 2
	assert summary.counters.prefetch_requested == 3
	assert summary.counters.prefetched == 1
	assert summary.counters.prefetch_skipped == 2
	assert summary.counters.prefetch_cancelled == 1
	assert summary.counters.decode_count == 2
	assert summary.counters.prefetch_decodes == 1
	assert summary.counters.cache_hits == 4
	assert summary.counters.cache_misses == 2
	assert summary.counters.cache_invalidations == 1
	assert summary.counters.cache_content_validations == 1
	assert summary.counters.cache_peak_bytes == 120
	assert summary.counters.cache_budget == 200
	assert summary.left_input_count == 8
	assert summary.right_input_count == 8
	assert summary.resize_to_frame_ns == 0
	assert summary.viewport_width == 2560
	assert summary.viewport_height == 1440
	assert summary.frame_median_ns == 16_667_000
	assert summary.frame_p95_ns == 16_667_000
	assert summary.frame_samples == 2
	assert summary.pan_transparent_to_frame_ns == 400_000
	assert summary.pan_transparent_median_ns == 400_000
	assert summary.pan_transparent_p95_ns == 500_000
	assert summary.pan_transparent_samples == 2
	assert summary.pan_opaque_to_frame_ns == 700_000
	assert summary.pan_opaque_median_ns == 700_000
	assert summary.pan_opaque_p95_ns == 800_000
	assert summary.pan_opaque_samples == 2
	assert summary.zoom_transparent_to_frame_ns == 1_000_000
	assert summary.zoom_transparent_median_ns == 1_000_000
	assert summary.zoom_transparent_p95_ns == 1_100_000
	assert summary.zoom_transparent_samples == 2
	assert summary.zoom_opaque_to_frame_ns == 1_300_000
	assert summary.zoom_opaque_median_ns == 1_300_000
	assert summary.zoom_opaque_p95_ns == 1_400_000
	assert summary.zoom_opaque_samples == 2
	assert summary.phase_order == ['process_launch', 'window_creation', 'font_work', 'ui2_setup',
		'gpu_context_initialization', 'first_content', 'directory_completion', 'first_input']
	assert summary.phase_monotonic
	assert summary.phase_ns['window_creation'] == 1_000_000
	assert summary.phase_ns['directory_completion'] == 18_500_000
	assert summary.complete
	assert live_variant_actions_present(summary, 'transparent')
	assert live_variant_actions_present(summary, 'opaque')
	mut opaque_only := summary
	opaque_only.pan_transparent_samples = 0
	opaque_only.zoom_transparent_samples = 0
	assert live_variant_actions_present(opaque_only, 'opaque')
	assert !live_variant_actions_present(opaque_only, 'transparent')
}
