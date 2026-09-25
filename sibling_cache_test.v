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

fn test_viewer_configures_nearby_retention_without_prefetching() {
	mut app := &ViewerApp{
		core:                          new_app()
		image_pipeline:                new_manual_image_pipeline()
		sibling_cache_neighbor_radius: 2
	}
	app.ensure_image_pipeline()
	app.core.playlist = ['0.png', '1.png', '2.png', '3.png', '4.png', '5.png']
	app.core.active_index = 3
	app.sync_sibling_cache_retention()
	assert app.image_pipeline.nearby_paths == ['1.png', '2.png', '4.png', '5.png']
	assert app.image_pipeline.cache.metrics.resident_entries == 0
	assert app.image_pipeline.metrics.started == 0
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
