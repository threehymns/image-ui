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
	assert os.file_name(fixtures.alpha) == 'alpha.tga'
	assert os.file_name(fixtures.opaque) == 'opaque.bmp'
	assert os.file_name(fixtures.large_4k) == 'large-4k.bmp'
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

fn test_benchmark_config_exposes_fixed_sample_and_cache_controls() {
	config := parse_benchmark_config(['--warmup', '3', '--iterations', '7', '--cache', 'cold']) or {
		panic(err)
	}
	assert config.warmup == 3
	assert config.iterations == 7
	assert config.cache == .cold
	assert parse_benchmark_config(['--cache', 'warm']) or { panic(err) }.cache == .warm
}

fn test_live_trace_summary_reports_required_phases_and_frame_percentiles() {
	path := os.join_path(os.temp_dir(), 'image-ui-live-trace-${os.getpid()}.tsv')
	trace := [
		'process_launch\t1000\t0\t0\t0\t0',
		'first_content\t16000\t3840\t2160\t0\t15000',
		'first_input\t21000\t3840\t2160\t0\t20000',
		'input_key\t21000\t3840\t2160\t1\t10000',
		'action_presented\t22667\t3840\t2160\t2\t1667\ttoggle',
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
	assert summary.resize_to_frame_ns == 0
	assert summary.viewport_width == 2560
	assert summary.viewport_height == 1440
	assert summary.frame_median_ns == 16_667_000
	assert summary.frame_p95_ns == 16_667_000
	assert summary.frame_samples == 2
	assert summary.complete
}
