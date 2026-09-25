module main

import os
import stbi
import sync
import time
import ui2

pub struct DecodedImage {
pub:
	width              int
	height             int
	channels           int
	pixels             []u8
	opacity            ui2.ImageOpacity
	renderer_bytes     int
	source_size        u64
	content_digest     string
	has_content_digest bool
}

pub type ImageResourceDecoder = fn (string) !DecodedImage
pub type ImageContentSignatureReader = fn (string) SiblingFileSignature

struct CurrentResourceValidationResult {
	path      string
	epoch     u64
	signature SiblingFileSignature
}

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
	// A full-resolution image has millions of alpha samples, so the scan uses
	// unchecked pointer steps instead of bounds-checked slice indexing.
	unsafe {
		start := &u8(pixels.data) + 3
		end := &u8(pixels.data) + pixels.len
		for start < end {
			if *start != 255 {
				return .has_alpha
			}
			start += 4
		}
	}
	return .proven_opaque
}

pub fn decode_stbi_image(path string) !DecodedImage {
	// The decoder reads the file inside stb, so a full-resolution image does not
	// need a second copy of its encoded bytes in managed memory.
	mut decoded := stbi.load(path, stbi.LoadParams{}) or {
		return error('Unable to load image: ${path}')
	}
	width := decoded.width
	height := decoded.height
	channels := decoded.nr_channels
	if width <= 0 || height <= 0 {
		decoded.free()
		return error('decoded image has invalid metadata')
	}
	pixel_len := width * height * 4
	mut pixels := []u8{len: pixel_len}
	copy(mut pixels, unsafe { decoded.data.vbytes(pixel_len) })
	opacity := classify_image_opacity(channels, pixels)
	decoded.free()
	// Decoding stays off the content-digest path. Cache lookups compare stat
	// identity, and hashing a full-resolution file here cost seconds per image.
	return DecodedImage{
		width:          width
		height:         height
		channels:       4
		pixels:         pixels
		opacity:        opacity
		renderer_bytes: pixel_len
		source_size:    if info := os.stat(path) { info.size } else { 0 }
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

pub struct CancellationToken {
mut:
	done           chan bool
	mutex          &sync.Mutex
	cancelled_flag bool
}

pub fn new_cancellation_token() &CancellationToken {
	return &CancellationToken{
		done:  chan bool{}
		mutex: sync.new_mutex()
	}
}

pub fn (mut token CancellationToken) cancel() {
	token.mutex.lock()
	if !token.cancelled_flag {
		token.done.close()
		token.cancelled_flag = true
	}
	token.mutex.unlock()
}

pub fn (token &CancellationToken) cancelled() bool {
	token.mutex.lock()
	result := token.cancelled_flag
	token.mutex.unlock()
	return result
}

pub struct ImageRequest {
pub:
	generation int
	path       string
	reason     string
mut:
	signature SiblingFileSignature
}

pub struct SiblingNeighborhood {
pub:
	scan_generation int
	direction       int
	previous_path   string
	current_path    string
	next_path       string
}

pub struct ImagePipelineResult {
pub:
	request        ImageRequest
	cpu_bytes      int
	renderer_bytes int
	decode_count   int
	cancelled      bool
mut:
	resource  ui2.ImageResource
	signature SiblingFileSignature
}

fn image_active_cancellation_transition(has_active bool, active_cancelled bool,
	token ?&CancellationToken) bool {
	if !has_active || active_cancelled {
		return false
	}
	if active_token := token {
		active_token.cancel()
	}
	return true
}

fn image_result_cancellation_transition(result_cancelled bool, active_cancelled bool) bool {
	return result_cancelled && !active_cancelled
}

pub struct ImagePipelineMetrics {
pub mut:
	requested                 int
	started                   int
	completed                 int
	accepted                  int
	committed                 int
	displayed                 int
	skipped                   int
	rejected                  int
	coalesced                 int
	cancelled                 int
	resident_hits             int
	cache_hits                int
	cache_misses              int
	cache_updates             int
	cache_evictions           int
	cache_invalidations       int
	cache_content_validations int
	cache_resident_bytes      int
	cache_peak_bytes          int
	cache_cpu_bytes           int
	cache_renderer_bytes      int
	cache_budget              int
	decode_count              int
	failed                    int
	max_pending               int
	max_total_pending         int
}

pub struct ImagePrefetchMetrics {
pub mut:
	requested     int
	started       int
	completed     int
	prefetched    int
	skipped       int
	coalesced     int
	cancelled     int
	resident_hits int
	cache_hits    int
	cache_misses  int
	decode_count  int
	max_pending   int
}

pub struct ImagePrefetchScheduler {
pub mut:
	result_ch            chan ImagePipelineResult
	active_request       ImageRequest
	has_active           bool
	active_token         ?&CancellationToken
	active_cancelled     bool
	queued_paths         []string
	queued_request       ImageRequest
	has_queued           bool
	generation           int
	scan_generation      int
	direction            int
	context_valid        bool
	neighborhood_paths   []string
	last_prefetched_path string
	has_last_prefetched  bool
	metrics              ImagePrefetchMetrics
}

pub struct ImagePipeline {
pub mut:
	decoder                          ImageResourceDecoder = unsafe { nil }
	result_ch                        chan ImagePipelineResult
	active_request                   ImageRequest
	active_token                     ?&CancellationToken
	has_active                       bool
	active_cancelled                 bool
	queued_request                   ImageRequest
	has_queued                       bool
	ready_request                    ImageRequest
	ready_resource                   ui2.ImageResource
	has_ready                        bool
	desired_request                  ImageRequest
	next_generation                  int
	resident_resource                ui2.ImageResource
	resident_signature               SiblingFileSignature
	cache                            SiblingResourceCache
	nearby_paths                     []string
	sibling_neighborhood_radius      int = default_sibling_cache_neighborhood_radius
	prefetch                         ImagePrefetchScheduler
	metrics                          ImagePipelineMetrics
	manual                           bool
	configured                       bool
	current_revalidation_interval_ns u64 = 1_000_000_000
	last_current_revalidation_ns     u64
	current_resource_invalidated     bool
	current_validation_ch            chan CurrentResourceValidationResult
	current_validation_in_flight     bool
	current_validation_epoch         u64
	current_validation_reader        ImageContentSignatureReader = unsafe { nil }
}

pub fn new_image_pipeline(decoder ImageResourceDecoder) ImagePipeline {
	return new_image_pipeline_with_cache(decoder, configured_sibling_cache_budget_bytes())
}

pub fn new_image_pipeline_with_cache(decoder ImageResourceDecoder, budget_bytes int) ImagePipeline {
	return ImagePipeline{
		decoder:                      decoder
		result_ch:                    chan ImagePipelineResult{cap: 1}
		cache:                        new_sibling_resource_cache(budget_bytes)
		prefetch:                     new_image_prefetch_scheduler()
		current_validation_ch:        chan CurrentResourceValidationResult{cap: 1}
		current_validation_reader:    sibling_file_content_signature
		last_current_revalidation_ns: time.sys_mono_now()
		configured:                   true
	}
}

pub fn new_manual_image_pipeline() ImagePipeline {
	mut pipeline := new_image_pipeline(unsafe { nil })
	pipeline.manual = true
	return pipeline
}

fn new_image_prefetch_scheduler() ImagePrefetchScheduler {
	return ImagePrefetchScheduler{
		result_ch: chan ImagePipelineResult{cap: 1}
	}
}

fn image_error_result(request ImageRequest, signature SiblingFileSignature, message string,
	decode_count int, cancelled bool) ImagePipelineResult {
	return ImagePipelineResult{
		request:      request
		resource:     ui2.error_image_resource('image-resource-${request.generation}', request.path, message)
		signature:    signature
		decode_count: decode_count
		cancelled:    cancelled
	}
}

fn image_signature_with_decoded_digest(signature SiblingFileSignature, decoded DecodedImage) SiblingFileSignature {
	if !decoded.has_content_digest {
		return signature
	}
	return SiblingFileSignature{
		exists:             true
		size:               if decoded.source_size > 0 {
			decoded.source_size
		} else {
			signature.size
		}
		modified_unix:      signature.modified_unix
		changed_unix:       signature.changed_unix
		device:             signature.device
		inode:              signature.inode
		links:              signature.links
		content_digest:     decoded.content_digest
		has_content_digest: true
	}
}

fn decode_image_request(request ImageRequest, decoder ImageResourceDecoder,
	token &CancellationToken) ImagePipelineResult {
	mut signature := request.signature
	if token.cancelled() {
		return image_error_result(request, signature, 'image request cancelled', 0, true)
	}
	if voidptr(decoder) == unsafe { nil } {
		return image_error_result(request, signature, 'no image decoder configured', 0, false)
	}
	before := sibling_file_signature(request.path)
	if token.cancelled() {
		return image_error_result(request, before, 'image request cancelled', 0, true)
	}
	decoded := decoder(request.path) or {
		if token.cancelled() {
			return image_error_result(request, before, 'image request cancelled', 1, true)
		}
		return image_error_result(request, before, err.msg(), 1, false)
	}
	if token.cancelled() {
		return image_error_result(request, before, 'image request cancelled', 1, true)
	}
	after := sibling_file_signature(request.path)
	if before.exists && after != before {
		return image_error_result(request, after, 'image file changed during decode', 1, false)
	}
	signature = if after.exists { after } else { before }
	if decoded.has_content_digest {
		signature = image_signature_with_decoded_digest(signature, decoded)
	} else {
		signature = sibling_file_content_signature(request.path)
	}
	if token.cancelled() {
		return image_error_result(request, signature, 'image request cancelled', 1, true)
	}
	resource := image_resource_from_decoded('image-resource-${request.generation}', request.path, decoded)
	return ImagePipelineResult{
		request:        request
		resource:       resource
		signature:      signature
		cpu_bytes:      decoded.pixels.len
		renderer_bytes: if decoded.renderer_bytes > 0 {
			decoded.renderer_bytes
		} else {
			image_resource_renderer_bytes(resource)
		}
		decode_count:   1
	}
}

fn image_decode_worker(request ImageRequest, decoder ImageResourceDecoder, token &CancellationToken,
	result_ch chan ImagePipelineResult) {
	result_ch <- decode_image_request(request, decoder, token)
}

fn (mut pipeline ImagePipeline) update_pending_metrics() {
	pending := pipeline.pending_count()
	if pending > pipeline.metrics.max_pending {
		pipeline.metrics.max_pending = pending
	}
	prefetch_pending := pipeline.prefetch_pending_count()
	if prefetch_pending > pipeline.prefetch.metrics.max_pending {
		pipeline.prefetch.metrics.max_pending = prefetch_pending
	}
	total := pending + prefetch_pending
	if total > pipeline.metrics.max_total_pending {
		pipeline.metrics.max_total_pending = total
	}
}

fn (mut pipeline ImagePipeline) sync_cache_metrics() {
	cache_metrics := pipeline.cache.metrics
	pipeline.metrics.cache_updates = cache_metrics.updates
	pipeline.metrics.cache_evictions = cache_metrics.evictions
	pipeline.metrics.cache_invalidations = cache_metrics.invalidations
	pipeline.metrics.cache_content_validations = cache_metrics.content_validations
	pipeline.metrics.cache_resident_bytes = cache_metrics.resident_bytes
	pipeline.metrics.cache_peak_bytes = cache_metrics.peak_bytes
	pipeline.metrics.cache_cpu_bytes = cache_metrics.cpu_bytes
	pipeline.metrics.cache_renderer_bytes = cache_metrics.renderer_bytes
	pipeline.metrics.cache_budget = pipeline.cache.budget_bytes
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

pub fn (pipeline &ImagePipeline) prefetch_pending_count() int {
	mut count := pipeline.prefetch.queued_paths.len
	if pipeline.prefetch.has_active {
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

pub fn (pipeline &ImagePipeline) prefetch_metrics() ImagePrefetchMetrics {
	return pipeline.prefetch.metrics
}

pub fn (pipeline &ImagePipeline) has_prefetch_active() bool {
	return pipeline.prefetch.has_active
}

pub fn (pipeline &ImagePipeline) prefetch_active_request() ImageRequest {
	return pipeline.prefetch.active_request
}

pub fn (pipeline &ImagePipeline) prefetch_queued_request() ImageRequest {
	return pipeline.prefetch.queued_request
}

pub fn (pipeline &ImagePipeline) has_prefetch_queued() bool {
	return pipeline.prefetch.has_queued
}

pub fn (pipeline &ImagePipeline) prefetch_queued_paths() []string {
	return pipeline.prefetch.queued_paths.clone()
}

pub fn (pipeline &ImagePipeline) prefetch_generation() int {
	return pipeline.prefetch.generation
}

pub fn (pipeline &ImagePipeline) prefetch_scan_generation() int {
	return pipeline.prefetch.scan_generation
}

pub fn (pipeline &ImagePipeline) prefetch_context_valid() bool {
	return pipeline.prefetch.context_valid
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
	mut nearby := pipeline.nearby_paths.clone()
	for path in pipeline.prefetch.neighborhood_paths {
		if path !in nearby {
			nearby << path
		}
	}
	mut required := []string{}
	if pipeline.has_active {
		required << pipeline.active_request.path
	}
	if pipeline.has_queued {
		required << pipeline.queued_request.path
	}
	if pipeline.has_ready {
		required << pipeline.ready_request.path
	}
	if pipeline.desired_request.path != '' {
		required << pipeline.desired_request.path
	}
	current_path := if pipeline.resident_resource.state == .ready {
		pipeline.resident_resource.source
	} else {
		''
	}
	if current_path != '' {
		required << current_path
	}
	pipeline.cache.set_requirements(current_path, required, nearby)
	pipeline.sync_cache_metrics()
}

fn (mut pipeline ImagePipeline) cache_lookup(path string, signature SiblingFileSignature) ?ui2.ImageResource {
	before_hits := pipeline.cache.metrics.hits
	before_misses := pipeline.cache.metrics.misses
	resource := pipeline.cache.get(path, signature)
	pipeline.metrics.cache_hits += pipeline.cache.metrics.hits - before_hits
	pipeline.metrics.cache_misses += pipeline.cache.metrics.misses - before_misses
	pipeline.sync_cache_metrics()
	return resource
}

fn (pipeline &ImagePipeline) user_path_has_priority(path string) bool {
	if path == '' {
		return false
	}
	if pipeline.has_active && pipeline.active_request.path == path {
		return true
	}
	if pipeline.has_queued && pipeline.queued_request.path == path {
		return true
	}
	if pipeline.has_ready && pipeline.ready_request.path == path {
		return true
	}
	if pipeline.desired_request.path == path {
		return true
	}
	return pipeline.resident_resource.state == .ready && pipeline.resident_resource.source == path
}

fn (mut scheduler ImagePrefetchScheduler) sync_queue_state() {
	if scheduler.queued_paths.len == 0 {
		scheduler.has_queued = false
		scheduler.queued_request = ImageRequest{}
		return
	}
	scheduler.has_queued = true
	scheduler.queued_request = ImageRequest{
		generation: 0
		path:       scheduler.queued_paths[0]
		reason:     'prefetch'
		signature:  sibling_file_signature(scheduler.queued_paths[0])
	}
}

fn (mut scheduler ImagePrefetchScheduler) cancel(replaced bool) bool {
	had_work := scheduler.context_valid || scheduler.has_active || scheduler.queued_paths.len > 0
	if !had_work {
		return false
	}
	scheduler.generation++
	scheduler.context_valid = false
	scheduler.neighborhood_paths = []string{}
	if scheduler.has_active {
		if image_active_cancellation_transition(scheduler.has_active, scheduler.active_cancelled,
			scheduler.active_token) {
			scheduler.active_cancelled = true
			scheduler.metrics.skipped++
			scheduler.metrics.cancelled++
		}
	}
	queued_count := scheduler.queued_paths.len
	for _ in 0 .. queued_count {
		scheduler.metrics.skipped++
		scheduler.metrics.cancelled++
	}
	if replaced {
		scheduler.metrics.coalesced += queued_count
	}
	scheduler.queued_paths = []string{}
	scheduler.sync_queue_state()
	return true
}

fn (mut pipeline ImagePipeline) enqueue_prefetch_path(path string) {
	if path == '' || path in pipeline.prefetch.queued_paths || pipeline.user_path_has_priority(path) {
		pipeline.prefetch.metrics.skipped++
		return
	}
	pipeline.prefetch.queued_paths << path
	pipeline.prefetch.sync_queue_state()
}

fn (mut pipeline ImagePipeline) pump_prefetch() {
	for pipeline.prefetch.has_queued && !pipeline.prefetch.has_active {
		path := pipeline.prefetch.queued_paths[0]
		pipeline.prefetch.queued_paths.delete(0)
		pipeline.prefetch.sync_queue_state()
		if pipeline.user_path_has_priority(path) {
			pipeline.prefetch.metrics.skipped++
			continue
		}
		signature := sibling_file_signature(path)
		if !signature.exists {
			pipeline.prefetch.metrics.skipped++
			continue
		}
		before_hits := pipeline.cache.metrics.hits
		before_misses := pipeline.cache.metrics.misses
		if _ := pipeline.cache.get(path, signature) {
			pipeline.prefetch.metrics.cache_hits += pipeline.cache.metrics.hits - before_hits
			pipeline.prefetch.metrics.cache_misses += pipeline.cache.metrics.misses - before_misses
			pipeline.prefetch.metrics.resident_hits++
			pipeline.prefetch.metrics.skipped++
			continue
		}
		pipeline.prefetch.metrics.cache_hits += pipeline.cache.metrics.hits - before_hits
		pipeline.prefetch.metrics.cache_misses += pipeline.cache.metrics.misses - before_misses
		pipeline.prefetch.generation++
		pipeline.prefetch.active_request = ImageRequest{
			generation: pipeline.prefetch.generation
			path:       path
			reason:     'prefetch'
			signature:  signature
		}
		pipeline.prefetch.has_active = true
		pipeline.prefetch.active_cancelled = false
		pipeline.prefetch.metrics.started++
		if voidptr(pipeline.decoder) == unsafe { nil } {
			pipeline.manual = true
		} else if !pipeline.manual {
			token := new_cancellation_token()
			pipeline.prefetch.active_token = token
			spawn image_decode_worker(pipeline.prefetch.active_request, pipeline.decoder, token,
				pipeline.prefetch.result_ch)
		}
		break
	}
	pipeline.update_retention()
	pipeline.update_pending_metrics()
}

pub fn (mut pipeline ImagePipeline) set_prefetch_neighborhood(neighborhood SiblingNeighborhood) {
	if neighborhood.scan_generation < pipeline.prefetch.scan_generation {
		return
	}
	mut candidates := []string{}
	if neighborhood.direction < 0 {
		candidates << neighborhood.current_path
		candidates << neighborhood.previous_path
		candidates << neighborhood.next_path
	} else {
		candidates << neighborhood.current_path
		candidates << neighborhood.next_path
		candidates << neighborhood.previous_path
	}
	mut unique := []string{}
	for path in candidates {
		if path != '' && path !in unique {
			unique << path
		}
	}
	if pipeline.prefetch.context_valid
		&& pipeline.prefetch.scan_generation == neighborhood.scan_generation
		&& pipeline.prefetch.direction == neighborhood.direction
		&& pipeline.prefetch.neighborhood_paths == unique {
		return
	}
	if pipeline.prefetch.cancel(true) {
		pipeline.update_retention()
	}
	pipeline.prefetch.scan_generation = neighborhood.scan_generation
	pipeline.prefetch.direction = neighborhood.direction
	pipeline.prefetch.context_valid = true
	pipeline.prefetch.neighborhood_paths = unique.clone()
	for path in unique {
		pipeline.prefetch.metrics.requested++
		pipeline.enqueue_prefetch_path(path)
	}
	pipeline.pump_prefetch()
}

pub fn (mut pipeline ImagePipeline) take_prefetched_path() string {
	if !pipeline.prefetch.has_last_prefetched {
		return ''
	}
	path := pipeline.prefetch.last_prefetched_path
	pipeline.prefetch.last_prefetched_path = ''
	pipeline.prefetch.has_last_prefetched = false
	return path
}

fn (mut pipeline ImagePipeline) cancel_active_user() {
	if image_active_cancellation_transition(pipeline.has_active, pipeline.active_cancelled,
		pipeline.active_token) {
		pipeline.active_cancelled = true
		pipeline.metrics.cancelled++
	}
}

fn (mut pipeline ImagePipeline) dispatch(request ImageRequest) {
	mut dispatched := request
	if !dispatched.signature.exists {
		dispatched.signature = sibling_file_signature(dispatched.path)
	}
	pipeline.active_request = dispatched
	pipeline.has_active = true
	pipeline.active_cancelled = false
	pipeline.metrics.started++
	pipeline.update_retention()
	if !pipeline.manual && voidptr(pipeline.decoder) != unsafe { nil } {
		token := new_cancellation_token()
		pipeline.active_token = token
		spawn image_decode_worker(dispatched, pipeline.decoder, token, pipeline.result_ch)
	}
}

fn (mut pipeline ImagePipeline) queue(request ImageRequest) {
	if pipeline.has_queued {
		pipeline.metrics.coalesced++
		pipeline.metrics.skipped++
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
	pipeline.prefetch.cancel(false)
	pipeline.cancel_active_user()
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
			pipeline.metrics.skipped++
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
			if pipeline.has_ready {
				pipeline.metrics.coalesced++
				pipeline.metrics.skipped++
				pipeline.ready_resource = ui2.ImageResource{}
				pipeline.ready_request = ImageRequest{}
			}
			pipeline.has_ready = false
			pipeline.dispatch(request)
		}
		pipeline.update_retention()
	}
	pipeline.update_pending_metrics()
	return request
}

pub fn (mut pipeline ImagePipeline) cancel() {
	pipeline.prefetch.cancel(false)
	pipeline.cancel_active_user()
	pipeline.next_generation++
	pipeline.desired_request = ImageRequest{
		generation: pipeline.next_generation
		path:       ''
		reason:     'cancel'
	}
	if pipeline.has_queued {
		pipeline.metrics.skipped++
	}
	pipeline.has_queued = false
	pipeline.has_ready = false
	pipeline.ready_resource = ui2.ImageResource{}
	pipeline.update_retention()
	pipeline.update_pending_metrics()
}

pub fn (mut pipeline ImagePipeline) set_resident(resource ui2.ImageResource) {
	mut signature := SiblingFileSignature{}
	if cached := pipeline.cache.signature(resource.source) {
		signature = cached
	}
	if !signature.exists || !signature.has_content_digest {
		signature = sibling_file_signature(resource.source)
	}
	pipeline.set_resident_with_signature(resource, signature)
}

pub fn (mut pipeline ImagePipeline) set_resident_with_signature(resource ui2.ImageResource, signature SiblingFileSignature) {
	if resource.state == .ready {
		pipeline.resident_resource = resource
		pipeline.resident_signature = if signature.exists {
			signature
		} else {
			sibling_file_signature(resource.source)
		}
		pipeline.last_current_revalidation_ns = time.sys_mono_now()
		pipeline.current_validation_epoch++
		pipeline.current_resource_invalidated = false
		pipeline.update_retention()
		if pipeline.resident_signature.exists && resource.id.len > 0 && resource.decoded_pixels().len > 0
			&& !pipeline.cache.contains(resource.source) {
			pipeline.cache.put(resource.source, pipeline.resident_signature, resource,
				resource.decoded_pixels().len, image_resource_renderer_bytes(resource))
		}
		pipeline.update_retention()
	}
}

pub fn (mut pipeline ImagePipeline) clear_resident() {
	pipeline.resident_resource = ui2.ImageResource{}
	pipeline.resident_signature = SiblingFileSignature{}
	pipeline.has_ready = false
	pipeline.ready_resource = ui2.ImageResource{}
	pipeline.current_validation_epoch++
	pipeline.current_resource_invalidated = false
	pipeline.update_retention()
}

pub fn (mut pipeline ImagePipeline) take_current_resource_invalidated() bool {
	if !pipeline.current_resource_invalidated {
		return false
	}
	pipeline.current_resource_invalidated = false
	return true
}

fn image_current_validation_worker(path string, epoch u64,
	reader ImageContentSignatureReader, result_ch chan CurrentResourceValidationResult) {
	signature := if voidptr(reader) == unsafe { nil } {
		sibling_file_content_signature(path)
	} else {
		reader(path)
	}
	result_ch <- CurrentResourceValidationResult{
		path:      path
		epoch:     epoch
		signature: signature
	}
}

fn (mut pipeline ImagePipeline) apply_current_resource_validation(result CurrentResourceValidationResult) {
	pipeline.current_validation_in_flight = false
	if result.epoch != pipeline.current_validation_epoch
		|| pipeline.resident_resource.state != .ready
		|| result.path != pipeline.resident_resource.source {
		return
	}
	if !result.signature.exists {
		if pipeline.resident_signature.exists {
			pipeline.resident_signature = result.signature
			pipeline.current_resource_invalidated = true
			pipeline.sync_cache_metrics()
			pipeline.update_retention()
		}
		return
	}
	if pipeline.resident_signature.exists
		&& sibling_file_signature_validates(pipeline.resident_signature, result.signature) {
		if pipeline.cache.contains(result.path) {
			pipeline.cache.revalidate(result.path, result.signature)
		}
		pipeline.resident_signature = result.signature
		pipeline.sync_cache_metrics()
		return
	}
	if pipeline.cache.contains(result.path) {
		pipeline.cache.revalidate(result.path, result.signature)
	}
	pipeline.resident_signature = result.signature
	pipeline.current_resource_invalidated = true
	pipeline.sync_cache_metrics()
	pipeline.update_retention()
}

fn (mut pipeline ImagePipeline) poll_current_resource_validation() {
	select {
		result := <-pipeline.current_validation_ch {
			pipeline.apply_current_resource_validation(result)
		}
		else {
		}
	}
}

fn (mut pipeline ImagePipeline) schedule_current_resource_validation() {
	if pipeline.resident_resource.state != .ready || pipeline.current_validation_in_flight
		|| pipeline.current_resource_invalidated {
		return
	}
	now := time.sys_mono_now()
	if pipeline.last_current_revalidation_ns > 0 && now <= pipeline.last_current_revalidation_ns {
		return
	}
	if pipeline.last_current_revalidation_ns > 0
		&& now - pipeline.last_current_revalidation_ns < pipeline.current_revalidation_interval_ns {
		return
	}
	pipeline.last_current_revalidation_ns = now
	pipeline.current_validation_epoch++
	pipeline.current_validation_in_flight = true
	spawn image_current_validation_worker(pipeline.resident_resource.source,
		pipeline.current_validation_epoch, pipeline.current_validation_reader, pipeline.current_validation_ch)
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

pub fn (mut pipeline ImagePipeline) complete_prefetch_active(resource ui2.ImageResource) bool {
	if !pipeline.prefetch.has_active {
		return false
	}
	result := ImagePipelineResult{
		request:        pipeline.prefetch.active_request
		resource:       resource
		signature:      sibling_file_signature(pipeline.prefetch.active_request.path)
		cpu_bytes:      resource.decoded_pixels().len
		renderer_bytes: image_resource_renderer_bytes(resource)
	}
	mut sent := false
	select {
		pipeline.prefetch.result_ch <- result {
			sent = true
		}
		else {
		}
	}
	return sent
}

pub fn (mut pipeline ImagePipeline) complete_prefetch(generation int, path string,
	resource ui2.ImageResource) bool {
	if !pipeline.prefetch.has_active || pipeline.prefetch.active_request.generation != generation
		|| pipeline.prefetch.active_request.path != path {
		return false
	}
	return pipeline.complete_prefetch_active(resource)
}

pub fn (mut pipeline ImagePipeline) mark_committed(request ImageRequest) {
	if request.generation == pipeline.desired_request.generation && request.path == pipeline.desired_request.path {
		pipeline.metrics.committed++
	}
}

pub fn (mut pipeline ImagePipeline) mark_displayed(request ImageRequest) {
	if request.generation == pipeline.desired_request.generation && request.path == pipeline.desired_request.path {
		pipeline.metrics.displayed++
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
		mut signature := request.signature
		if cached := pipeline.cache.signature(request.path) {
			signature = cached
		}
		accepted << ImagePipelineResult{
			request:        request
			resource:       resource
			signature:      signature
			cpu_bytes:      resource.decoded_pixels().len
			renderer_bytes: image_resource_renderer_bytes(resource)
		}
		pipeline.metrics.accepted++
		if resource.state == .error {
			pipeline.metrics.failed++
		}
	} else {
		pipeline.metrics.rejected++
		pipeline.metrics.skipped++
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
				pipeline.metrics.decode_count += result.decode_count
				if !pipeline.has_active || result.request.generation != pipeline.active_request.generation
					|| result.request.path != pipeline.active_request.path {
					pipeline.metrics.rejected++
					pipeline.metrics.skipped++
					continue
				}
				was_cancelled := pipeline.active_cancelled
				pipeline.has_active = false
				pipeline.active_token = none
				pipeline.active_cancelled = false
				pipeline.metrics.completed++
				mut normalized := result
				if image_result_cancellation_transition(normalized.cancelled, was_cancelled) {
					pipeline.metrics.cancelled++
				} else if normalized.resource.state == .ready {
					current_signature := sibling_file_signature(normalized.request.path)
					if normalized.signature.exists && !sibling_file_identity_matches(normalized.signature, current_signature) {
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
						}
					}
				}
				if pipeline.result_is_current(normalized) {
					if normalized.resource.state == .ready {
						pipeline.resident_resource = normalized.resource
						pipeline.resident_signature = normalized.signature
					}
					accepted << normalized
					pipeline.metrics.accepted++
					if normalized.resource.state == .error {
						pipeline.metrics.failed++
					}
				} else {
					pipeline.metrics.rejected++
					pipeline.metrics.skipped++
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
	mut prefetch_drained := 0
	for prefetch_drained < 4 {
		select {
			result := <-pipeline.prefetch.result_ch {
				prefetch_drained++
				pipeline.prefetch.metrics.decode_count += result.decode_count
				if !pipeline.prefetch.has_active
					|| result.request.generation != pipeline.prefetch.active_request.generation
					|| result.request.path != pipeline.prefetch.active_request.path {
					continue
				}
				was_cancelled := pipeline.prefetch.active_cancelled
				pipeline.prefetch.has_active = false
				pipeline.prefetch.active_token = none
				pipeline.prefetch.active_cancelled = false
				pipeline.prefetch.metrics.completed++
				mut normalized := result
				if image_result_cancellation_transition(normalized.cancelled, was_cancelled) {
					pipeline.prefetch.metrics.cancelled++
				} else if normalized.resource.state == .ready {
					current_signature := sibling_file_signature(normalized.request.path)
					if normalized.signature.exists && !sibling_file_identity_matches(normalized.signature, current_signature) {
						normalized.resource = ui2.error_image_resource('image-resource-${normalized.request.generation}', normalized.request.path,
							'image file changed during decode')
						normalized.signature = current_signature
					}
				}
				context_current := !normalized.cancelled && pipeline.prefetch.context_valid
					&& normalized.request.generation == pipeline.prefetch.generation
					&& normalized.request.path in pipeline.prefetch.neighborhood_paths
				if context_current && normalized.resource.state == .ready {
					if pipeline.cache.put(normalized.request.path, normalized.signature,
						normalized.resource, normalized.cpu_bytes, normalized.renderer_bytes) {
						pipeline.prefetch.metrics.prefetched++
						pipeline.prefetch.last_prefetched_path = normalized.request.path
						pipeline.prefetch.has_last_prefetched = true
					} else {
						pipeline.prefetch.metrics.skipped++
					}
				} else if context_current {
					pipeline.prefetch.metrics.skipped++
				}
				pipeline.update_retention()
				pipeline.pump_prefetch()
			}
			else {
				break
			}
		}
	}
	if pipeline.prefetch.has_queued && !pipeline.prefetch.has_active {
		pipeline.pump_prefetch()
	}
	pipeline.poll_current_resource_validation()
	pipeline.schedule_current_resource_validation()
	pipeline.update_pending_metrics()
	pipeline.sync_cache_metrics()
	return accepted
}
