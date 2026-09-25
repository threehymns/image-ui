module main

import os
import stbi
import ui2

pub struct DecodedImage {
pub:
	width    int
	height   int
	channels int
	pixels   []u8
	opacity  ui2.ImageOpacity
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
		width:    decoded.width
		height:   decoded.height
		channels: 4
		pixels:   pixels
		opacity:  opacity
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
}

pub struct ImagePipelineResult {
pub:
	request  ImageRequest
	resource ui2.ImageResource
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
	has_ready         bool
	desired_request   ImageRequest
	next_generation   int
	resident_resource ui2.ImageResource
	metrics           ImagePipelineMetrics
	manual            bool
	configured        bool
}

pub fn new_image_pipeline(decoder ImageResourceDecoder) ImagePipeline {
	return ImagePipeline{
		decoder:    decoder
		result_ch:  chan ImagePipelineResult{cap: 1}
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
	if voidptr(decoder) != unsafe { nil } {
		decoded := decoder(request.path) or {
			result_ch <- ImagePipelineResult{
				request:  request
				resource: ui2.error_image_resource('image-resource-${request.generation}', request.path, err.msg())
			}
			return
		}
		resource = image_resource_from_decoded('image-resource-${request.generation}', request.path, decoded)
	}
	result_ch <- ImagePipelineResult{
		request:  request
		resource: resource
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

fn (mut pipeline ImagePipeline) dispatch(request ImageRequest) {
	pipeline.active_request = request
	pipeline.has_active = true
	pipeline.metrics.started++
	if !pipeline.manual && voidptr(pipeline.decoder) != unsafe { nil } {
		spawn image_pipeline_worker(request, pipeline.decoder, pipeline.result_ch)
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
	request := pipeline.queued_request
	pipeline.has_queued = false
	if pipeline.resident_resource.state == .ready && pipeline.resident_resource.source == request.path {
		pipeline.ready_request = request
		pipeline.has_ready = true
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
	request := ImageRequest{
		generation: generation
		path:       path
		reason:     reason
	}
	pipeline.desired_request = request
	pipeline.metrics.requested++
	if voidptr(pipeline.decoder) == unsafe { nil } {
		pipeline.manual = true
	}
	if pipeline.resident_resource.state == .ready && pipeline.resident_resource.source == path {
		pipeline.metrics.resident_hits++
		if pipeline.has_active {
			pipeline.queue(request)
		} else if pipeline.has_ready {
			pipeline.metrics.coalesced++
			pipeline.ready_request = request
		} else {
			pipeline.ready_request = request
			pipeline.has_ready = true
		}
	} else if pipeline.has_active {
		pipeline.queue(request)
	} else {
		pipeline.has_ready = false
		pipeline.dispatch(request)
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
	pipeline.update_pending_metrics()
}

pub fn (mut pipeline ImagePipeline) set_resident(resource ui2.ImageResource) {
	if resource.state == .ready {
		pipeline.resident_resource = resource
	}
}

pub fn (mut pipeline ImagePipeline) clear_resident() {
	pipeline.resident_resource = ui2.ImageResource{}
	pipeline.has_ready = false
}

pub fn (mut pipeline ImagePipeline) complete_active(resource ui2.ImageResource) bool {
	if !pipeline.has_active {
		return false
	}
	result := ImagePipelineResult{
		request:  pipeline.active_request
		resource: resource
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
	pipeline.has_ready = false
	if request.generation == pipeline.desired_request.generation && request.path == pipeline.desired_request.path {
		accepted << ImagePipelineResult{
			request:  request
			resource: pipeline.resident_resource
		}
		pipeline.metrics.accepted++
		if pipeline.resident_resource.state == .error {
			pipeline.metrics.failed++
		}
	} else {
		pipeline.metrics.rejected++
	}
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
				if pipeline.result_is_current(result) {
					accepted << result
					pipeline.metrics.accepted++
					if result.resource.state == .error {
						pipeline.metrics.failed++
					}
				} else {
					pipeline.metrics.rejected++
				}
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
