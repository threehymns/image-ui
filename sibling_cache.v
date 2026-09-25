module main

import crypto.sha256
import os
import ui2

pub const default_sibling_cache_budget_bytes = 256 * 1024 * 1024
pub const default_sibling_cache_neighborhood_radius = 1

pub fn configured_sibling_cache_budget_bytes() int {
	value := os.getenv('IMAGE_UI_SIBLING_CACHE_BUDGET_BYTES')
	if value.len == 0 {
		return default_sibling_cache_budget_bytes
	}
	parsed := value.int()
	return if parsed < 0 { default_sibling_cache_budget_bytes } else { parsed }
}

pub fn configured_sibling_cache_neighborhood_radius() int {
	value := os.getenv('IMAGE_UI_SIBLING_CACHE_NEIGHBORHOOD_RADIUS')
	if value.len == 0 {
		return default_sibling_cache_neighborhood_radius
	}
	parsed := value.int()
	return if parsed < 0 { default_sibling_cache_neighborhood_radius } else { parsed }
}

pub struct SiblingFileSignature {
pub:
	exists             bool
	size               u64
	modified_unix      i64
	changed_unix       i64
	device             u64
	inode              u64
	links              u64
	content_digest     string
	has_content_digest bool
}

struct SiblingResourceCacheEntry {
	resource       ui2.ImageResource
	signature      SiblingFileSignature
	cpu_bytes      int
	renderer_bytes int
mut:
	sequence u64
}

pub struct SiblingResourceCacheMetrics {
pub mut:
	hits                int
	misses              int
	updates             int
	invalidations       int
	evictions           int
	oversized           int
	content_validations int
	resident_entries    int
	resident_bytes      int
	peak_bytes          int
	cpu_bytes           int
	renderer_bytes      int
}

pub struct SiblingResourceCache {
pub mut:
	budget_bytes  int
	entries       map[string]SiblingResourceCacheEntry
	protected     map[string]bool
	required      map[string]bool
	current_path  string
	next_sequence u64
	metrics       SiblingResourceCacheMetrics
}

pub fn new_sibling_resource_cache(budget_bytes int) SiblingResourceCache {
	return SiblingResourceCache{
		budget_bytes: if budget_bytes < 0 { 0 } else { budget_bytes }
		entries:      map[string]SiblingResourceCacheEntry{}
		protected:    map[string]bool{}
		required:     map[string]bool{}
	}
}

// A content digest reads and hashes the whole file. Large images cost seconds of
// CPU at the portable SHA-256 throughput, so only files within this budget are
// hashed. Larger files rely on stat identity, which already covers ordinary
// rewrites because the signature keeps nanosecond timestamps and inode identity.
pub const sibling_file_digest_budget = 1024 * 1024

pub fn sibling_file_digest(data []u8) string {
	return sha256.sum(data).hex()
}

pub fn sibling_file_signature_from_bytes(path string, data []u8) SiblingFileSignature {
	signature := sibling_file_signature(path)
	if !signature.exists {
		return signature
	}
	if data.len > sibling_file_digest_budget {
		return signature
	}
	return SiblingFileSignature{
		exists:             true
		size:               signature.size
		modified_unix:      signature.modified_unix
		changed_unix:       signature.changed_unix
		device:             signature.device
		inode:              signature.inode
		links:              signature.links
		content_digest:     sibling_file_digest(data)
		has_content_digest: true
	}
}

pub fn sibling_file_content_signature(path string) SiblingFileSignature {
	stat := sibling_file_signature(path)
	if !stat.exists || stat.size > sibling_file_digest_budget {
		return stat
	}
	data := os.read_bytes(path) or { return stat }
	return sibling_file_signature_from_bytes(path, data)
}

pub fn sibling_file_signature(path string) SiblingFileSignature {
	if info := os.stat(path) {
		return SiblingFileSignature{
			exists:        true
			size:          info.size
			modified_unix: info.mtime
			changed_unix:  info.ctime
			device:        info.dev
			inode:         info.inode
			links:         info.nlink
		}
	}
	return SiblingFileSignature{}
}

fn sibling_file_identity_matches(cached SiblingFileSignature, current SiblingFileSignature) bool {
	return cached.exists && current.exists && cached.size == current.size
		&& cached.modified_unix == current.modified_unix && cached.changed_unix == current.changed_unix
		&& cached.device == current.device && cached.inode == current.inode && cached.links == current.links
}

fn sibling_file_signature_matches(cached SiblingFileSignature, current SiblingFileSignature) bool {
	if !sibling_file_identity_matches(cached, current) {
		return false
	}
	if current.has_content_digest {
		return cached.has_content_digest && cached.content_digest == current.content_digest
	}
	return true
}

fn sibling_file_signature_validates(cached SiblingFileSignature, current SiblingFileSignature) bool {
	if !sibling_file_identity_matches(cached, current) {
		return false
	}
	if !cached.has_content_digest {
		return true
	}
	return !current.has_content_digest || cached.content_digest == current.content_digest
}

fn (mut cache SiblingResourceCache) remove_path(path string) {
	entry := cache.entries[path] or { return }
	cache.metrics.resident_bytes -= entry.cpu_bytes + entry.renderer_bytes
	cache.metrics.cpu_bytes -= entry.cpu_bytes
	cache.metrics.renderer_bytes -= entry.renderer_bytes
	cache.metrics.resident_entries--
	cache.entries.delete(path)
}

fn (cache &SiblingResourceCache) oldest_candidate(include_protected bool, include_required bool,
	include_current bool) string {
	mut oldest_path := ''
	mut oldest_sequence := u64(0)
	for path, entry in cache.entries {
		if !include_protected && path in cache.protected {
			continue
		}
		if !include_required && path in cache.required {
			continue
		}
		if !include_current && path == cache.current_path {
			continue
		}
		if oldest_path == '' || entry.sequence < oldest_sequence {
			oldest_path = path
			oldest_sequence = entry.sequence
		}
	}
	return oldest_path
}

fn (mut cache SiblingResourceCache) evict_to_fit() {
	for cache.metrics.resident_bytes > cache.budget_bytes {
		mut oldest_path := cache.oldest_candidate(false, false, false)
		if oldest_path == '' {
			oldest_path = cache.oldest_candidate(true, false, false)
		}
		if oldest_path == '' {
			oldest_path = cache.oldest_candidate(true, true, false)
		}
		if oldest_path == '' {
			oldest_path = cache.oldest_candidate(true, true, true)
		}
		if oldest_path == '' {
			return
		}
		cache.remove_path(oldest_path)
		cache.metrics.evictions++
	}
}

pub fn (mut cache SiblingResourceCache) set_budget(budget_bytes int) {
	cache.budget_bytes = if budget_bytes < 0 { 0 } else { budget_bytes }
	cache.evict_to_fit()
}

pub fn (mut cache SiblingResourceCache) set_retention(current_path string, nearby_paths []string) {
	cache.set_requirements(current_path, [current_path], nearby_paths)
}

pub fn (mut cache SiblingResourceCache) set_requirements(current_path string, required_paths []string,
	nearby_paths []string) {
	cache.current_path = current_path
	cache.required = map[string]bool{}
	cache.protected = map[string]bool{}
	if current_path != '' {
		cache.required[current_path] = true
		cache.protected[current_path] = true
	}
	for path in required_paths {
		if path != '' {
			cache.required[path] = true
			cache.protected[path] = true
		}
	}
	for path in nearby_paths {
		if path != '' {
			cache.protected[path] = true
		}
	}
	cache.evict_to_fit()
}

pub fn (mut cache SiblingResourceCache) put(path string, signature SiblingFileSignature, resource ui2.ImageResource, cpu_bytes int, renderer_bytes int) bool {
	if path == '' || !signature.exists || cpu_bytes < 0 || renderer_bytes < 0 {
		return false
	}
	if path in cache.entries {
		cache.metrics.updates++
		cache.remove_path(path)
	}
	total_bytes := cpu_bytes + renderer_bytes
	if total_bytes > cache.budget_bytes {
		cache.metrics.oversized++
		return false
	}
	cache.next_sequence++
	cache.entries[path] = SiblingResourceCacheEntry{
		resource:       resource
		signature:      signature
		cpu_bytes:      cpu_bytes
		renderer_bytes: renderer_bytes
		sequence:       cache.next_sequence
	}
	cache.metrics.resident_entries++
	cache.metrics.resident_bytes += total_bytes
	cache.metrics.cpu_bytes += cpu_bytes
	cache.metrics.renderer_bytes += renderer_bytes
	if cache.metrics.resident_bytes > cache.metrics.peak_bytes {
		cache.metrics.peak_bytes = cache.metrics.resident_bytes
	}
	cache.evict_to_fit()
	return path in cache.entries
}

pub fn (mut cache SiblingResourceCache) get(path string, signature SiblingFileSignature) ?ui2.ImageResource {
	entry := cache.entries[path] or {
		cache.metrics.misses++
		return none
	}
	if !sibling_file_signature_matches(entry.signature, signature) {
		cache.metrics.invalidations++
		cache.remove_path(path)
		cache.metrics.misses++
		return none
	}
	if signature.has_content_digest {
		cache.metrics.content_validations++
	}
	cache.next_sequence++
	cache.entries[path] = SiblingResourceCacheEntry{
		resource:       entry.resource
		signature:      if signature.has_content_digest { signature } else { entry.signature }
		cpu_bytes:      entry.cpu_bytes
		renderer_bytes: entry.renderer_bytes
		sequence:       cache.next_sequence
	}
	cache.metrics.hits++
	return entry.resource
}

pub fn (mut cache SiblingResourceCache) revalidate(path string, signature SiblingFileSignature) bool {
	entry := cache.entries[path] or { return false }
	if entry.signature.has_content_digest && signature.has_content_digest {
		cache.metrics.content_validations++
	}
	if !sibling_file_signature_validates(entry.signature, signature) {
		cache.metrics.invalidations++
		cache.remove_path(path)
		return false
	}
	if signature.has_content_digest {
		cache.entries[path] = SiblingResourceCacheEntry{
			resource:       entry.resource
			signature:      signature
			cpu_bytes:      entry.cpu_bytes
			renderer_bytes: entry.renderer_bytes
			sequence:       entry.sequence
		}
	}
	return true
}

pub fn (mut cache SiblingResourceCache) invalidate(path string) bool {
	if path !in cache.entries {
		return false
	}
	cache.remove_path(path)
	cache.metrics.invalidations++
	return true
}

pub fn (cache &SiblingResourceCache) contains(path string) bool {
	return path in cache.entries
}

pub fn (cache &SiblingResourceCache) signature(path string) ?SiblingFileSignature {
	entry := cache.entries[path] or { return none }
	return entry.signature
}
