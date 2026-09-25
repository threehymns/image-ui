module main

import os
import time
import ui2

pub const benchmark_key_repeat_steps = 16
pub const benchmark_fast_input_count = 100

pub enum BenchmarkCacheSelection {
	cold
	warm
	both
}

pub struct BenchmarkConfig {
pub mut:
	warmup             int                     = 2
	iterations         int                     = 10
	cache              BenchmarkCacheSelection = .both
	fixtures           string
	cache_budget_bytes int
}

pub struct BenchmarkCounters {
pub mut:
	requested                 int
	displayed                 int
	skipped                   int
	coalesced                 int
	prefetch_requested        int
	prefetched                int
	prefetch_skipped          int
	prefetch_coalesced        int
	prefetch_cancelled        int
	prefetch_decodes          int
	decode_count              int
	max_pending               int
	max_total_pending         int
	cache_hits                int
	cache_misses              int
	cache_updates             int
	cache_evictions           int
	cache_invalidations       int
	cache_content_validations int
	cache_bytes               int
	cache_peak_bytes          int
	cache_cpu_bytes           int
	cache_renderer_bytes      int
	cache_budget              int
}

pub struct BenchmarkSample {
pub:
	elapsed_ns i64
	checksum   u64
	counters   BenchmarkCounters
}

pub struct BenchmarkResult {
pub:
	name                string
	fixture             string
	cache               string
	warmup              int
	iterations          int
	median_ns           i64
	p95_ns              i64
	checksum            u64
	verified            bool
	checksum_samples    int
	checksum_mismatches int
	counters            BenchmarkCounters
	cache_budget        int
}

pub enum BenchmarkFrameAction {
	pan
	zoom
}

pub enum BenchmarkDirection {
	right
	left
}

pub enum BenchmarkOperationKind {
	image_pipeline_load_alpha
	image_pipeline_load_opaque
	image_pipeline_load_4k
	image_worker_load_alpha
	image_worker_load_opaque
	image_worker_load_4k
	sibling_cache_cold
	sibling_cache_warm
	sibling_cache_invalidation
	sibling_cache_4k_cold
	sibling_cache_4k_warm
	sibling_discovery
	sibling_navigation
	resident_sibling_switch
	resident_sibling_switch_4k
	key_repeat_resident_right
	key_repeat_resident_left
	sustained_key_repeat_right
	sustained_key_repeat_left
	key_repeat_faster_than_decode
	pattern_tile
	frame_prepare_4k
	pan_4k_transparent
	pan_4k_opaque
	zoom_4k_transparent
	zoom_4k_opaque
	toggle_checkerboard_4k
	screen_construct_4k
	screen_resize_to_4k
	startup_cpu_cold
	startup_cpu_warm
}

struct BenchmarkOperation {
pub mut:
	kind               BenchmarkOperationKind
	path               string
	secondary_path     string
	width              int
	height             int
	cache              string
	cache_budget_bytes int
	frame_action       BenchmarkFrameAction
	direction          BenchmarkDirection
	opacity            ui2.ImageOpacity
}

fn benchmark_operation_name(kind BenchmarkOperationKind) string {
	return match kind {
		.image_pipeline_load_alpha { 'image_pipeline_load_alpha' }
		.image_pipeline_load_opaque { 'image_pipeline_load_opaque' }
		.image_pipeline_load_4k { 'image_pipeline_load_4k' }
		.image_worker_load_alpha { 'image_worker_load_alpha' }
		.image_worker_load_opaque { 'image_worker_load_opaque' }
		.image_worker_load_4k { 'image_worker_load_4k' }
		.sibling_cache_cold { 'sibling_cache_cold' }
		.sibling_cache_warm { 'sibling_cache_warm' }
		.sibling_cache_invalidation { 'sibling_cache_invalidation' }
		.sibling_cache_4k_cold { 'sibling_cache_4k_cold' }
		.sibling_cache_4k_warm { 'sibling_cache_4k_warm' }
		.sibling_discovery { 'sibling_discovery' }
		.sibling_navigation { 'sibling_navigation' }
		.resident_sibling_switch { 'resident_sibling_switch' }
		.resident_sibling_switch_4k { 'resident_sibling_switch_4k' }
		.key_repeat_resident_right { 'key_repeat_resident_right' }
		.key_repeat_resident_left { 'key_repeat_resident_left' }
		.sustained_key_repeat_right { 'sustained_key_repeat_right' }
		.sustained_key_repeat_left { 'sustained_key_repeat_left' }
		.key_repeat_faster_than_decode { 'key_repeat_faster_than_decode' }
		.pattern_tile { 'pattern_tile' }
		.frame_prepare_4k { 'frame_prepare_4k' }
		.pan_4k_transparent { 'pan_4k_transparent' }
		.pan_4k_opaque { 'pan_4k_opaque' }
		.zoom_4k_transparent { 'zoom_4k_transparent' }
		.zoom_4k_opaque { 'zoom_4k_opaque' }
		.toggle_checkerboard_4k { 'toggle_checkerboard_4k' }
		.screen_construct_4k { 'screen_construct_4k' }
		.screen_resize_to_4k { 'screen_resize_to_4k' }
		.startup_cpu_cold { 'startup_cpu_cold' }
		.startup_cpu_warm { 'startup_cpu_warm' }
	}
}

struct BenchmarkRunner {
pub mut:
	config  BenchmarkConfig
	results []BenchmarkResult
}

pub fn benchmark_main() {
	benchmark_process_launch_ns = time.sys_mono_now()
	args := if os.args.len > 1 { os.args[1..] } else { []string{} }
	if args.len == 0 {
		run_headless_benchmark(BenchmarkConfig{}) or { panic(err) }
		return
	}
	match args[0] {
		'--help', '-h' {
			print_benchmark_help()
		}
		'--prepare-fixtures' {
			if args.len != 2 {
				fatal_benchmark_usage('--prepare-fixtures requires one directory')
			}
			fixtures := generate_benchmark_fixtures(args[1], benchmark_sibling_count) or {
				eprintln('fixture generation failed: ${err}')
				exit(1)
			}
			print_benchmark('Viewer fixtures')
			println('alpha=${fixtures.alpha}')
			println('opaque=${fixtures.opaque}')
			println('large_4k=${fixtures.large_4k}')
			println('large_alpha=${fixtures.large_alpha}')
			println('large_sibling_previous=${fixtures.large_sibling_previous}')
			println('large_sibling_next=${fixtures.large_sibling_next}')
			println('siblings=${fixtures.siblings}')
			println('sibling_count=${fixtures.sibling_count}')
		}
		'--wayland-smoke' {
			if args.len != 2 {
				fatal_benchmark_usage('--wayland-smoke requires one target image')
			}
			run_wayland_smoke(args[1]) or {
				eprintln('Wayland smoke failed: ${err}')
				exit(1)
			}
		}
		else {
			config := parse_benchmark_config(args) or {
				fatal_benchmark_usage(err.msg())
				return
			}
			run_headless_benchmark(config) or {
				eprintln('benchmark failed: ${err}')
				exit(1)
			}
		}
	}
}

fn parse_benchmark_config(args []string) !BenchmarkConfig {
	mut config := BenchmarkConfig{}
	mut index := 0
	for index < args.len {
		match args[index] {
			'--warmup' {
				index++
				if index >= args.len {
					return error('--warmup requires a positive integer')
				}
				config.warmup = args[index].int()
			}
			'--iterations' {
				index++
				if index >= args.len {
					return error('--iterations requires a positive integer')
				}
				config.iterations = args[index].int()
			}
			'--cache' {
				index++
				if index >= args.len {
					return error('--cache requires cold, warm, or both')
				}
				config.cache = match args[index] {
					'cold' { BenchmarkCacheSelection.cold }
					'warm' { BenchmarkCacheSelection.warm }
					'both' { BenchmarkCacheSelection.both }
					else { return error('--cache requires cold, warm, or both') }
				}
			}
			'--fixtures' {
				index++
				if index >= args.len {
					return error('--fixtures requires a directory')
				}
				config.fixtures = args[index]
			}
			'--cache-budget' {
				index++
				if index >= args.len {
					return error('--cache-budget requires a byte count')
				}
				config.cache_budget_bytes = args[index].int()
				if config.cache_budget_bytes < 0 {
					return error('--cache-budget cannot be negative')
				}
			}
			else {
				return error('unknown option: ${args[index]}')
			}
		}
		index++
	}
	if config.warmup < 0 {
		return error('warmup cannot be negative')
	}
	if config.iterations < 2 {
		return error('iterations must be at least 2 for p95 reporting')
	}
	return config
}

fn benchmark_cache_budgets(config BenchmarkConfig) []int {
	if config.cache_budget_bytes > 0 {
		return [config.cache_budget_bytes]
	}
	return [16 * 1024, 32 * 1024, 64 * 1024]
}

fn run_headless_benchmark(config BenchmarkConfig) ! {
	owned_root := config.fixtures == ''
	root := if owned_root {
		os.join_path(os.temp_dir(), 'image-ui-benchmark-${os.getpid()}')
	} else {
		config.fixtures
	}
	fixture_started := time.new_stopwatch()
	fixtures := generate_benchmark_fixtures(root, benchmark_sibling_count) or { return err }
	fixture_elapsed := fixture_started.elapsed().nanoseconds()

	mut runner := BenchmarkRunner{
		config:  config
		results: []
	}
	runner.add(BenchmarkOperation{
		kind:  .image_pipeline_load_alpha
		path:  fixtures.alpha
		cache: 'no-app-cache'
	})
	runner.add(BenchmarkOperation{
		kind:  .image_pipeline_load_opaque
		path:  fixtures.opaque
		cache: 'no-app-cache'
	})
	runner.add(BenchmarkOperation{
		kind:  .image_pipeline_load_4k
		path:  fixtures.large_4k
		cache: 'no-app-cache'
	})
	for operation in [
		BenchmarkOperation{
			kind:  .image_worker_load_alpha
			path:  fixtures.alpha
			cache: 'worker-resource'
		},
		BenchmarkOperation{
			kind:  .image_worker_load_opaque
			path:  fixtures.opaque
			cache: 'worker-resource'
		},
		BenchmarkOperation{
			kind:  .image_worker_load_4k
			path:  fixtures.large_4k
			cache: 'worker-resource'
		},
	] {
		runner.add(operation)
	}
	for budget_bytes in benchmark_cache_budgets(config) {
		if config.cache == .cold || config.cache == .both {
			runner.add(BenchmarkOperation{
				kind:               .sibling_cache_cold
				path:               fixtures.opaque
				cache:              'sibling-lru'
				cache_budget_bytes: budget_bytes
			})
		}
		if config.cache == .warm || config.cache == .both {
			runner.add(BenchmarkOperation{
				kind:               .sibling_cache_warm
				path:               fixtures.opaque
				cache:              'sibling-lru'
				cache_budget_bytes: budget_bytes
			})
		}
	}
	if config.cache == .cold || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:               .sibling_cache_invalidation
			path:               fixtures.opaque
			cache:              'sibling-lru-invalidation'
			cache_budget_bytes: 64 * 1024
		})
	}
	if config.cache == .cold || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:               .sibling_cache_4k_cold
			path:               fixtures.large_4k
			cache:              'sibling-lru'
			cache_budget_bytes: 256 * 1024 * 1024
		})
	}
	if config.cache == .warm || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:               .sibling_cache_4k_warm
			path:               fixtures.large_4k
			cache:              'sibling-lru'
			cache_budget_bytes: 256 * 1024 * 1024
		})
	}
	runner.add(BenchmarkOperation{
		kind:  .sibling_discovery
		path:  fixtures.sibling(0)
		cache: 'filesystem'
	})
	runner.add(BenchmarkOperation{
		kind:  .sibling_navigation
		path:  fixtures.sibling(64)
		cache: 'no-app-cache'
	})
	runner.add(BenchmarkOperation{
		kind:               .resident_sibling_switch
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(1)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               .resident_sibling_switch_4k
		path:               fixtures.large_4k
		secondary_path:     fixtures.large_sibling_next
		width:              benchmark_large_width
		height:             benchmark_large_height
		cache:              'sibling-lru-resident'
		cache_budget_bytes: default_sibling_cache_budget_bytes
	})
	runner.add(BenchmarkOperation{
		kind:               .key_repeat_resident_right
		direction:          .right
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(benchmark_key_repeat_steps)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               .key_repeat_resident_left
		direction:          .left
		path:               fixtures.sibling(benchmark_key_repeat_steps)
		secondary_path:     fixtures.sibling(0)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               .sustained_key_repeat_right
		direction:          .right
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(benchmark_key_repeat_steps)
		width:              1024
		height:             768
		cache:              'sustained-sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               .sustained_key_repeat_left
		direction:          .left
		path:               fixtures.sibling(benchmark_key_repeat_steps)
		secondary_path:     fixtures.sibling(0)
		width:              1024
		height:             768
		cache:              'sustained-sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               .key_repeat_faster_than_decode
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(benchmark_fast_input_count)
		width:              1024
		height:             768
		cache:              'manual-pipeline'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:  .pattern_tile
		cache: 'constant'
	})
	runner.add(BenchmarkOperation{
		kind:   .frame_prepare_4k
		path:   fixtures.large_4k
		width:  benchmark_large_width
		height: benchmark_large_height
		cache:  'pattern-resource'
	})
	for operation in [
		BenchmarkOperation{
			kind:         .pan_4k_transparent
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'pattern-resource'
			frame_action: .pan
			opacity:      .has_alpha
		},
		BenchmarkOperation{
			kind:         .pan_4k_opaque
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'opaque-resource'
			frame_action: .pan
			opacity:      .proven_opaque
		},
		BenchmarkOperation{
			kind:         .zoom_4k_transparent
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'pattern-resource'
			frame_action: .zoom
			opacity:      .has_alpha
		},
		BenchmarkOperation{
			kind:         .zoom_4k_opaque
			width:        benchmark_large_width
			height:       benchmark_large_height
			cache:        'opaque-resource'
			frame_action: .zoom
			opacity:      .proven_opaque
		},
	] {
		runner.add(operation)
	}
	runner.add(BenchmarkOperation{
		kind:   .toggle_checkerboard_4k
		width:  benchmark_large_width
		height: benchmark_large_height
		cache:  'pattern-resource'
	})

	if config.cache == .cold || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:   .screen_construct_4k
			path:   fixtures.opaque
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'pattern-resource'
		})
		runner.add(BenchmarkOperation{
			kind:   .screen_resize_to_4k
			path:   fixtures.opaque
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'pattern-resource'
		})
		runner.add(BenchmarkOperation{
			kind:   .startup_cpu_cold
			path:   fixtures.large_4k
			width:  1024
			height: 768
			cache:  'startup-cold'
		})
	}
	if config.cache == .warm || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:   .screen_construct_4k
			path:   fixtures.opaque
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'pattern-resource'
		})
		runner.add(BenchmarkOperation{
			kind:   .startup_cpu_warm
			path:   fixtures.large_4k
			width:  1024
			height: 768
			cache:  'startup-warm'
		})
	}

	print_benchmark('Viewer headless benchmark')
	build := benchmark_build_info()
	hardware := benchmark_hardware_info()
	println('build_commit=${build.commit} build_state=${build.dirty} module=${build.module}')
	println('v=${build.v_version}')
	println('compiler=${build.compiler}')
	println('compile_flags=${build.compile_flag}')
	println('hardware=${hardware.os_name} ${hardware.architecture} cpu=${hardware.cpu_model} logical_cpus=${hardware.logical_cpus} memory=${hardware.memory} gpu_driver=${hardware.gpu_driver}')
	println('config=warmup:${config.warmup} iterations:${config.iterations} cache:${benchmark_cache_name(config.cache)} cache_budget_override:${config.cache_budget_bytes}')
	println('fixtures=alpha:64x64 opaque:96x64 large_4k:${benchmark_large_width}x${benchmark_large_height} large_alpha:${benchmark_large_width}x${benchmark_large_height} large_siblings:2 siblings:${fixtures.sibling_count} generation_ms=${benchmark_ms(fixture_elapsed)}')
	println('cache_note=image rows have no application cache; sibling-lru rows use the full-resolution resource cache')
	println('sibling_counter_note=requested/displayed/skipped/coalesced count user Sibling requests; prefetch columns count Neighborhood candidates and accepted cache insertions')
	println('cache_separation=Filmstrip Thumbnail Cache remains a separate cache and is not included in sibling-lru budget accounting')
	println('pattern_note=the Viewer uses one 32x32 logical repeat tile; no full-window raster is generated')
	println('measurement=screen rows build UI2 elements only and do not include GPU submission')
	println('decode_note=decodes count full decoder invocations; cache hits and prefetched resources do not decode again')
	println('fixed_iteration_note=every row runs the configured warmup count and exactly the configured measured iteration count; each measured checksum and counter set is checked')
	println('| case | fixture | cache | budget bytes | warmup | iterations | median ms | p95 ms | decodes | prefetch decodes | requested | displayed | skipped | coalesced | prefetch requested | prefetched | prefetch skipped | prefetch coalesced | prefetch cancelled | max pending | max total pending | hits | misses | updates | evictions | invalidations | content validations | resident bytes | peak bytes | cpu bytes | renderer bytes | checksum | checksum samples | checksum mismatches | status |')
	println('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | --- | --- |')
	mut verified := true
	for result in runner.results {
		status := if result.verified { 'ok' } else { 'checksum-or-counter-mismatch' }
		counters := result.counters
		println('| ${result.name} | ${os.file_name(result.fixture)} | ${result.cache} | ${result.cache_budget} | ${result.warmup} | ${result.iterations} | ${benchmark_ms(result.median_ns)} | ${benchmark_ms(result.p95_ns)} | ${counters.decode_count} | ${counters.prefetch_decodes} | ${counters.requested} | ${counters.displayed} | ${counters.skipped} | ${counters.coalesced} | ${counters.prefetch_requested} | ${counters.prefetched} | ${counters.prefetch_skipped} | ${counters.prefetch_coalesced} | ${counters.prefetch_cancelled} | ${counters.max_pending} | ${counters.max_total_pending} | ${counters.cache_hits} | ${counters.cache_misses} | ${counters.cache_updates} | ${counters.cache_evictions} | ${counters.cache_invalidations} | ${counters.cache_content_validations} | ${counters.cache_bytes} | ${counters.cache_peak_bytes} | ${counters.cache_cpu_bytes} | ${counters.cache_renderer_bytes} | ${result.checksum.hex()} | ${result.checksum_samples} | ${result.checksum_mismatches} | ${status} |')
		verified = verified && result.verified
	}
	print_headless_startup_phases()
	if owned_root {
		os.rmdir_all(root) or {}
	}
	if !verified {
		return error('one or more returned-value checks failed')
	}
}

fn (mut runner BenchmarkRunner) add(operation BenchmarkOperation) {
	for _ in 0 .. runner.config.warmup {
		_ := execute_benchmark_operation(operation, 0)
	}
	mut samples := []i64{}
	mut expected := u64(0)
	mut expected_observation := ''
	mut expected_counters := BenchmarkCounters{}
	mut verified := true
	mut checksum_mismatches := 0
	for iteration in 0 .. runner.config.iterations {
		sample := execute_benchmark_operation(operation, iteration)
		observation := benchmark_sample_observation(sample)
		if iteration == 0 {
			expected = sample.checksum
			expected_observation = observation
			expected_counters = sample.counters
		} else {
			if sample.checksum != expected {
				checksum_mismatches++
			}
			if observation != expected_observation {
				verified = false
			}
		}
		samples << sample.elapsed_ns
	}
	stats := summarize_samples(samples)
	fixture := if operation.path == '' {
		'generated:${operation.width}x${operation.height}'
	} else {
		operation.path
	}
	runner.results << BenchmarkResult{
		name:                benchmark_operation_name(operation.kind)
		fixture:             fixture
		cache:               operation.cache
		warmup:              runner.config.warmup
		iterations:          runner.config.iterations
		median_ns:           stats.median_ns
		p95_ns:              stats.p95_ns
		checksum:            expected
		verified:            verified && checksum_mismatches == 0
		checksum_samples:    runner.config.iterations
		checksum_mismatches: checksum_mismatches
		counters:            expected_counters
		cache_budget:        operation.cache_budget_bytes
	}
}

fn benchmark_sample_observation(sample BenchmarkSample) string {
	counters := sample.counters
	return '${sample.checksum}:${counters.requested}:${counters.displayed}:${counters.skipped}:${counters.coalesced}:${counters.prefetch_requested}:${counters.prefetched}:${counters.prefetch_skipped}:${counters.prefetch_coalesced}:${counters.prefetch_cancelled}:${counters.prefetch_decodes}:${counters.decode_count}:${counters.max_pending}:${counters.max_total_pending}:${counters.cache_hits}:${counters.cache_misses}:${counters.cache_updates}:${counters.cache_evictions}:${counters.cache_invalidations}:${counters.cache_content_validations}:${counters.cache_bytes}:${counters.cache_peak_bytes}:${counters.cache_cpu_bytes}:${counters.cache_renderer_bytes}'
}

fn benchmark_frame_app(width int, height int, opacity ui2.ImageOpacity) &ViewerApp {
	mut app := &ViewerApp{
		core:               new_app()
		window_ready:       true
		requested_window_w: width
		requested_window_h: height
	}
	app.core.set_canvas_size(width, height)
	app.core.set_image_resource(benchmark_ready_resource_with_opacity('frame-fixture', width, height, opacity))
	return app
}

fn execute_frame_transform_benchmark(operation BenchmarkOperation) BenchmarkSample {
	mut app := benchmark_frame_app(operation.width, operation.height, operation.opacity)
	app.core.zoom_in()
	mut stopwatch := time.new_stopwatch()
	if operation.frame_action == .pan {
		app.core.pan(17.0, 13.0)
	} else {
		app.core.zoom_in()
	}
	screen := app.build_screen_at_size(operation.width, operation.height)
	elapsed := stopwatch.elapsed().nanoseconds()
	mut checksum := benchmark_checksum_text(0, '${screen.id}:${screen.children}:${app.core.viewport.x}:${app.core.viewport.y}:${app.core.viewport.scale}')
	checksum = benchmark_checksum_u64(checksum, u64(app.core.transparency_background_visible()))
	return BenchmarkSample{ elapsed_ns: elapsed, checksum: checksum }
}

fn execute_toggle_benchmark(operation BenchmarkOperation) BenchmarkSample {
	mut app := benchmark_frame_app(operation.width, operation.height, .has_alpha)
	_ = app.build_screen_at_size(operation.width, operation.height)
	mut stopwatch := time.new_stopwatch()
	app.core.toggle_checkerboard()
	screen := app.build_screen_at_size(operation.width, operation.height)
	elapsed := stopwatch.elapsed().nanoseconds()
	checksum := benchmark_checksum_text(0, '${screen.id}:${screen.children}:${app.core.show_checkerboard}')
	return BenchmarkSample{ elapsed_ns: elapsed, checksum: checksum }
}

fn benchmark_resource_checksum(resource ui2.ImageResource, _source string) u64 {
	mut checksum := u64(0)
	checksum = benchmark_checksum_u64(checksum, u64(resource.width()))
	checksum = benchmark_checksum_u64(checksum, u64(resource.height()))
	return benchmark_checksum_u64(checksum, u64(resource.decoded_pixels().len))
}

fn execute_pipeline_load(operation BenchmarkOperation) BenchmarkSample {
	mut stopwatch := time.new_stopwatch()
	mut pipeline := new_image_pipeline(decode_stbi_image)
	pipeline.request(operation.path, 'benchmark-pipeline')
	mut result := ImagePipelineResult{}
	select {
		result = <-pipeline.result_ch {
		}
		5 * time.second {
			panic('benchmark pipeline decode timeout')
		}
	}
	pipeline.result_ch <- result
	results := pipeline.poll()
	if results.len != 1 {
		panic('benchmark pipeline did not complete')
	}
	elapsed := stopwatch.elapsed().nanoseconds()
	return BenchmarkSample{
		elapsed_ns: elapsed
		checksum:   benchmark_resource_checksum(results[0].resource, operation.path)
		counters:   benchmark_pipeline_sample_counters(pipeline)
	}
}

fn execute_worker_load(operation BenchmarkOperation) BenchmarkSample {
	mut stopwatch := time.new_stopwatch()
	request := ImageRequest{ generation: 1, path: operation.path, reason: 'benchmark-worker' }
	token := new_cancellation_token()
	result_ch := chan ImagePipelineResult{cap: 1}
	spawn image_decode_worker(request, decode_stbi_image, token, result_ch)
	result := <-result_ch
	elapsed := stopwatch.elapsed().nanoseconds()
	return BenchmarkSample{
		elapsed_ns: elapsed
		checksum:   benchmark_resource_checksum(result.resource, operation.path)
		counters:   BenchmarkCounters{
			decode_count: result.decode_count
		}
	}
}

fn execute_startup_pipeline_screen(operation BenchmarkOperation) BenchmarkSample {
	mut stopwatch := time.new_stopwatch()
	mut pipeline := new_image_pipeline(decode_stbi_image)
	pipeline.request(operation.path, 'benchmark-startup')
	mut result := ImagePipelineResult{}
	select {
		result = <-pipeline.result_ch {
		}
		5 * time.second {
			panic('benchmark startup decode timeout')
		}
	}
	pipeline.result_ch <- result
	results := pipeline.poll()
	if results.len != 1 {
		panic('benchmark startup did not complete')
	}
	mut app := new_app()
	app.set_image_resource(results[0].resource)
	app.set_canvas_size(operation.width, operation.height)
	screen := benchmark_viewer_for_app(mut app, operation.width, operation.height).build_screen_at_size(operation.width, operation.height)
	elapsed := stopwatch.elapsed().nanoseconds()
	return BenchmarkSample{
		elapsed_ns: elapsed
		checksum:   benchmark_checksum_text(benchmark_checksum_text(0, '${screen.id}:${screen.children}'), operation.path)
		counters:   benchmark_pipeline_sample_counters(pipeline)
	}
}

fn execute_benchmark_operation(operation BenchmarkOperation, iteration int) BenchmarkSample {
	match operation.kind {
		.resident_sibling_switch, .resident_sibling_switch_4k {
			return execute_resident_sibling_switch(operation)
		}
		.key_repeat_resident_right, .key_repeat_resident_left,
		.sustained_key_repeat_right, .sustained_key_repeat_left {
			return execute_resident_key_repeat(operation)
		}
		.pan_4k_transparent, .pan_4k_opaque, .zoom_4k_transparent, .zoom_4k_opaque {
			return execute_frame_transform_benchmark(operation)
		}
		.toggle_checkerboard_4k {
			return execute_toggle_benchmark(operation)
		}
		.key_repeat_faster_than_decode {
			return execute_fast_key_repeat(operation)
		}
		.image_pipeline_load_alpha, .image_pipeline_load_opaque, .image_pipeline_load_4k {
			return execute_pipeline_load(operation)
		}
		.image_worker_load_alpha, .image_worker_load_opaque, .image_worker_load_4k {
			return execute_worker_load(operation)
		}
		.sibling_discovery {
			ch := chan SiblingBatch{cap: 8}
			mut stopwatch := time.new_stopwatch()
			spawn scan_directory_siblings(os.dir(operation.path), operation.path, ch)
			mut count := 0
			mut complete := false
			for !complete {
				batch := <-ch
				count += batch.items.len
				complete = batch.is_last
			}
			elapsed := stopwatch.elapsed().nanoseconds()
			return BenchmarkSample{ elapsed_ns: elapsed, checksum: benchmark_checksum_u64(0, u64(count)) }
		}
		.sibling_navigation {
			mut app := benchmark_navigation_app(os.dir(operation.path))
			mut stopwatch := time.new_stopwatch()
			if iteration % 2 == 0 {
				app.core.next_sibling()
			} else {
				app.core.prev_sibling()
			}
			request := app.core.request_image(app.core.target_path, 'benchmark-navigation')
			app.image_pipeline.request_with_generation(app.core.target_path, 'benchmark-navigation', request.generation)
			mut result := ImagePipelineResult{}
			select {
				result = <-app.image_pipeline.result_ch {
				}
				5 * time.second {
					panic('benchmark navigation decode timeout')
				}
			}
			app.image_pipeline.result_ch <- result
			results := app.image_pipeline.poll()
			if results.len != 1 {
				panic('benchmark navigation did not complete')
			}
			elapsed := stopwatch.elapsed().nanoseconds()
			return BenchmarkSample{
				elapsed_ns: elapsed
				checksum:   benchmark_resource_checksum(results[0].resource, results[0].request.path)
				counters:   benchmark_pipeline_sample_counters(app.image_pipeline)
			}
		}
		.pattern_tile {
			mut stopwatch := time.new_stopwatch()
			pattern := checkerboard_pattern()
			elapsed := stopwatch.elapsed().nanoseconds()
			return BenchmarkSample{
				elapsed_ns: elapsed
				checksum:   benchmark_checksum(pattern.pixels)
			}
		}
		.sibling_cache_cold, .sibling_cache_warm, .sibling_cache_4k_cold, .sibling_cache_4k_warm,
		.sibling_cache_invalidation {
			mut cache := new_sibling_resource_cache(operation.cache_budget_bytes)
			mut checksum := u64(0)
			mut decode_count := 0
			mut elapsed := i64(0)
			if operation.kind == .sibling_cache_invalidation {
				decoded := decode_stbi_image(operation.path) or { panic(err) }
				decode_count = 1
				resource := image_resource_from_decoded('benchmark-invalidation', operation.path, decoded)
				signature := sibling_file_signature(operation.path)
				assert cache.put(operation.path, signature, resource, decoded.pixels.len, decoded.renderer_bytes)
				changed := SiblingFileSignature{
					exists:        signature.exists
					size:          signature.size
					modified_unix: signature.modified_unix + 1
				}
				mut stopwatch := time.new_stopwatch()
				invalidated := cache.get(operation.path, changed) != none
				elapsed = stopwatch.elapsed().nanoseconds()
				checksum = benchmark_checksum_u64(benchmark_checksum_u64(0, u64(decoded.width)), u64(invalidated))
			} else if operation.kind == .sibling_cache_warm || operation.kind == .sibling_cache_4k_warm {
				decoded := decode_stbi_image(operation.path) or { panic(err) }
				decode_count = 1
				resource := image_resource_from_decoded('benchmark-cache', operation.path, decoded)
				signature := sibling_file_signature(operation.path)
				cache.put(operation.path, signature, resource, decoded.pixels.len, decoded.renderer_bytes)
				mut stopwatch := time.new_stopwatch()
				elapsed = stopwatch.elapsed().nanoseconds()
				mut hit := false
				if cached := cache.get(operation.path, signature) {
					hit = true
					checksum = benchmark_checksum_u64(checksum, u64(cached.width()))
					checksum = benchmark_checksum_u64(checksum, u64(cached.height()))
				}
				checksum = benchmark_checksum_u64(checksum, u64(hit))
			} else {
				mut stopwatch := time.new_stopwatch()
				signature := sibling_file_signature(operation.path)
				decoded := decode_stbi_image(operation.path) or { panic(err) }
				decode_count = 1
				resource := image_resource_from_decoded('benchmark-cache', operation.path, decoded)
				accepted := cache.put(operation.path, signature, resource, decoded.pixels.len, decoded.renderer_bytes)
				elapsed = stopwatch.elapsed().nanoseconds()
				checksum = benchmark_checksum_u64(checksum, u64(decoded.width))
				checksum = benchmark_checksum_u64(checksum, u64(decoded.height))
				checksum = benchmark_checksum_u64(checksum, u64(accepted))
			}
			return BenchmarkSample{
				elapsed_ns: elapsed
				checksum:   checksum
				counters:   BenchmarkCounters{
					decode_count:              decode_count
					cache_hits:                cache.metrics.hits
					cache_misses:              cache.metrics.misses
					cache_updates:             cache.metrics.updates
					cache_evictions:           cache.metrics.evictions
					cache_invalidations:       cache.metrics.invalidations
					cache_content_validations: cache.metrics.content_validations
					cache_bytes:               cache.metrics.resident_bytes
					cache_peak_bytes:          cache.metrics.peak_bytes
					cache_cpu_bytes:           cache.metrics.cpu_bytes
					cache_renderer_bytes:      cache.metrics.renderer_bytes
					cache_budget:              operation.cache_budget_bytes
				}
			}
		}
		.screen_construct_4k, .screen_resize_to_4k, .frame_prepare_4k,
		.startup_cpu_cold, .startup_cpu_warm {
			if operation.kind == .startup_cpu_cold || operation.kind == .startup_cpu_warm {
				return execute_startup_pipeline_screen(operation)
			}
			mut app := benchmark_screen_app(operation.path, operation.width, operation.height)
			if operation.kind == .screen_resize_to_4k {
				_ = app.build_screen_at_size(1920, 1080)
			} else if operation.kind != .screen_construct_4k {
				_ = app.build_screen_at_size(operation.width, operation.height)
			}
			mut stopwatch := time.new_stopwatch()
			if operation.kind == .screen_resize_to_4k {
				first := app.build_screen_at_size(operation.width, operation.height)
				second := app.build_screen_at_size(operation.width, operation.height)
				third := app.build_screen_at_size(operation.width, operation.height)
				elapsed := stopwatch.elapsed().nanoseconds()
				return BenchmarkSample{
					elapsed_ns: elapsed
					checksum:   benchmark_checksum_text(0, '${first.id}:${first.children}:${second.id}:${second.children}:${third.id}:${third.children}')
				}
			}
			if operation.kind == .frame_prepare_4k {
				app.core.zoom_in()
				app.core.pan(1.0, 1.0)
			}
			screen := app.build_screen_at_size(operation.width, operation.height)
			elapsed := stopwatch.elapsed().nanoseconds()
			mut checksum := benchmark_checksum_text(0, '${screen.id}:${screen.children}')
			if operation.kind == .frame_prepare_4k {
				checksum = benchmark_checksum_u64(checksum, u64(app.core.viewport.x * 1000.0))
				checksum = benchmark_checksum_u64(checksum, u64(app.core.viewport.y * 1000.0))
			}
			return BenchmarkSample{ elapsed_ns: elapsed, checksum: checksum }
		}
		else {
			panic('unknown benchmark operation: ${operation.kind}')
		}
	}
}

fn benchmark_ready_resource(path string, width int, height int) ui2.ImageResource {
	return benchmark_ready_resource_with_opacity(path, width, height, .proven_opaque)
}

fn benchmark_ready_resource_with_opacity(path string, width int, height int, opacity ui2.ImageOpacity) ui2.ImageResource {
	pixel_bytes := width * height * 4
	return ui2.ready_image_resource('benchmark-${path}', path, ui2.ImageResourceInput{
		width:    width
		height:   height
		channels: 4
		pixels:   []u8{len: pixel_bytes, init: 255}
	}, opacity)
}

fn benchmark_pipeline_sample_counters(pipeline ImagePipeline) BenchmarkCounters {
	prefetch := pipeline.prefetch_metrics()
	cache_metrics := pipeline.cache.metrics
	return BenchmarkCounters{
		requested:                 pipeline.metrics.requested
		displayed:                 pipeline.metrics.displayed
		skipped:                   pipeline.metrics.skipped
		coalesced:                 pipeline.metrics.coalesced
		prefetch_requested:        prefetch.requested
		prefetched:                prefetch.prefetched
		prefetch_skipped:          prefetch.skipped
		prefetch_coalesced:        prefetch.coalesced
		prefetch_cancelled:        prefetch.cancelled
		prefetch_decodes:          prefetch.decode_count
		decode_count:              pipeline.metrics.decode_count
		max_pending:               pipeline.metrics.max_pending
		max_total_pending:         pipeline.metrics.max_total_pending
		cache_hits:                cache_metrics.hits
		cache_misses:              cache_metrics.misses
		cache_updates:             cache_metrics.updates
		cache_evictions:           cache_metrics.evictions
		cache_invalidations:       cache_metrics.invalidations
		cache_content_validations: cache_metrics.content_validations
		cache_bytes:               cache_metrics.resident_bytes
		cache_peak_bytes:          cache_metrics.peak_bytes
		cache_cpu_bytes:           cache_metrics.cpu_bytes
		cache_renderer_bytes:      cache_metrics.renderer_bytes
		cache_budget:              pipeline.cache.budget_bytes
	}
}

fn benchmark_pipeline_sample(elapsed_ns i64, checksum u64, app &ViewerApp) BenchmarkSample {
	return BenchmarkSample{
		elapsed_ns: elapsed_ns
		checksum:   checksum
		counters:   benchmark_pipeline_sample_counters(app.image_pipeline)
	}
}

fn benchmark_resident_switch_app(operation BenchmarkOperation) &ViewerApp {
	current_decoded := decode_stbi_image(operation.path) or { panic(err) }
	target_decoded := decode_stbi_image(operation.secondary_path) or { panic(err) }
	current := image_resource_from_decoded('benchmark-current', operation.path, current_decoded)
	target := image_resource_from_decoded('benchmark-target', operation.secondary_path, target_decoded)
	mut app := &ViewerApp{
		core:               new_app()
		image_pipeline:     new_manual_image_pipeline()
		requested_window_w: operation.width
		requested_window_h: operation.height
	}
	app.core.playlist = [operation.path, operation.secondary_path]
	app.core.active_index = 0
	app.core.set_canvas_size(operation.width, operation.height)
	app.core.set_image_resource(current)
	app.image_pipeline.set_cache_budget(operation.cache_budget_bytes)
	app.image_pipeline.set_resident(current)
	target_signature := sibling_file_content_signature(operation.secondary_path)
	assert app.image_pipeline.cache.put(operation.secondary_path, target_signature, target,
		target_decoded.pixels.len, target_decoded.renderer_bytes)
	app.sync_sibling_cache_retention()
	app.image_pipeline.last_current_revalidation_ns = time.sys_mono_now()
	return app
}

fn execute_resident_sibling_switch(operation BenchmarkOperation) BenchmarkSample {
	mut app := benchmark_resident_switch_app(operation)
	mut stopwatch := time.new_stopwatch()
	app.handle_key_event(ui2.KeyEvent{ code: .right })
	screen := app.build_screen_at_size(operation.width, operation.height)
	elapsed := stopwatch.elapsed().nanoseconds()
	assert app.core.displayed_image_resource().source == operation.secondary_path
	mut checksum := benchmark_checksum_text(0, operation.secondary_path)
	checksum = benchmark_checksum_text(checksum, '${screen.id}:${screen.children}')
	return benchmark_pipeline_sample(elapsed, checksum, app)
}

fn benchmark_resident_repeat_app(operation BenchmarkOperation, right bool) &ViewerApp {
	paths := benchmark_sibling_paths(os.dir(operation.path))
	start_index := if right { 0 } else { benchmark_key_repeat_steps }
	mut app := &ViewerApp{
		core:               new_app()
		image_pipeline:     new_manual_image_pipeline()
		requested_window_w: operation.width
		requested_window_h: operation.height
	}
	app.core.playlist = paths
	app.core.active_index = start_index
	app.core.set_canvas_size(operation.width, operation.height)
	current := benchmark_ready_resource(operation.path, 96, 64)
	app.core.set_image_resource(current)
	app.image_pipeline.set_cache_budget(operation.cache_budget_bytes)
	for index in 0 .. benchmark_key_repeat_steps + 1 {
		path := paths[index]
		signature := sibling_file_content_signature(path)
		resource := benchmark_ready_resource(path, 96, 64)
		assert app.image_pipeline.cache.put(path, signature, resource, 96 * 64 * 4, 96 * 64 * 4)
	}
	app.image_pipeline.set_resident(current)
	app.sync_sibling_cache_retention()
	app.image_pipeline.last_current_revalidation_ns = time.sys_mono_now()
	return app
}

fn execute_resident_key_repeat(operation BenchmarkOperation) BenchmarkSample {
	right := operation.direction == .right
	mut app := benchmark_resident_repeat_app(operation, right)
	mut checksum := u64(0)
	mut stopwatch := time.new_stopwatch()
	if right {
		for _ in 0 .. benchmark_key_repeat_steps {
			app.handle_key_event(ui2.KeyEvent{ code: .right })
			screen := app.build_screen_at_size(operation.width, operation.height)
			checksum = benchmark_checksum_text(checksum, app.core.displayed_image_resource().source)
			checksum = benchmark_checksum_text(checksum, '${screen.id}:${screen.children}')
		}
	} else {
		for _ in 0 .. benchmark_key_repeat_steps {
			app.handle_key_event(ui2.KeyEvent{ code: .left })
			screen := app.build_screen_at_size(operation.width, operation.height)
			checksum = benchmark_checksum_text(checksum, app.core.displayed_image_resource().source)
			checksum = benchmark_checksum_text(checksum, '${screen.id}:${screen.children}')
		}
	}
	elapsed := stopwatch.elapsed().nanoseconds()
	assert app.image_pipeline.metrics.requested == benchmark_key_repeat_steps
	assert app.image_pipeline.metrics.displayed == benchmark_key_repeat_steps
	assert app.image_pipeline.metrics.skipped == 0
	assert app.image_pipeline.metrics.coalesced == 0
	return benchmark_pipeline_sample(elapsed, checksum, app)
}

fn execute_fast_key_repeat(operation BenchmarkOperation) BenchmarkSample {
	paths := benchmark_sibling_paths(os.dir(operation.path))
	mut app := &ViewerApp{
		core:               new_app()
		image_pipeline:     new_manual_image_pipeline()
		requested_window_w: operation.width
		requested_window_h: operation.height
	}
	app.core.playlist = paths
	app.core.active_index = 0
	app.core.set_canvas_size(operation.width, operation.height)
	current := benchmark_ready_resource(operation.path, 96, 64)
	app.core.set_image_resource(current)
	app.image_pipeline.set_cache_budget(operation.cache_budget_bytes)
	app.image_pipeline.set_resident(current)
	mut stopwatch := time.new_stopwatch()
	for _ in 0 .. benchmark_fast_input_count {
		app.handle_key_event(ui2.KeyEvent{ code: .right })
	}
	elapsed := stopwatch.elapsed().nanoseconds()
	first := app.image_pipeline.active_request
	assert app.image_pipeline.complete_active(benchmark_ready_resource(first.path, 96, 64))
	app.poll_image_pipeline()
	latest := app.image_pipeline.active_request
	assert latest.path == operation.secondary_path
	assert app.image_pipeline.complete_active(benchmark_ready_resource(latest.path, 96, 64))
	app.poll_image_pipeline()
	assert app.core.displayed_image_resource().source == operation.secondary_path
	assert app.image_pipeline.metrics.requested == benchmark_fast_input_count
	assert app.image_pipeline.metrics.displayed == 1
	assert app.image_pipeline.metrics.skipped == benchmark_fast_input_count - 1
	assert app.image_pipeline.metrics.coalesced == benchmark_fast_input_count - 2
	assert app.image_pipeline.metrics.max_pending == 2
	assert app.image_pipeline.metrics.max_total_pending <= 5
	checksum := benchmark_checksum_text(0, operation.secondary_path)
	return benchmark_pipeline_sample(elapsed, checksum, app)
}

fn benchmark_navigation_app(directory string) &ViewerApp {
	mut app := &ViewerApp{
		core:           new_app()
		image_pipeline: new_image_pipeline(decode_stbi_image)
	}
	app.core.playlist = benchmark_sibling_paths(directory)
	app.core.active_index = 64
	app.core.set_image_loaded(app.core.active_sibling_path(), 96, 64)
	app.core.set_canvas_size(1024, 768)
	return app
}

fn benchmark_sibling_paths(directory string) []string {
	mut paths := []string{}
	for entry in os.ls(directory) or { []string{} } {
		path := os.join_path(directory, entry)
		if is_image_file(path) {
			paths << path
		}
	}
	natural_sort(mut paths)
	return paths
}

fn benchmark_screen_app(path string, width int, height int) &ViewerApp {
	mut app := &ViewerApp{
		core:               new_app()
		window_ready:       true
		requested_window_w: width
		requested_window_h: height
	}
	image_width := if width == benchmark_large_width { benchmark_large_width } else { 96 }
	image_height := if height == benchmark_large_height { benchmark_large_height } else { 64 }
	app.core.set_image_loaded(path, image_width, image_height)
	return app
}

fn benchmark_viewer_for_app(mut app App, width int, height int) &ViewerApp {
	return &ViewerApp{
		core:               app
		window_ready:       true
		requested_window_w: width
		requested_window_h: height
	}
}

fn live_variant_actions_present(summary LiveTraceSummary, variant string) bool {
	return match variant {
		'transparent' {
			summary.pan_transparent_to_frame_ns >= 0 && summary.zoom_transparent_to_frame_ns >= 0
		}
		'opaque' {
			summary.pan_opaque_to_frame_ns >= 0 && summary.zoom_opaque_to_frame_ns >= 0
		}
		else {
			false
		}
	}
}

fn run_wayland_smoke(target string) ! {
	if os.getenv('WAYLAND_DISPLAY') == '' {
		return error('WAYLAND_DISPLAY is unset')
	}
	trace_path := os.getenv('IMAGE_UI_BENCHMARK_TRACE')
	if trace_path == '' {
		return error('IMAGE_UI_BENCHMARK_TRACE is required')
	}
	warmup_frames := os.getenv('IMAGE_UI_BENCHMARK_WARMUP_FRAMES').int()
	frame_target := os.getenv('IMAGE_UI_BENCHMARK_FRAME_TARGET').int()
	launch_viewer(target)
	summary := summarize_live_trace(trace_path, warmup_frames, frame_target) or { return err }
	if !summary.complete {
		return error('live trace did not complete')
	}
	for phase in startup_phase_names() {
		if (summary.phase_ns[phase] or { -1 }) < 0 {
			return error('live trace lacks startup phase: ${phase}')
		}
	}
	if !summary.phase_monotonic {
		return error('live trace startup phases are not monotonic')
	}
	if summary.process_to_first_content_ns < 0 || summary.process_to_first_input_ns < 0 {
		return error('live trace lacks process-to-content or process-to-input marks')
	}
	if summary.toggle_to_frame_ns < 0 || summary.switch_to_frame_ns < 0 {
		return error('live trace lacks toggle or switch action marks')
	}
	mut expected_variant := os.getenv('IMAGE_UI_BENCHMARK_EXPECTED_OPACITY')
	if expected_variant != 'transparent' && expected_variant != 'opaque' {
		expected_variant = if target.ends_with('.tga') { 'transparent' } else { 'opaque' }
	}
	if !live_variant_actions_present(summary, expected_variant) {
		return error('live trace lacks ${expected_variant} pan or zoom action marks')
	}
	if summary.prefetch_cached_events == 0 || summary.counters.requested < 1 || summary.counters.displayed < 1 {
		return error('live trace lacks resident Sibling prefetch or request counters')
	}
	if summary.resize_to_frame_ns < 0 || summary.frame_samples == 0 {
		return error('live trace lacks resize or frame cadence samples')
	}
	mut repeat_target := os.getenv('IMAGE_UI_BENCHMARK_REPEAT_KEYS').int()
	if repeat_target <= 0 {
		repeat_target = 8
	}
	if summary.left_input_count < repeat_target || summary.right_input_count < repeat_target {
		return error('live trace lacks sustained Left/Right input counters')
	}
	build := benchmark_build_info()
	hardware := benchmark_hardware_info()
	print_benchmark('Viewer live Wayland smoke')
	println('build_commit=${build.commit} build_state=${build.dirty} module=${build.module}')
	println('v=${build.v_version}')
	println('compile_flags=${build.compile_flag}')
	println('hardware=${hardware.os_name} ${hardware.architecture} cpu=${hardware.cpu_model} logical_cpus=${hardware.logical_cpus} memory=${hardware.memory} gpu_driver=${hardware.gpu_driver}')
	println('cache=${os.getenv('IMAGE_UI_BENCHMARK_CACHE')} target=${target}')
	println('config=warmup_frames:${warmup_frames} frame_target:${frame_target} measured_frames:${summary.frame_samples} repeat_keys_each_direction:${repeat_target}')
	println('measured_viewport=${summary.viewport_width}x${summary.viewport_height}')
	println('viewport_exact_3840x2160=${summary.viewport_width == benchmark_large_width && summary.viewport_height == benchmark_large_height}')
	println('post_present_fence=unavailable')
	println('target_4k60=not_proven_without_exact_viewport_and_post_present_fence')
	println('startup_phase_order=${summary.phase_order.join('>')}')
	for phase in startup_phase_names() {
		println('startup_phase=${phase} elapsed_ms=${benchmark_ms(summary.phase_ns[phase] or { 0 })}')
	}
	println('process_to_first_content_ms=${benchmark_ms(summary.process_to_first_content_ns)}')
	println('process_to_first_input_ms=${benchmark_ms(summary.process_to_first_input_ns)}')
	println('toggle_to_frame_ms=${benchmark_ms(summary.toggle_to_frame_ns)}')
	println('switch_to_frame_ms=${benchmark_ms(summary.switch_to_frame_ns)}')
	println('sibling_requested=${summary.counters.requested} sibling_displayed=${summary.counters.displayed} sibling_skipped=${summary.counters.skipped} sibling_coalesced=${summary.counters.coalesced}')
	println('decode_count=${summary.counters.decode_count} prefetch_decode_count=${summary.counters.prefetch_decodes}')
	println('cache_hits=${summary.counters.cache_hits} cache_misses=${summary.counters.cache_misses} cache_updates=${summary.counters.cache_updates} cache_evictions=${summary.counters.cache_evictions} cache_invalidations=${summary.counters.cache_invalidations} cache_content_validations=${summary.counters.cache_content_validations}')
	println('cache_resident_bytes=${summary.counters.cache_bytes} cache_peak_bytes=${summary.counters.cache_peak_bytes} cache_cpu_bytes=${summary.counters.cache_cpu_bytes} cache_renderer_bytes=${summary.counters.cache_renderer_bytes} cache_budget=${summary.counters.cache_budget}')
	println('prefetch_requested=${summary.counters.prefetch_requested} prefetched=${summary.counters.prefetched} prefetch_skipped=${summary.counters.prefetch_skipped} prefetch_coalesced=${summary.counters.prefetch_coalesced} prefetch_cancelled=${summary.counters.prefetch_cancelled} prefetch_cached_events=${summary.prefetch_cached_events}')
	println('repeat_left_input=${summary.left_input_count} repeat_right_input=${summary.right_input_count}')
	println('pan_transparent_to_frame_ms=${benchmark_ms(summary.pan_transparent_to_frame_ns)}')
	println('pan_opaque_to_frame_ms=${benchmark_ms(summary.pan_opaque_to_frame_ns)}')
	println('zoom_transparent_to_frame_ms=${benchmark_ms(summary.zoom_transparent_to_frame_ns)}')
	println('zoom_opaque_to_frame_ms=${benchmark_ms(summary.zoom_opaque_to_frame_ns)}')
	println('resize_to_frame_ms=${benchmark_ms(summary.resize_to_frame_ns)}')
	println('frame_callback_median_ms=${benchmark_ms(summary.frame_median_ns)}')
	println('frame_callback_p95_ms=${benchmark_ms(summary.frame_p95_ns)}')
	println('checksum=${summary.checksum.hex()} status=ok')
	println('measurement_note=frame values are Viewer build-callback cadence; no post-present GPU fence is exposed')
}

fn print_headless_startup_phases() {
	mut trace := new_startup_phase_trace(time.sys_mono_now())
	trace.mark_now(.process_launch)
	mut app := new_app()
	app.set_canvas_size(1024, 768)
	trace.mark_now(.window_creation)
	_, _ := ui2.startup_font_paths()
	trace.mark_now(.font_work)
	app.set_image_loaded('phase-fixture.bmp', 96, 64)
	_ = benchmark_viewer_for_app(mut app, 1024, 768).build_screen_at_size(1024, 768)
	trace.mark_now(.ui2_setup)
	trace.mark_now(.gpu_context_initialization)
	trace.mark_now(.first_content)
	trace.mark_now(.first_input)
	trace.mark_now(.directory_completion)
	assert trace.is_monotonic()
	assert trace.has_all_startup_phases()
	print_benchmark('Viewer headless startup phases')
	println('measurement=phase-order smoke; elapsed values are monotonic CPU trace values, not process-launch claims')
	println('phase_order=${trace.ordered_phase_names().join('>')}')
	println('| phase | elapsed ms | monotonic ns | order |')
	println('| --- | ---: | ---: | ---: |')
	for mark in trace.marks {
		println('| ${ui2.startup_phase_name(mark.phase)} | ${benchmark_ms(mark.elapsed_ns)} | ${mark.monotonic_ns} | ${mark.order} |')
	}
}

fn benchmark_cache_name(cache BenchmarkCacheSelection) string {
	return match cache {
		.cold { 'cold' }
		.warm { 'warm' }
		.both { 'both' }
	}
}

fn benchmark_ms(value i64) string {
	return '${f64(value) / 1_000_000.0:0.3}'
}

fn print_benchmark(title string) {
	println('# ${title}')
}

fn print_benchmark_help() {
	print_benchmark('Viewer benchmark')
	println('usage: make benchmark [BENCHMARK_ARGS="--warmup 2 --iterations 10 --cache both"]')
	println('usage: make benchmark BENCHMARK_ARGS="--cache-budget 67108864"')
	println('usage: ./image-ui-benchmark --prepare-fixtures <directory>')
	println('usage: make benchmark-wayland')
	println('headless measures image metadata decode, screen construction, resize, navigation, pattern-tile creation, and frame preparation without opening a display')
	println('live uses the niri Wayland smoke harness and records the measured viewport without claiming 4K evidence')
}

fn fatal_benchmark_usage(message string) {
	eprintln('benchmark usage error: ${message}')
	print_benchmark_help()
	exit(2)
}
