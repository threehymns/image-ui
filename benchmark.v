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

pub struct BenchmarkSample {
pub:
	elapsed_ns         i64
	checksum           u64
	requested          int
	displayed          int
	skipped            int
	coalesced          int
	prefetch_requested int
	prefetched         int
	prefetch_skipped   int
	prefetch_coalesced int
	max_pending        int
	max_total_pending  int
	cache_hits         int
	cache_misses       int
	cache_updates      int
	cache_evictions    int
	cache_bytes        int
	cache_budget       int
}

pub struct BenchmarkResult {
pub:
	name               string
	fixture            string
	cache              string
	warmup             int
	iterations         int
	median_ns          i64
	p95_ns             i64
	checksum           u64
	verified           bool
	requested          int
	displayed          int
	skipped            int
	coalesced          int
	prefetch_requested int
	prefetched         int
	prefetch_skipped   int
	prefetch_coalesced int
	max_pending        int
	max_total_pending  int
	cache_hits         int
	cache_misses       int
	cache_updates      int
	cache_evictions    int
	cache_bytes        int
	cache_budget       int
}

struct BenchmarkOperation {
pub mut:
	kind               string
	path               string
	secondary_path     string
	width              int
	height             int
	cache              string
	cache_budget_bytes int
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
		kind:  'image_load_alpha'
		path:  fixtures.alpha
		cache: 'no-app-cache'
	})
	runner.add(BenchmarkOperation{
		kind:  'image_load_opaque'
		path:  fixtures.opaque
		cache: 'no-app-cache'
	})
	runner.add(BenchmarkOperation{
		kind:  'image_load_4k'
		path:  fixtures.large_4k
		cache: 'no-app-cache'
	})
	for budget_bytes in benchmark_cache_budgets(config) {
		if config.cache == .cold || config.cache == .both {
			runner.add(BenchmarkOperation{
				kind:               'sibling_cache_cold'
				path:               fixtures.opaque
				cache:              'sibling-lru'
				cache_budget_bytes: budget_bytes
			})
		}
		if config.cache == .warm || config.cache == .both {
			runner.add(BenchmarkOperation{
				kind:               'sibling_cache_warm'
				path:               fixtures.opaque
				cache:              'sibling-lru'
				cache_budget_bytes: budget_bytes
			})
		}
	}
	if config.cache == .cold || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:               'sibling_cache_4k_cold'
			path:               fixtures.large_4k
			cache:              'sibling-lru'
			cache_budget_bytes: 256 * 1024 * 1024
		})
	}
	if config.cache == .warm || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:               'sibling_cache_4k_warm'
			path:               fixtures.large_4k
			cache:              'sibling-lru'
			cache_budget_bytes: 256 * 1024 * 1024
		})
	}
	runner.add(BenchmarkOperation{
		kind:  'sibling_discovery'
		path:  fixtures.sibling(0)
		cache: 'filesystem'
	})
	runner.add(BenchmarkOperation{
		kind:  'sibling_navigation'
		path:  fixtures.sibling(64)
		cache: 'no-app-cache'
	})
	runner.add(BenchmarkOperation{
		kind:               'resident_sibling_switch'
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(1)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               'resident_sibling_switch_4k'
		path:               fixtures.large_4k
		secondary_path:     fixtures.large_sibling_next
		width:              benchmark_large_width
		height:             benchmark_large_height
		cache:              'sibling-lru-resident'
		cache_budget_bytes: default_sibling_cache_budget_bytes
	})
	runner.add(BenchmarkOperation{
		kind:               'key_repeat_resident_right'
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(benchmark_key_repeat_steps)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               'key_repeat_resident_left'
		path:               fixtures.sibling(benchmark_key_repeat_steps)
		secondary_path:     fixtures.sibling(0)
		width:              1024
		height:             768
		cache:              'sibling-lru-resident'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:               'key_repeat_faster_than_decode'
		path:               fixtures.sibling(0)
		secondary_path:     fixtures.sibling(benchmark_fast_input_count)
		width:              1024
		height:             768
		cache:              'manual-pipeline'
		cache_budget_bytes: 4 * 1024 * 1024
	})
	runner.add(BenchmarkOperation{
		kind:  'pattern_tile'
		cache: 'constant'
	})
	runner.add(BenchmarkOperation{
		kind:   'frame_prepare_4k'
		path:   fixtures.large_4k
		width:  benchmark_large_width
		height: benchmark_large_height
		cache:  'pattern-resource'
	})

	if config.cache == .cold || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:   'screen_construct_4k'
			path:   fixtures.opaque
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'pattern-resource'
		})
		runner.add(BenchmarkOperation{
			kind:   'screen_resize_to_4k'
			path:   fixtures.opaque
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'pattern-resource'
		})
		runner.add(BenchmarkOperation{
			kind:   'startup_cpu'
			path:   fixtures.large_4k
			width:  1024
			height: 768
			cache:  'pattern-resource'
		})
	}
	if config.cache == .warm || config.cache == .both {
		runner.add(BenchmarkOperation{
			kind:   'screen_construct_4k'
			path:   fixtures.opaque
			width:  benchmark_large_width
			height: benchmark_large_height
			cache:  'pattern-resource'
		})
		runner.add(BenchmarkOperation{
			kind:   'startup_cpu'
			path:   fixtures.large_4k
			width:  1024
			height: 768
			cache:  'pattern-resource'
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
	println('fixtures=alpha:64x64 opaque:96x64 large_4k:${benchmark_large_width}x${benchmark_large_height} large_neighbors:2 siblings:${fixtures.sibling_count} generation_ms=${benchmark_ms(fixture_elapsed)}')
	println('cache_note=image rows have no application cache; sibling-lru rows use the full-resolution resource cache')
	println('sibling_counter_note=requested/displayed/skipped/coalesced count user Sibling requests; prefetch columns count Neighborhood candidates and accepted cache insertions')
	println('cache_separation=Filmstrip Thumbnail Cache remains a separate cache and is not included in sibling-lru budget accounting')
	println('pattern_note=the Viewer uses one 32x32 logical repeat tile; no full-window raster is generated')
	println('measurement=screen rows build UI2 elements only and do not include GPU submission')
	println('| case | fixture | cache | budget bytes | warmup | iterations | median ms | p95 ms | requested | displayed | skipped | coalesced | prefetch requested | prefetched | prefetch skipped | prefetch coalesced | max pending | max total pending | hits | misses | updates | evictions | resident bytes | checksum | status |')
	println('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |')
	mut verified := true
	for result in runner.results {
		status := if result.verified { 'ok' } else { 'checksum-mismatch' }
		println('| ${result.name} | ${os.file_name(result.fixture)} | ${result.cache} | ${result.cache_budget} | ${result.warmup} | ${result.iterations} | ${benchmark_ms(result.median_ns)} | ${benchmark_ms(result.p95_ns)} | ${result.requested} | ${result.displayed} | ${result.skipped} | ${result.coalesced} | ${result.prefetch_requested} | ${result.prefetched} | ${result.prefetch_skipped} | ${result.prefetch_coalesced} | ${result.max_pending} | ${result.max_total_pending} | ${result.cache_hits} | ${result.cache_misses} | ${result.cache_updates} | ${result.cache_evictions} | ${result.cache_bytes} | ${result.checksum.hex()} | ${status} |')
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
	mut verified := true
	mut sample_requested := 0
	mut sample_displayed := 0
	mut sample_skipped := 0
	mut sample_coalesced := 0
	mut sample_prefetch_requested := 0
	mut sample_prefetched := 0
	mut sample_prefetch_skipped := 0
	mut sample_prefetch_coalesced := 0
	mut sample_max_pending := 0
	mut sample_max_total_pending := 0
	mut sample_cache_hits := 0
	mut sample_cache_misses := 0
	mut sample_cache_updates := 0
	mut sample_cache_evictions := 0
	mut sample_cache_bytes := 0
	for iteration in 0 .. runner.config.iterations {
		sample := execute_benchmark_operation(operation, iteration)
		if iteration == 0 {
			expected = sample.checksum
			sample_requested = sample.requested
			sample_displayed = sample.displayed
			sample_skipped = sample.skipped
			sample_coalesced = sample.coalesced
			sample_prefetch_requested = sample.prefetch_requested
			sample_prefetched = sample.prefetched
			sample_prefetch_skipped = sample.prefetch_skipped
			sample_prefetch_coalesced = sample.prefetch_coalesced
			sample_max_pending = sample.max_pending
			sample_max_total_pending = sample.max_total_pending
			sample_cache_hits = sample.cache_hits
			sample_cache_misses = sample.cache_misses
			sample_cache_updates = sample.cache_updates
			sample_cache_evictions = sample.cache_evictions
			sample_cache_bytes = sample.cache_bytes
		} else if sample.checksum != expected {
			verified = false
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
		name:               operation.kind
		fixture:            fixture
		cache:              operation.cache
		warmup:             runner.config.warmup
		iterations:         runner.config.iterations
		median_ns:          stats.median_ns
		p95_ns:             stats.p95_ns
		checksum:           expected
		verified:           verified
		requested:          sample_requested
		displayed:          sample_displayed
		skipped:            sample_skipped
		coalesced:          sample_coalesced
		prefetch_requested: sample_prefetch_requested
		prefetched:         sample_prefetched
		prefetch_skipped:   sample_prefetch_skipped
		prefetch_coalesced: sample_prefetch_coalesced
		max_pending:        sample_max_pending
		max_total_pending:  sample_max_total_pending
		cache_hits:         sample_cache_hits
		cache_misses:       sample_cache_misses
		cache_updates:      sample_cache_updates
		cache_evictions:    sample_cache_evictions
		cache_bytes:        sample_cache_bytes
		cache_budget:       operation.cache_budget_bytes
	}
}

fn execute_benchmark_operation(operation BenchmarkOperation, iteration int) BenchmarkSample {
	match operation.kind {
		'resident_sibling_switch', 'resident_sibling_switch_4k' {
			return execute_resident_sibling_switch(operation)
		}
		'key_repeat_resident_right', 'key_repeat_resident_left' {
			return execute_resident_key_repeat(operation)
		}
		'key_repeat_faster_than_decode' {
			return execute_fast_key_repeat(operation)
		}
		'image_load_alpha', 'image_load_opaque', 'image_load_4k' {
			mut stopwatch := time.new_stopwatch()
			metadata := load_image_metadata(operation.path) or { panic(err) }
			elapsed := stopwatch.elapsed().nanoseconds()
			mut checksum := u64(0)
			checksum = benchmark_checksum_u64(checksum, u64(metadata.width))
			checksum = benchmark_checksum_u64(checksum, u64(metadata.height))
			checksum = benchmark_checksum_u64(checksum, u64(metadata.source_bytes))
			checksum = benchmark_checksum_u64(checksum, u64(metadata.original_channels))
			return BenchmarkSample{ elapsed_ns: elapsed, checksum: checksum }
		}
		'sibling_discovery' {
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
		'sibling_navigation' {
			mut app := benchmark_navigation_app(os.dir(operation.path))
			mut stopwatch := time.new_stopwatch()
			if iteration % 2 == 0 {
				app.core.next_sibling()
			} else {
				app.core.prev_sibling()
			}
			metadata := load_image_metadata(app.core.target_path) or { panic(err) }
			elapsed := stopwatch.elapsed().nanoseconds()
			app.core.set_image_loaded(app.core.target_path, metadata.width, metadata.height)
			return BenchmarkSample{
				elapsed_ns: elapsed
				checksum:   benchmark_checksum_u64(benchmark_checksum_u64(0, u64(metadata.width)), u64(metadata.height))
			}
		}
		'pattern_tile' {
			mut stopwatch := time.new_stopwatch()
			pattern := checkerboard_pattern()
			elapsed := stopwatch.elapsed().nanoseconds()
			return BenchmarkSample{
				elapsed_ns: elapsed
				checksum:   benchmark_checksum(pattern.pixels)
			}
		}
		'sibling_cache_cold', 'sibling_cache_warm', 'sibling_cache_4k_cold', 'sibling_cache_4k_warm' {
			mut cache := new_sibling_resource_cache(operation.cache_budget_bytes)
			mut checksum := u64(0)
			mut elapsed := i64(0)
			if operation.kind == 'sibling_cache_warm' || operation.kind == 'sibling_cache_4k_warm' {
				decoded := decode_stbi_image(operation.path) or { panic(err) }
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
				resource := image_resource_from_decoded('benchmark-cache', operation.path, decoded)
				accepted := cache.put(operation.path, signature, resource, decoded.pixels.len, decoded.renderer_bytes)
				elapsed = stopwatch.elapsed().nanoseconds()
				checksum = benchmark_checksum_u64(checksum, u64(decoded.width))
				checksum = benchmark_checksum_u64(checksum, u64(decoded.height))
				checksum = benchmark_checksum_u64(checksum, u64(accepted))
			}
			return BenchmarkSample{
				elapsed_ns:      elapsed
				checksum:        checksum
				cache_hits:      cache.metrics.hits
				cache_misses:    cache.metrics.misses
				cache_updates:   cache.metrics.updates
				cache_evictions: cache.metrics.evictions
				cache_bytes:     cache.metrics.resident_bytes
				cache_budget:    operation.cache_budget_bytes
			}
		}
		'screen_construct_4k', 'screen_resize_to_4k', 'frame_prepare_4k', 'startup_cpu' {
			if operation.kind == 'startup_cpu' {
				mut stopwatch := time.new_stopwatch()
				mut app := new_app()
				metadata := load_image_metadata(operation.path) or { panic(err) }
				app.set_image_loaded(operation.path, metadata.width, metadata.height)
				app.set_canvas_size(operation.width, operation.height)
				screen := benchmark_viewer_for_app(mut app, operation.width, operation.height).build_screen_at_size(operation.width, operation.height)
				elapsed := stopwatch.elapsed().nanoseconds()
				mut checksum := benchmark_checksum_text(0, '${screen.id}:${screen.children}')
				checksum = benchmark_checksum_u64(checksum, u64(metadata.width))
				checksum = benchmark_checksum_u64(checksum, u64(metadata.height))
				return BenchmarkSample{ elapsed_ns: elapsed, checksum: checksum }
			}
			mut app := benchmark_screen_app(operation.path, operation.width, operation.height)
			if operation.kind == 'screen_resize_to_4k' {
				_ = app.build_screen_at_size(1920, 1080)
			} else if operation.kind != 'screen_construct_4k' {
				_ = app.build_screen_at_size(operation.width, operation.height)
			}
			mut stopwatch := time.new_stopwatch()
			if operation.kind == 'screen_resize_to_4k' {
				first := app.build_screen_at_size(operation.width, operation.height)
				second := app.build_screen_at_size(operation.width, operation.height)
				third := app.build_screen_at_size(operation.width, operation.height)
				elapsed := stopwatch.elapsed().nanoseconds()
				return BenchmarkSample{
					elapsed_ns: elapsed
					checksum:   benchmark_checksum_text(0, '${first.id}:${first.children}:${second.id}:${second.children}:${third.id}:${third.children}')
				}
			}
			if operation.kind == 'frame_prepare_4k' {
				app.core.zoom_in()
				app.core.pan(1.0, 1.0)
			}
			screen := app.build_screen_at_size(operation.width, operation.height)
			elapsed := stopwatch.elapsed().nanoseconds()
			mut checksum := benchmark_checksum_text(0, '${screen.id}:${screen.children}')
			if operation.kind == 'frame_prepare_4k' {
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
	pixel_bytes := width * height * 4
	return ui2.ready_image_resource('benchmark-${path}', path, ui2.ImageResourceInput{
		width:    width
		height:   height
		channels: 4
		pixels:   []u8{len: pixel_bytes, init: 255}
	}, .proven_opaque)
}

fn benchmark_pipeline_sample(elapsed_ns i64, checksum u64, app &ViewerApp) BenchmarkSample {
	return BenchmarkSample{
		elapsed_ns:         elapsed_ns
		checksum:           checksum
		requested:          app.image_pipeline.metrics.requested
		displayed:          app.image_pipeline.metrics.displayed
		skipped:            app.image_pipeline.metrics.skipped
		coalesced:          app.image_pipeline.metrics.coalesced
		prefetch_requested: app.image_pipeline.prefetch_metrics.requested
		prefetched:         app.image_pipeline.prefetch_metrics.prefetched
		prefetch_skipped:   app.image_pipeline.prefetch_metrics.skipped
		prefetch_coalesced: app.image_pipeline.prefetch_metrics.coalesced
		max_pending:        app.image_pipeline.metrics.max_pending
		max_total_pending:  app.image_pipeline.metrics.max_total_pending
		cache_hits:         app.image_pipeline.cache.metrics.hits
		cache_misses:       app.image_pipeline.cache.metrics.misses
		cache_updates:      app.image_pipeline.cache.metrics.updates
		cache_evictions:    app.image_pipeline.cache.metrics.evictions
		cache_bytes:        app.image_pipeline.cache.metrics.resident_bytes
		cache_budget:       app.image_pipeline.cache.budget_bytes
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
	target_signature := sibling_file_signature(operation.secondary_path)
	assert app.image_pipeline.cache.put(operation.secondary_path, target_signature, target,
		target_decoded.pixels.len, target_decoded.renderer_bytes)
	app.sync_sibling_cache_retention()
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
		signature := sibling_file_signature(path)
		resource := benchmark_ready_resource(path, 96, 64)
		assert app.image_pipeline.cache.put(path, signature, resource, 96 * 64 * 4, 96 * 64 * 4)
	}
	app.image_pipeline.set_resident(current)
	app.sync_sibling_cache_retention()
	return app
}

fn execute_resident_key_repeat(operation BenchmarkOperation) BenchmarkSample {
	right := operation.kind == 'key_repeat_resident_right'
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
		core: new_app()
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
	for phase in startup_phase_names {
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
	if summary.toggle_to_frame_ns < 0 || summary.switch_to_frame_ns < 0
		|| summary.pan_to_frame_ns < 0 || summary.zoom_to_frame_ns < 0 {
		return error('live trace lacks one or more action-to-frame marks')
	}
	if summary.prefetch_cached == 0 || summary.requested < 1 || summary.displayed < 1 {
		return error('live trace lacks resident Sibling prefetch or request counters')
	}
	if summary.resize_to_frame_ns < 0 || summary.frame_samples == 0 {
		return error('live trace lacks resize or frame cadence samples')
	}
	build := benchmark_build_info()
	hardware := benchmark_hardware_info()
	print_benchmark('Viewer live Wayland smoke')
	println('build_commit=${build.commit} build_state=${build.dirty} module=${build.module}')
	println('v=${build.v_version}')
	println('compile_flags=${build.compile_flag}')
	println('hardware=${hardware.os_name} ${hardware.architecture} cpu=${hardware.cpu_model} logical_cpus=${hardware.logical_cpus} memory=${hardware.memory} gpu_driver=${hardware.gpu_driver}')
	println('cache=${os.getenv('IMAGE_UI_BENCHMARK_CACHE')} target=${target}')
	println('config=warmup_frames:${warmup_frames} frame_target:${frame_target} measured_frames:${summary.frame_samples}')
	println('measured_viewport=${summary.viewport_width}x${summary.viewport_height}')
	println('startup_phase_order=${summary.phase_order.join('>')}')
	for phase in startup_phase_names {
		println('startup_phase=${phase} elapsed_ms=${benchmark_ms(summary.phase_ns[phase] or { 0 })}')
	}
	println('process_to_first_content_ms=${benchmark_ms(summary.process_to_first_content_ns)}')
	println('process_to_first_input_ms=${benchmark_ms(summary.process_to_first_input_ns)}')
	println('toggle_to_frame_ms=${benchmark_ms(summary.toggle_to_frame_ns)}')
	println('switch_to_frame_ms=${benchmark_ms(summary.switch_to_frame_ns)}')
	println('sibling_requested=${summary.requested} sibling_displayed=${summary.displayed} sibling_skipped=${summary.skipped} sibling_coalesced=${summary.coalesced}')
	println('prefetch_requested=${summary.prefetch_requested} prefetched=${summary.prefetched} prefetch_skipped=${summary.prefetch_skipped} prefetch_coalesced=${summary.prefetch_coalesced} prefetch_cached_events=${summary.prefetch_cached}')
	println('pan_to_frame_ms=${benchmark_ms(summary.pan_to_frame_ns)}')
	println('zoom_to_frame_ms=${benchmark_ms(summary.zoom_to_frame_ns)}')
	println('resize_to_frame_ms=${benchmark_ms(summary.resize_to_frame_ns)}')
	println('frame_callback_median_ms=${benchmark_ms(summary.frame_median_ns)}')
	println('frame_callback_p95_ms=${benchmark_ms(summary.frame_p95_ns)}')
	println('checksum=${summary.checksum.hex()} status=ok')
	println('measurement_note=frame values are Viewer build-callback cadence; no post-present GPU fence is exposed')
}

fn print_headless_startup_phases() {
	mut trace := new_startup_phase_trace(time.sys_mono_now())
	trace.mark_now('process_launch')
	mut app := new_app()
	app.set_canvas_size(1024, 768)
	trace.mark_now('window_creation')
	_, _ := ui2.startup_font_paths()
	trace.mark_now('font_work')
	app.set_image_loaded('phase-fixture.bmp', 96, 64)
	_ = benchmark_viewer_for_app(mut app, 1024, 768).build_screen_at_size(1024, 768)
	trace.mark_now('ui2_setup')
	trace.mark_now('gpu_setup')
	trace.mark_now('first_content')
	trace.mark_now('first_input')
	trace.mark_now('directory_completion')
	assert trace.is_monotonic()
	assert trace.has_all_startup_phases()
	print_benchmark('Viewer headless startup phases')
	println('measurement=phase-order smoke; elapsed values are monotonic CPU trace values, not process-launch claims')
	println('phase_order=${trace.ordered_phases().join('>')}')
	println('| phase | elapsed ms | monotonic ns | order |')
	println('| --- | ---: | ---: | ---: |')
	for mark in trace.marks {
		println('| ${mark.phase} | ${benchmark_ms(mark.elapsed_ns)} | ${mark.monotonic_ns} | ${mark.order} |')
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
