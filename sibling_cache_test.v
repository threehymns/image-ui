module main

import os
import time
import ui2

fn sibling_cache_test_resource(path string) ui2.ImageResource {
	return ui2.ready_image_resource('resource-${path}', path, ui2.ImageResourceInput{
		width:    1
		height:   1
		channels: 4
		pixels:   []u8{len: 4, init: 255}
	}, .proven_opaque)
}

__global sibling_cache_test_decode_count = 0

fn sibling_cache_test_decoder(path string) !DecodedImage {
	sibling_cache_test_decode_count++
	return decode_stbi_image(path)!
}

fn sibling_cache_test_bmp() []u8 {
	mut data := []u8{len: 58}
	data[0] = `B`
	data[1] = `M`
	data[2] = 58
	data[10] = 54
	data[14] = 40
	data[18] = 1
	data[22] = 1
	data[26] = 1
	data[28] = 24
	data[34] = 4
	data[54] = 255
	data[55] = 0
	data[56] = 0
	return data
}

fn test_sibling_resource_cache_accounts_cpu_and_renderer_bytes_under_budget() {
	mut cache := new_sibling_resource_cache(24)
	first_signature := SiblingFileSignature{
		exists:        true
		size:          10
		modified_unix: 1
	}
	second_signature := SiblingFileSignature{
		exists:        true
		size:          20
		modified_unix: 2
	}

	assert cache.put('a.png', first_signature, sibling_cache_test_resource('a.png'), 10, 2)
	assert cache.put('b.png', second_signature, sibling_cache_test_resource('b.png'), 10, 2)
	assert cache.metrics.resident_bytes == 24
	assert cache.metrics.cpu_bytes == 20
	assert cache.metrics.renderer_bytes == 4
	assert cache.metrics.peak_bytes == 24

	assert cache.put('b.png', second_signature, sibling_cache_test_resource('b.png'), 11, 3)
	assert cache.metrics.updates == 1
	assert cache.metrics.evictions == 1
	assert !cache.contains('a.png')
	assert cache.metrics.resident_bytes == 14
	assert cache.metrics.cpu_bytes == 11
	assert cache.metrics.renderer_bytes == 3
}

fn test_sibling_resource_cache_hits_refresh_lru_recency_and_misses_report() {
	mut cache := new_sibling_resource_cache(25)
	first_signature := SiblingFileSignature{ exists: true, size: 1, modified_unix: 1 }
	second_signature := SiblingFileSignature{ exists: true, size: 2, modified_unix: 2 }
	third_signature := SiblingFileSignature{ exists: true, size: 3, modified_unix: 3 }
	missing_signature := SiblingFileSignature{ exists: true, size: 4, modified_unix: 4 }

	assert cache.put('a.png', first_signature, sibling_cache_test_resource('a.png'), 10, 0)
	assert cache.put('b.png', second_signature, sibling_cache_test_resource('b.png'), 10, 0)
	hit := cache.get('a.png', first_signature) or { panic('expected a.png hit') }
	assert hit.source == 'a.png'
	assert cache.put('c.png', third_signature, sibling_cache_test_resource('c.png'), 10, 0)
	assert !cache.contains('b.png')
	assert cache.contains('a.png')
	assert cache.contains('c.png')
	if cache.get('missing.png', missing_signature) != none {
		assert false
	}
	assert cache.metrics.hits == 1
	assert cache.metrics.misses == 1
	assert cache.metrics.evictions == 1
	assert cache.metrics.resident_entries == 2
	assert cache.metrics.resident_bytes == 20
}

fn test_sibling_resource_cache_invalidates_changed_file_signature() {
	path := os.join_path(os.temp_dir(), 'image-ui-sibling-signature-${time.ticks()}.png')
	os.write_file(path, 'first') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	mut cache := new_sibling_resource_cache(32)
	first_signature := sibling_file_signature(path)
	assert first_signature.exists
	assert cache.put(path, first_signature, sibling_cache_test_resource(path), 8, 0)
	os.write_file(path, 'other') or { panic(err) }
	os.utime(path, 10, 20) or { panic(err) }
	changed_signature := sibling_file_signature(path)
	assert changed_signature.size == first_signature.size
	assert changed_signature.modified_unix != first_signature.modified_unix
	if cache.get(path, changed_signature) != none {
		assert false
	}
	assert cache.metrics.hits == 0
	assert cache.metrics.misses == 1
	assert cache.metrics.invalidations == 1
	assert !cache.contains(path)
	assert cache.metrics.resident_bytes == 0
}

fn test_sibling_resource_cache_periodic_digest_catches_same_size_same_second_rewrite() {
	path := os.join_path(os.temp_dir(), 'image-ui-sibling-content-rewrite-${time.ticks()}.png')
	os.write_file(path, 'aaaa') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	initial := sibling_file_content_signature(path)
	mut cache := new_sibling_resource_cache(32)
	assert cache.put(path, initial, sibling_cache_test_resource(path), 8, 0)
	os.write_file(path, 'bbbb') or { panic(err) }
	os.utime(path, initial.modified_unix, initial.modified_unix) or { panic(err) }
	stat_only := sibling_file_signature(path)
	assert stat_only.size == initial.size
	assert stat_only.modified_unix == initial.modified_unix
	assert stat_only.changed_unix == initial.changed_unix
	assert cache.get(path, stat_only) != none
	assert !cache.revalidate(path, sibling_file_content_signature(path))
	assert cache.metrics.hits == 1
	assert cache.metrics.content_validations == 1
	assert cache.metrics.invalidations == 1
	assert !cache.contains(path)
}

fn test_sibling_resource_cache_hit_retains_resource_and_content_validation() {
	path := os.join_path(os.temp_dir(), 'image-ui-sibling-cache-hit-${time.ticks()}.png')
	os.write_file(path, 'same') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	mut cache := new_sibling_resource_cache(32)
	full := sibling_file_content_signature(path)
	resource := sibling_cache_test_resource(path)
	assert cache.put(path, full, resource, 8, 0)
	hit := cache.get(path, sibling_file_signature(path)) or { panic('expected cache hit') }
	assert hit == resource
	assert cache.revalidate(path, sibling_file_content_signature(path))
	assert cache.contains(path)
	assert cache.metrics.hits == 1
	assert cache.metrics.content_validations == 1
	assert cache.metrics.invalidations == 0
}

fn test_pipeline_revalidates_current_displayed_resource_without_request_cache_hit() {
	path := os.join_path(os.temp_dir(), 'image-ui-current-revalidation-${time.ticks()}.png')
	os.write_file(path, 'aaaa') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	mut pipeline := new_manual_image_pipeline()
	pipeline.set_resident(sibling_cache_test_resource(path))
	assert pipeline.cache.contains(path)
	initial := sibling_file_content_signature(path)
	os.write_file(path, 'bbbb') or { panic(err) }
	os.utime(path, initial.modified_unix, initial.modified_unix) or { panic(err) }
	pipeline.current_revalidation_interval_ns = 1
	pipeline.last_current_revalidation_ns = 0
	assert pipeline.poll().len == 0
	assert pipeline.current_resource_invalidated
	assert !pipeline.cache.contains(path)
	assert pipeline.resident_resource.state == .loading
	assert pipeline.take_current_resource_invalidated()
	assert !pipeline.take_current_resource_invalidated()
}

fn test_current_revalidation_keeps_oversized_resident_when_unchanged() {
	path := os.join_path(os.temp_dir(), 'image-ui-oversized-current-${time.ticks()}.png')
	os.write_file(path, 'aaaa') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	mut pipeline := new_manual_image_pipeline()
	pipeline.set_cache_budget(1)
	pipeline.set_resident(sibling_cache_test_resource(path))
	pipeline.current_revalidation_interval_ns = 1
	pipeline.last_current_revalidation_ns = 0
	assert pipeline.poll().len == 0
	assert pipeline.resident_resource.state == .ready
	assert !pipeline.current_resource_invalidated
}

fn test_sibling_resource_cache_keeps_current_and_nearby_entries_within_budget() {
	mut cache := new_sibling_resource_cache(30)
	first_signature := SiblingFileSignature{ exists: true, size: 1, modified_unix: 1 }
	second_signature := SiblingFileSignature{ exists: true, size: 2, modified_unix: 2 }
	third_signature := SiblingFileSignature{ exists: true, size: 3, modified_unix: 3 }
	fourth_signature := SiblingFileSignature{ exists: true, size: 4, modified_unix: 4 }
	assert cache.put('old.png', first_signature, sibling_cache_test_resource('old.png'), 10, 0)
	assert cache.put('nearby.png', second_signature, sibling_cache_test_resource('nearby.png'), 10, 0)
	assert cache.put('current.png', third_signature, sibling_cache_test_resource('current.png'), 10, 0)
	cache.set_retention('current.png', ['nearby.png'])
	assert cache.put('next.png', fourth_signature, sibling_cache_test_resource('next.png'), 10, 0)
	assert !cache.contains('old.png')
	assert cache.contains('nearby.png')
	assert cache.contains('current.png')
	assert cache.contains('next.png')
	assert cache.metrics.resident_bytes == 30
	cache.set_budget(20)
	assert cache.metrics.resident_bytes <= 20
	assert cache.contains('current.png')
	assert cache.contains('nearby.png')
}

fn test_sibling_resource_cache_rejects_oversize_entries_without_exceeding_budget() {
	mut cache := new_sibling_resource_cache(8)
	signature := SiblingFileSignature{ exists: true, size: 1, modified_unix: 1 }
	assert cache.put('fits.png', signature, sibling_cache_test_resource('fits.png'), 4, 4)
	assert !cache.put('too-large.png', signature, sibling_cache_test_resource('too-large.png'), 4, 5)
	assert cache.metrics.oversized == 1
	assert cache.metrics.resident_bytes == 8
	assert !cache.contains('too-large.png')
	cache.set_budget(4)
	assert cache.metrics.resident_bytes == 0
	assert !cache.contains('fits.png')
}

fn test_async_pipeline_cache_hit_reuses_resource_without_second_decode() {
	path := os.join_path(os.temp_dir(), 'image-ui-sibling-pipeline-${time.ticks()}.bmp')
	os.write_bytes(path, sibling_cache_test_bmp()) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	sibling_cache_test_decode_count = 0
	mut pipeline := new_image_pipeline_with_cache(sibling_cache_test_decoder, 1024)
	first_request := pipeline.request(path, 'first')
	mut first_result := ImagePipelineResult{}
	select {
		first_result = <-pipeline.result_ch {
		}
		5 * time.second {
			panic('sibling cache first decode timeout')
		}
	}
	pipeline.result_ch <- first_result
	first_results := pipeline.poll()
	assert first_results.len == 1
	assert first_results[0].request.generation == first_request.generation
	assert sibling_cache_test_decode_count == 1

	second_request := pipeline.request(path, 'resident')
	second_results := pipeline.poll()
	assert second_results.len == 1
	assert second_results[0].request.generation == second_request.generation
	assert second_results[0].resource.decoded_pixels() == first_results[0].resource.decoded_pixels()
	assert sibling_cache_test_decode_count == 1
	assert pipeline.metrics.started == 1
	assert pipeline.metrics.cache_hits == 1
	assert pipeline.metrics.cache_misses == 1
	assert pipeline.cache.metrics.hits == 1
	assert pipeline.cache.metrics.misses == 1
	assert pipeline.cache.metrics.resident_bytes == 8
	assert pipeline.cache.metrics.cpu_bytes == 4
	assert pipeline.cache.metrics.renderer_bytes == 4
}

fn test_prefetched_resource_is_reused_by_user_request_without_second_decode() {
	root := os.join_path(os.temp_dir(), 'image-ui-prefetch-reuse-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	previous := os.join_path(root, 'previous.bmp')
	current := os.join_path(root, 'current.bmp')
	next := os.join_path(root, 'next.bmp')
	for path in [previous, current, next] {
		os.write_bytes(path, sibling_cache_test_bmp()) or { panic(err) }
	}
	sibling_cache_test_decode_count = 0
	mut pipeline := new_image_pipeline_with_cache(sibling_cache_test_decoder, 1024)
	pipeline.set_prefetch_neighborhood(SiblingNeighborhood{
		scan_generation: 1
		direction:       1
		current_path:    current
	})
	mut prefetched := ImagePipelineResult{}
	select {
		prefetched = <-pipeline.prefetch.result_ch {
		}
		5 * time.second {
			panic('prefetch decode timeout')
		}
	}
	pipeline.prefetch.result_ch <- prefetched
	assert pipeline.poll().len == 0
	assert pipeline.prefetch_metrics().decode_count == 1
	assert pipeline.cache.contains(current)
	request := pipeline.request(current, 'user')
	results := pipeline.poll()
	assert results.len == 1
	assert results[0].request.generation == request.generation
	assert results[0].resource.source == current
	assert sibling_cache_test_decode_count == 1
	assert pipeline.metrics.resident_hits == 1
}

fn test_async_pipeline_reloads_after_file_signature_changes() {
	path := os.join_path(os.temp_dir(), 'image-ui-sibling-invalidation-${time.ticks()}.bmp')
	os.write_bytes(path, sibling_cache_test_bmp()) or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	sibling_cache_test_decode_count = 0
	mut pipeline := new_image_pipeline_with_cache(sibling_cache_test_decoder, 1024)
	pipeline.request(path, 'first')
	mut first_result := ImagePipelineResult{}
	select {
		first_result = <-pipeline.result_ch {
		}
		5 * time.second {
			panic('sibling cache first decode timeout')
		}
	}
	pipeline.result_ch <- first_result
	assert pipeline.poll().len == 1
	os.write_bytes(path, sibling_cache_test_bmp()) or { panic(err) }
	os.utime(path, 30, 40) or { panic(err) }
	second_request := pipeline.request(path, 'changed')
	mut second_result := ImagePipelineResult{}
	select {
		second_result = <-pipeline.result_ch {
		}
		5 * time.second {
			panic('sibling cache changed decode timeout')
		}
	}
	pipeline.result_ch <- second_result
	second_results := pipeline.poll()
	assert second_results.len == 1
	assert second_results[0].request.generation == second_request.generation
	assert second_results[0].resource.state == .ready
	assert sibling_cache_test_decode_count == 2
	assert pipeline.cache.metrics.invalidations == 1
	assert pipeline.cache.metrics.misses == 2
	assert pipeline.cache.metrics.hits == 0
}

fn test_pipeline_keeps_current_resource_when_obsolete_completion_arrives() {
	root := os.join_path(os.temp_dir(), 'image-ui-sibling-pending-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	current_path := os.join_path(root, 'current.png')
	first_path := os.join_path(root, 'first.png')
	latest_path := os.join_path(root, 'latest.png')
	for path in [current_path, first_path, latest_path] {
		os.write_file(path, 'fixture') or { panic(err) }
	}
	mut pipeline := new_manual_image_pipeline()
	pipeline.set_resident(sibling_cache_test_resource(current_path))
	pipeline.request(first_path, 'first')
	latest_request := pipeline.request(latest_path, 'latest')
	assert pipeline.complete_active(sibling_cache_test_resource(first_path))
	assert pipeline.poll().len == 0
	assert pipeline.resident_resource.source == current_path
	assert pipeline.complete(latest_request.generation, latest_request.path, sibling_cache_test_resource(latest_path))
	assert pipeline.poll().len == 1
	assert pipeline.resident_resource.source == latest_path
}

fn test_viewer_configures_nearby_retention_and_prefetches_immediate_neighborhood() {
	root := os.join_path(os.temp_dir(), 'image-ui-prefetch-neighborhood-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	previous := os.join_path(root, 'previous.png')
	current := os.join_path(root, 'current.png')
	next := os.join_path(root, 'next.png')
	for path in [previous, current, next] {
		os.write_file(path, 'fixture') or { panic(err) }
	}
	mut app := &ViewerApp{
		core:                              new_app()
		image_pipeline:                    new_manual_image_pipeline()
		sibling_cache_neighborhood_radius: 2
	}
	app.core.playlist = [previous, current, next]
	app.core.active_index = 1
	app.core.set_image_loaded(current, 1, 1)
	app.sync_sibling_cache_retention()

	assert app.image_pipeline.nearby_paths == [previous, next]
	assert app.image_pipeline.has_prefetch_active()
	assert app.image_pipeline.prefetch_active_request().path == current
	assert app.image_pipeline.has_prefetch_queued()
	assert app.image_pipeline.prefetch_queued_request().path == next
	assert app.image_pipeline.prefetch_metrics().requested == 3

	for expected_path in [current, next, previous] {
		assert app.image_pipeline.complete_prefetch_active(sibling_cache_test_resource(expected_path))
		assert app.image_pipeline.poll().len == 0
		assert app.image_pipeline.cache.contains(expected_path)
	}

	assert app.image_pipeline.prefetch_metrics().prefetched == 3
	assert app.image_pipeline.prefetch_pending_count() == 0
	assert app.image_pipeline.cache.metrics.resident_bytes <= app.image_pipeline.cache.budget_bytes
}

fn test_prefetch_stops_when_scan_generation_or_direction_changes() {
	root := os.join_path(os.temp_dir(), 'image-ui-prefetch-context-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	previous := os.join_path(root, 'previous.png')
	current := os.join_path(root, 'current.png')
	next := os.join_path(root, 'next.png')
	for path in [previous, current, next] {
		os.write_file(path, 'fixture') or { panic(err) }
	}
	mut pipeline := new_manual_image_pipeline()
	pipeline.set_prefetch_neighborhood(SiblingNeighborhood{
		scan_generation: 1
		direction:       1
		current_path:    current
	})

	first_generation := pipeline.prefetch_generation()
	assert pipeline.prefetch_active_request().path == current

	pipeline.set_prefetch_neighborhood(SiblingNeighborhood{
		scan_generation: 4
		direction:       -1
		previous_path:   previous
		current_path:    current
		next_path:       next
	})
	assert pipeline.prefetch_generation() > first_generation
	assert pipeline.prefetch_active_request().path == current
	pending_after_direction := pipeline.prefetch_pending_count()
	assert pending_after_direction == 4
	assert pipeline.complete_prefetch_active(sibling_cache_test_resource(current))
	assert pipeline.poll().len == 0
	assert !pipeline.cache.contains(current)
	assert pipeline.prefetch_active_request().path == current
	assert pipeline.prefetch_queued_request().path == previous

	pipeline.set_prefetch_neighborhood(SiblingNeighborhood{
		scan_generation: 5
		direction:       -1
		previous_path:   previous
		current_path:    current
		next_path:       next
	})
	assert pipeline.prefetch_scan_generation() == 5
	assert pipeline.prefetch_context_valid()
	pending_after_scan := pipeline.prefetch_pending_count()
	assert pending_after_scan == 4
	assert pipeline.prefetch_metrics().cancelled >= 2
	assert pipeline.prefetch_metrics().skipped >= 2
	stale_generation := pipeline.prefetch_generation()
	pipeline.set_prefetch_neighborhood(SiblingNeighborhood{
		scan_generation: 3
		direction:       1
		previous_path:   previous
		current_path:    next
		next_path:       current
	})
	assert pipeline.prefetch_scan_generation() == 5
	assert pipeline.prefetch_generation() == stale_generation
}

fn test_scanner_neighborhood_batch_starts_prefetch_for_discovered_paths() {
	root := os.join_path(os.temp_dir(), 'image-ui-scanner-prefetch-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	previous := os.join_path(root, '00-previous.png')
	current := os.join_path(root, '01-current.png')
	next := os.join_path(root, '02-next.png')
	for path in [previous, current, next] {
		os.write_file(path, 'fixture') or { panic(err) }
	}
	mut app := &ViewerApp{
		core:           new_app()
		image_pipeline: new_manual_image_pipeline()
	}
	app.core.open_path(current)
	app.core.playlist = [current]
	app.core.active_index = 0
	app.core.set_image_loaded(current, 1, 1)
	app.core.begin_scan(app.core.scan_generation)
	app.scanner_ch = chan SiblingBatch{cap: 1}
	app.has_scanner_ch = true
	app.scanner_ch <- SiblingBatch{
		items:           [previous, current, next]
		is_neighborhood: true
		is_last:         true
		generation:      app.core.scan_generation
	}
	app.poll_scanner()
	assert app.core.playlist == [previous, current, next]
	assert app.image_pipeline.has_prefetch_active()
	assert app.image_pipeline.prefetch_active_request().path == current
	assert app.image_pipeline.prefetch_queued_paths() == [next, previous]
	assert app.image_pipeline.prefetch_metrics().requested == 3
}

fn test_user_request_has_independent_priority_over_active_prefetch() {
	root := os.join_path(os.temp_dir(), 'image-ui-prefetch-priority-${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	previous := os.join_path(root, 'previous.png')
	current := os.join_path(root, 'current.png')
	next := os.join_path(root, 'next.png')
	for path in [previous, current, next] {
		os.write_file(path, 'fixture') or { panic(err) }
	}
	mut pipeline := new_manual_image_pipeline()
	pipeline.set_prefetch_neighborhood(SiblingNeighborhood{
		scan_generation: 1
		direction:       1
		previous_path:   previous
		current_path:    current
		next_path:       next
	})
	request := pipeline.request(next, 'user')
	assert pipeline.has_active
	assert pipeline.has_prefetch_active()
	assert pipeline.pending_count() == 1
	assert pipeline.complete(request.generation, request.path, sibling_cache_test_resource(next))
	results := pipeline.poll()
	assert results.len == 1
	assert results[0].request.path == next
	assert pipeline.has_prefetch_active()
}

fn test_cache_evicts_unrequired_entries_before_current_and_pending_resources() {
	mut cache := new_sibling_resource_cache(20)
	first_signature := SiblingFileSignature{ exists: true, size: 1, modified_unix: 1 }
	second_signature := SiblingFileSignature{ exists: true, size: 2, modified_unix: 2 }
	third_signature := SiblingFileSignature{ exists: true, size: 3, modified_unix: 3 }
	assert cache.put('current.png', first_signature, sibling_cache_test_resource('current.png'), 10, 0)
	assert cache.put('pending.png', second_signature, sibling_cache_test_resource('pending.png'), 10, 0)
	cache.set_requirements('current.png', ['current.png', 'pending.png'], [])
	assert !cache.put('prefetch.png', third_signature, sibling_cache_test_resource('prefetch.png'), 10, 0)
	assert cache.contains('current.png')
	assert cache.contains('pending.png')
	assert !cache.contains('prefetch.png')
}

fn test_sibling_resource_cache_is_independent_from_filmstrip_thumbnail_budget() {
	mut full_resolution := new_sibling_resource_cache(64)
	thumbnail_cache := new_sibling_resource_cache(20 * 1024 * 1024)
	signature := SiblingFileSignature{ exists: true, size: 1, modified_unix: 1 }
	assert full_resolution.put('full.png', signature, sibling_cache_test_resource('full.png'), 64, 0)
	assert !thumbnail_cache.contains('full.png')
	assert thumbnail_cache.metrics.resident_bytes == 0
	assert full_resolution.metrics.resident_bytes == 64
	assert thumbnail_cache.budget_bytes != full_resolution.budget_bytes
}
