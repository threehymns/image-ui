module main

import os
import stbi
import ui2

pub struct DecodedImage {
pub:
	width          int
	height         int
	channels       int
	pixels         []u8
	opacity        ui2.ImageOpacity
	renderer_bytes int
}

pub type ImageResourceDecoder = fn (string) !DecodedImage

pub struct ImageResourceLoader {
pub mut:
	decoder ImageResourceDecoder = unsafe { nil }
	next_id int
}

pub fn classify_image_opacity(channels int, pixels []u8) ui2.ImageOpacity {
	if channels == 3 && pixels.len >= 3 {
		return .proven_opaque
	}
	if channels != 4 || pixels.len < 4 {
		return .unknown
	}
	for index := 3; index < pixels.len; index += 4 {
		if pixels[index] != 255 {
			return .has_alpha
		}
	}
	return .proven_opaque
}

pub fn decode_stbi_image(path string) !DecodedImage {
	image_bytes := os.read_bytes(path) or {
		return error('Unable to read image: ${err.msg()}')
	}
	mut decoded := stbi.load_from_memory(image_bytes.data, image_bytes.len, stbi.LoadParams{}) or {
		return error('Unable to load image: ${err.msg()}')
	}
	if decoded.width <= 0 || decoded.height <= 0 {
		decoded.free()
		return error('decoded image has invalid dimensions')
	}
	pixel_len := decoded.width * decoded.height * 4
	mut pixels := []u8{len: pixel_len}
	copy(mut pixels, unsafe { decoded.data.vbytes(pixel_len) })
	opacity := classify_image_opacity(decoded.nr_channels, pixels)
	decoded.free()
	return DecodedImage{
		width:          decoded.width
		height:         decoded.height
		channels:       4
		pixels:         pixels
		opacity:        opacity
		renderer_bytes: pixel_len
	}
}

pub fn new_image_resource_loader(decoder ImageResourceDecoder) ImageResourceLoader {
	return ImageResourceLoader{
		decoder: decoder
	}
}

pub fn image_resource_from_decoded(id string, path string, decoded DecodedImage) ui2.ImageResource {
	if decoded.width <= 0 || decoded.height <= 0 || decoded.channels != 4 {
		return ui2.error_image_resource(id, path, 'decoded image has invalid metadata')
	}
	pixel_len := decoded.width * decoded.height * 4
	if decoded.pixels.len < pixel_len {
		return ui2.error_image_resource(id, path, 'decoded image has incomplete pixels')
	}
	return ui2.ready_image_resource(id, path, ui2.ImageResourceInput{
		width:    decoded.width
		height:   decoded.height
		channels: decoded.channels
		pixels:   decoded.pixels
	}, decoded.opacity)
}

pub fn image_resource_renderer_bytes(resource ui2.ImageResource) int {
	if resource.state != .ready || resource.id.len == 0 || resource.decoded_pixels().len == 0 {
		return 0
	}
	return resource.width() * resource.height() * resource.channels()
}

pub fn (mut loader ImageResourceLoader) load(path string) ui2.ImageResource {
	loader.next_id++
	return loader.load_with_id(path, 'image-resource-${loader.next_id}')
}

pub fn (mut loader ImageResourceLoader) load_with_id(path string, id string) ui2.ImageResource {
	if voidptr(loader.decoder) == unsafe { nil } {
		return ui2.error_image_resource(id, path, 'no image decoder configured')
	}
	decoded := loader.decoder(path) or {
		return ui2.error_image_resource(id, path, err.msg())
	}
	return image_resource_from_decoded(id, path, decoded)
}

pub struct ImageRequest {
pub:
	generation int
	path       string
	reason     string
mut:
	signature SiblingFileSignature
}

pub struct ImagePipelineResult {
pub:
	request        ImageRequest
	cpu_bytes      int
	renderer_bytes int
mut:
	resource  ui2.ImageResource
	signature SiblingFileSignature
}

pub struct ImagePipelineMetrics {
pub mut:
	requested     int
	started       int
	completed     int
	accepted      int
	committed     int
	rejected      int
	coalesced     int
	resident_hits int
	cache_hits    int
	cache_misses  int
	failed        int
	max_pending   int
}

pub struct ImagePipeline {
pub mut:
	decoder           ImageResourceDecoder = unsafe { nil }
	result_ch         chan ImagePipelineResult
	active_request    ImageRequest
	has_active        bool
	queued_request    ImageRequest
	has_queued        bool
	ready_request     ImageRequest
	ready_resource    ui2.ImageResource
	has_ready         bool
	desired_request   ImageRequest
	next_generation   int
	resident_resource ui2.ImageResource
	cache             SiblingResourceCache
	nearby_paths      []string
	neighbor_radius   int = default_sibling_cache_neighbor_radius
	metrics           ImagePipelineMetrics
	manual            bool
	configured        bool
}

pub fn new_image_pipeline(decoder ImageResourceDecoder) ImagePipeline {
	return new_image_pipeline_with_cache(decoder, configured_sibling_cache_budget_bytes())
}

pub fn new_image_pipeline_with_cache(decoder ImageResourceDecoder, budget_bytes int) ImagePipeline {
	return ImagePipeline{
		decoder:    decoder
		result_ch:  chan ImagePipelineResult{cap: 1}
		cache:      new_sibling_resource_cache(budget_bytes)
		configured: true
	}
}

pub fn new_manual_image_pipeline() ImagePipeline {
	mut pipeline := new_image_pipeline(unsafe { nil })
	pipeline.manual = true
	return pipeline
}

fn image_pipeline_worker(request ImageRequest, decoder ImageResourceDecoder, result_ch chan ImagePipelineResult) {
	mut resource := ui2.error_image_resource('image-resource-${request.generation}', request.path,
		'no image decoder configured')
	mut signature := request.signature
	mut cpu_bytes := 0
	mut renderer_bytes := 0
	if voidptr(decoder) != unsafe { nil } {
		before := sibling_file_signature(request.path)
		decoded := decoder(request.path) or {
			result_ch <- ImagePipelineResult{
				request:   request
				resource:  ui2.error_image_resource('image-resource-${request.generation}', request.path, err.msg())
				signature: signature
			}
			return
		}
		after := sibling_file_signature(request.path)
		if before.exists && after != before {
			result_ch <- ImagePipelineResult{
				request:   request
				resource:  ui2.error_image_resource('image-resource-${request.generation}', request.path, 'image file changed during decode')
				signature: after
			}
			return
		}
		signature = if after.exists { after } else { before }
		cpu_bytes = decoded.pixels.len
		resource = image_resource_from_decoded('image-resource-${request.generation}', request.path, decoded)
		renderer_bytes = if decoded.renderer_bytes > 0 {
			decoded.renderer_bytes
		} else {
			image_resource_renderer_bytes(resource)
		}
	}
	result_ch <- ImagePipelineResult{
		request:        request
		resource:       resource
		signature:      signature
		cpu_bytes:      cpu_bytes
		renderer_bytes: renderer_bytes
	}
}

fn (mut pipeline ImagePipeline) update_pending_metrics() {
	pending := pipeline.pending_count()
	if pending > pipeline.metrics.max_pending {
		pipeline.metrics.max_pending = pending
	}
}

pub fn (pipeline &ImagePipeline) pending_count() int {
	mut count := 0
	if pipeline.has_active {
		count++
	}
	if pipeline.has_queued {
		count++
	}
	if pipeline.has_ready {
		count++
	}
	return count
}

pub fn (pipeline &ImagePipeline) queued_count() int {
	return if pipeline.has_queued { 1 } else { 0 }
}

pub fn (pipeline &ImagePipeline) current_request() ImageRequest {
	return pipeline.desired_request
}

pub fn (mut pipeline ImagePipeline) set_cache_budget(budget_bytes int) {
	pipeline.cache.set_budget(budget_bytes)
	pipeline.update_retention()
}

pub fn (mut pipeline ImagePipeline) set_nearby_paths(paths []string) {
	pipeline.nearby_paths = paths.clone()
	pipeline.update_retention()
}

pub fn (mut pipeline ImagePipeline) update_retention() {
	mut paths := pipeline.nearby_paths.clone()
	if pipeline.has_active {
		paths << pipeline.active_request.path
	}
	if pipeline.has_queued {
		paths << pipeline.queued_request.path
	}
	if pipeline.has_ready {
		paths << pipeline.ready_request.path
	}
	if pipeline.desired_request.path != '' {
		paths << pipeline.desired_request.path
	}
	current_path := if pipeline.resident_resource.state == .ready {
		pipeline.resident_resource.source
	} else {
		''
	}
	pipeline.cache.set_retention(current_path, paths)
}

fn (mut pipeline ImagePipeline) cache_lookup(path string, signature SiblingFileSignature) ?ui2.ImageResource {
	before_hits := pipeline.cache.metrics.hits
	before_misses := pipeline.cache.metrics.misses
	resource := pipeline.cache.get(path, signature)
	pipeline.metrics.cache_hits += pipeline.cache.metrics.hits - before_hits
	pipeline.metrics.cache_misses += pipeline.cache.metrics.misses - before_misses
	return resource
}

fn (mut pipeline ImagePipeline) dispatch(request ImageRequest) {
	mut dispatched := request
	if !dispatched.signature.exists {
		dispatched.signature = sibling_file_signature(dispatched.path)
	}
	pipeline.active_request = dispatched
	pipeline.has_active = true
	pipeline.metrics.started++
	pipeline.update_retention()
	if !pipeline.manual && voidptr(pipeline.decoder) != unsafe { nil } {
		spawn image_pipeline_worker(dispatched, pipeline.decoder, pipeline.result_ch)
	}
}

fn (mut pipeline ImagePipeline) queue(request ImageRequest) {
	if pipeline.has_queued {
		pipeline.metrics.coalesced++
	}
	pipeline.queued_request = request
	pipeline.has_queued = true
}

fn (mut pipeline ImagePipeline) pump_queued() {
	if !pipeline.has_queued {
		return
	}
	mut request := pipeline.queued_request
	pipeline.has_queued = false
	request.signature = sibling_file_signature(request.path)
	pipeline.update_retention()
	if resource := pipeline.cache_lookup(request.path, request.signature) {
		pipeline.ready_request = request
		pipeline.ready_resource = resource
		pipeline.has_ready = true
		pipeline.update_retention()
	} else {
		pipeline.dispatch(request)
	}
}

fn (pipeline &ImagePipeline) result_is_current(result ImagePipelineResult) bool {
	return result.request.generation == pipeline.desired_request.generation
		&& result.request.path == pipeline.desired_request.path
}

pub fn (mut pipeline ImagePipeline) request(path string, reason string) ImageRequest {
	pipeline.next_generation++
	return pipeline.request_with_generation(path, reason, pipeline.next_generation)
}

pub fn (mut pipeline ImagePipeline) request_with_generation(path string, reason string, generation int) ImageRequest {
	if generation > pipeline.next_generation {
		pipeline.next_generation = generation
	}
	mut request := ImageRequest{
		generation: generation
		path:       path
		reason:     reason
		signature:  sibling_file_signature(path)
	}
	pipeline.desired_request = request
	pipeline.metrics.requested++
	if voidptr(pipeline.decoder) == unsafe { nil } {
		pipeline.manual = true
	}
	pipeline.update_retention()
	mut cache_hit := false
	if resource := pipeline.cache_lookup(path, request.signature) {
		cache_hit = true
		pipeline.metrics.resident_hits++
		pipeline.ready_resource = resource
		if pipeline.has_active {
			pipeline.queue(request)
		} else if pipeline.has_ready {
			pipeline.metrics.coalesced++
			pipeline.ready_request = request
		} else {
			pipeline.ready_request = request
			pipeline.has_ready = true
		}
		pipeline.update_retention()
	}
	if !cache_hit {
		if pipeline.has_active {
			pipeline.queue(request)
		} else {
			pipeline.has_ready = false
			pipeline.dispatch(request)
		}
		pipeline.update_retention()
	}
	pipeline.update_pending_metrics()
	return request
}

pub fn (mut pipeline ImagePipeline) cancel() {
	pipeline.next_generation++
	pipeline.desired_request = ImageRequest{
		generation: pipeline.next_generation
		path:       ''
		reason:     'cancel'
	}
	pipeline.has_queued = false
	pipeline.has_ready = false
	pipeline.ready_resource = ui2.ImageResource{}
	pipeline.update_retention()
	pipeline.update_pending_metrics()
}

pub fn (mut pipeline ImagePipeline) set_resident(resource ui2.ImageResource) {
	if resource.state == .ready {
		pipeline.resident_resource = resource
		signature := sibling_file_signature(resource.source)
		if signature.exists && resource.id.len > 0 && resource.decoded_pixels().len > 0
			&& !pipeline.cache.contains(resource.source) {
			pipeline.cache.put(resource.source, signature, resource,
				resource.decoded_pixels().len, image_resource_renderer_bytes(resource))
		}
		pipeline.update_retention()
	}
}

pub fn (mut pipeline ImagePipeline) clear_resident() {
	pipeline.resident_resource = ui2.ImageResource{}
	pipeline.has_ready = false
	pipeline.ready_resource = ui2.ImageResource{}
	pipeline.update_retention()
}

pub fn (mut pipeline ImagePipeline) complete_active(resource ui2.ImageResource) bool {
	if !pipeline.has_active {
		return false
	}
	result := ImagePipelineResult{
		request:        pipeline.active_request
		resource:       resource
		signature:      sibling_file_signature(pipeline.active_request.path)
		cpu_bytes:      resource.decoded_pixels().len
		renderer_bytes: image_resource_renderer_bytes(resource)
	}
	mut sent := false
	select {
		pipeline.result_ch <- result {
			sent = true
		}
		else {
		}
	}
	return sent
}

pub fn (mut pipeline ImagePipeline) complete(generation int, path string, resource ui2.ImageResource) bool {
	if !pipeline.has_active || pipeline.active_request.generation != generation || pipeline.active_request.path != path {
		return false
	}
	return pipeline.complete_active(resource)
}

pub fn (mut pipeline ImagePipeline) fail_active(generation int, path string, message string) bool {
	if !pipeline.complete(generation, path, ui2.error_image_resource('image-resource-${generation}', path, message)) {
		return false
	}
	return true
}

pub fn (mut pipeline ImagePipeline) mark_committed(request ImageRequest) {
	if request.generation == pipeline.desired_request.generation && request.path == pipeline.desired_request.path {
		pipeline.metrics.committed++
	}
}

fn (mut pipeline ImagePipeline) collect_ready(mut accepted []ImagePipelineResult) []ImagePipelineResult {
	if !pipeline.has_ready {
		return accepted
	}
	request := pipeline.ready_request
	resource := pipeline.ready_resource
	pipeline.has_ready = false
	pipeline.ready_resource = ui2.ImageResource{}
	if request.generation == pipeline.desired_request.generation && request.path == pipeline.desired_request.path {
		accepted << ImagePipelineResult{
			request:        request
			resource:       resource
			signature:      request.signature
			cpu_bytes:      resource.decoded_pixels().len
			renderer_bytes: image_resource_renderer_bytes(resource)
		}
		pipeline.metrics.accepted++
		if resource.state == .error {
			pipeline.metrics.failed++
		}
	} else {
		pipeline.metrics.rejected++
	}
	pipeline.update_retention()
	return accepted
}

pub fn (mut pipeline ImagePipeline) poll() []ImagePipelineResult {
	mut accepted := []ImagePipelineResult{}
	accepted = pipeline.collect_ready(mut accepted)
	mut drained := 0
	for drained < 4 {
		select {
			result := <-pipeline.result_ch {
				drained++
				if !pipeline.has_active || result.request.generation != pipeline.active_request.generation
					|| result.request.path != pipeline.active_request.path {
					pipeline.metrics.rejected++
					continue
				}
				pipeline.has_active = false
				pipeline.metrics.completed++
				mut normalized := result
				if normalized.resource.state == .ready {
					current_signature := sibling_file_signature(normalized.request.path)
					if normalized.signature.exists && current_signature != normalized.signature {
						normalized.resource = ui2.error_image_resource('image-resource-${normalized.request.generation}',
							normalized.request.path, 'image file changed during decode')
						normalized.signature = current_signature
					} else {
						if !normalized.signature.exists {
							normalized.signature = current_signature
						}
						if normalized.signature.exists {
							pipeline.cache.put(normalized.request.path, normalized.signature, normalized.resource,
								normalized.cpu_bytes, normalized.renderer_bytes)
							pipeline.resident_resource = normalized.resource
						}
					}
				}
				if pipeline.result_is_current(normalized) {
					accepted << normalized
					pipeline.metrics.accepted++
					if normalized.resource.state == .error {
						pipeline.metrics.failed++
					}
				} else {
					pipeline.metrics.rejected++
				}
				pipeline.update_retention()
				if pipeline.has_queued {
					pipeline.pump_queued()
				}
			}
			else {
				break
			}
		}
	}
	if pipeline.has_queued && !pipeline.has_active {
		pipeline.pump_queued()
	}
	accepted = pipeline.collect_ready(mut accepted)
	pipeline.update_pending_metrics()
	return accepted
}
