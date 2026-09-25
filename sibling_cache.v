module main

import os
import ui2

pub const default_sibling_cache_budget_bytes = 256 * 1024 * 1024
pub const default_sibling_cache_neighbor_radius = 1

pub fn configured_sibling_cache_budget_bytes() int {
	value := os.getenv('IMAGE_UI_SIBLING_CACHE_BUDGET_BYTES')
	if value.len == 0 {
		return default_sibling_cache_budget_bytes
	}
	parsed := value.int()
	return if parsed < 0 { default_sibling_cache_budget_bytes } else { parsed }
}

pub fn configured_sibling_cache_neighbor_radius() int {
	value := os.getenv('IMAGE_UI_SIBLING_CACHE_NEIGHBOR_RADIUS')
	if value.len == 0 {
		return default_sibling_cache_neighbor_radius
	}
	parsed := value.int()
	return if parsed < 0 { default_sibling_cache_neighbor_radius } else { parsed }
}

pub struct SiblingFileSignature {
pub:
	exists        bool
	size          u64
	modified_unix i64
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
	hits             int
	misses           int
	updates          int
	invalidations    int
	evictions        int
	oversized        int
	resident_entries int
	resident_bytes   int
	peak_bytes       int
	cpu_bytes        int
	renderer_bytes   int
}

pub struct SiblingResourceCache {
pub mut:
	budget_bytes  int
	entries       map[string]SiblingResourceCacheEntry
	protected     map[string]bool
	current_path  string
	next_sequence u64
	metrics       SiblingResourceCacheMetrics
}

pub fn new_sibling_resource_cache(budget_bytes int) SiblingResourceCache {
	return SiblingResourceCache{
		budget_bytes: if budget_bytes < 0 { 0 } else { budget_bytes }
		entries:      map[string]SiblingResourceCacheEntry{}
		protected:    map[string]bool{}
	}
}

pub fn sibling_file_signature(path string) SiblingFileSignature {
	if info := os.stat(path) {
		return SiblingFileSignature{
			exists:        true
			size:          info.size
			modified_unix: info.mtime
		}
	}
	return SiblingFileSignature{}
}

fn (mut cache SiblingResourceCache) remove_path(path string) {
	entry := cache.entries[path] or { return }
	cache.metrics.resident_bytes -= entry.cpu_bytes + entry.renderer_bytes
	cache.metrics.cpu_bytes -= entry.cpu_bytes
	cache.metrics.renderer_bytes -= entry.renderer_bytes
	cache.metrics.resident_entries--
	cache.entries.delete(path)
}

fn (cache &SiblingResourceCache) oldest_candidate(include_protected bool, include_current bool) string {
	mut oldest_path := ''
	mut oldest_sequence := u64(0)
	for path, entry in cache.entries {
		if !include_protected && path in cache.protected {
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
		mut oldest_path := cache.oldest_candidate(false, false)
		if oldest_path == '' {
			oldest_path = cache.oldest_candidate(true, false)
		}
		if oldest_path == '' {
			oldest_path = cache.oldest_candidate(true, true)
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
	cache.current_path = current_path
	cache.protected = map[string]bool{}
	if current_path != '' {
		cache.protected[current_path] = true
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
	if !signature.exists || entry.signature != signature {
		cache.metrics.invalidations++
		cache.remove_path(path)
		cache.metrics.misses++
		return none
	}
	cache.next_sequence++
	cache.entries[path] = SiblingResourceCacheEntry{
		resource:       entry.resource
		signature:      entry.signature
		cpu_bytes:      entry.cpu_bytes
		renderer_bytes: entry.renderer_bytes
		sequence:       cache.next_sequence
	}
	cache.metrics.hits++
	return entry.resource
}

pub fn (cache &SiblingResourceCache) contains(path string) bool {
	return path in cache.entries
}
