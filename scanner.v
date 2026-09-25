module main

import os
import math

pub const supported_image_extensions = [
	'.png',
	'.jpg',
	'.jpeg',
	'.bmp',
	'.gif',
	'.webp',
	'.tga',
	'.ppm',
	'.pgm',
	'.hdr',
	'.pic',
]

pub const scanner_batch_size = 50
pub const scanner_neighborhood_radius = 50

pub struct SiblingBatch {
pub:
	items            []string
	is_neighborhood  bool
	is_last          bool
	generation       int
	is_first_content bool
}

pub type SiblingDirectorySource = fn (string) ![]string
pub type SiblingPathSorter = fn (mut []string)

pub fn is_image_file(path string) bool {
	filename := os.file_name(path)
	if filename == '' || filename.starts_with('.') {
		return false
	}
	ext := os.file_ext(path).to_lower()
	return ext in supported_image_extensions
}

fn is_digit(c u8) bool {
	return c >= `0` && c <= `9`
}

pub fn natural_compare_strings(sa string, sb string) int {
	mut ia := 0
	mut ib := 0
	la := sa.len
	lb := sb.len
	for ia < la && ib < lb {
		ca := sa[ia]
		cb := sb[ib]
		if is_digit(ca) && is_digit(cb) {
			mut full_end_a := ia
			for full_end_a < la && is_digit(sa[full_end_a]) {
				full_end_a++
			}
			mut start_a := ia
			for start_a < full_end_a && sa[start_a] == `0` {
				start_a++
			}
			mut full_end_b := ib
			for full_end_b < lb && is_digit(sb[full_end_b]) {
				full_end_b++
			}
			mut start_b := ib
			for start_b < full_end_b && sb[start_b] == `0` {
				start_b++
			}
			num_len_a := full_end_a - start_a
			num_len_b := full_end_b - start_b
			if num_len_a != num_len_b {
				return if num_len_a < num_len_b { -1 } else { 1 }
			}
			for k := 0; k < num_len_a; k++ {
				da := sa[start_a + k]
				db := sb[start_b + k]
				if da != db {
					return if da < db { -1 } else { 1 }
				}
			}
			zeros_a := start_a - ia
			zeros_b := start_b - ib
			if zeros_a != zeros_b {
				return if zeros_a < zeros_b { -1 } else { 1 }
			}
			ia = full_end_a
			ib = full_end_b
		} else {
			mut la_c := ca
			if la_c >= `A` && la_c <= `Z` {
				la_c += 32
			}
			mut lb_c := cb
			if lb_c >= `A` && lb_c <= `Z` {
				lb_c += 32
			}
			if la_c != lb_c {
				return if la_c < lb_c { -1 } else { 1 }
			}
			ia++
			ib++
		}
	}
	if ia < la {
		return 1
	}
	if ib < lb {
		return -1
	}
	if sa != sb {
		return if sa < sb { -1 } else { 1 }
	}
	return 0
}

pub fn natural_compare_paths(a &string, b &string) int {
	fa := os.file_name(*a)
	fb := os.file_name(*b)
	res := natural_compare_strings(fa, fb)
	if res != 0 {
		return res
	}
	return natural_compare_strings(*a, *b)
}

pub fn natural_sort(mut items []string) {
	items.sort_with_compare(natural_compare_paths)
}

fn first_image_path(image_files []string) ?string {
	if image_files.len == 0 {
		return none
	}
	mut first := image_files[0]
	for i in 1 .. image_files.len {
		candidate := image_files[i]
		if natural_compare_paths(candidate, first) < 0 {
			first = candidate
		}
	}
	return first
}

fn target_index(image_files []string, target_path string) int {
	if target_path == '' {
		return -1
	}
	target_name := os.file_name(target_path)
	target_clean := os.real_path(target_path)
	for i, path in image_files {
		if path == target_path {
			return i
		}
		if target_name != '' && os.file_name(path) == target_name && os.real_path(path) == target_clean {
			return i
		}
	}
	return -1
}

pub fn find_first_image_in_dir(dir_path string) ?string {
	if !os.is_dir(dir_path) {
		return none
	}
	entries := os.ls(dir_path) or { return none }
	mut first := ''
	for entry in entries {
		full_path := os.join_path(dir_path, entry)
		if !os.is_dir(full_path) && is_image_file(full_path) {
			if first == '' || natural_compare_paths(full_path, first) < 0 {
				first = full_path
			}
		}
	}
	if first == '' {
		return none
	}
	return first
}

fn send_scan_batch(ch chan SiblingBatch, cancel chan bool, batch SiblingBatch) bool {
	select {
		ch <- batch {
			return true
		}
		<-cancel {
			return false
		}
	}
	return false
}

fn keep_largest_before(mut paths []string, candidate string, limit int) []string {
	if limit <= 0 {
		return paths
	}
	if paths.len < limit {
		paths << candidate
		return paths
	}
	mut largest := 0
	for index in 1 .. paths.len {
		if natural_compare_paths(paths[index], paths[largest]) > 0 {
			largest = index
		}
	}
	if natural_compare_paths(candidate, paths[largest]) > 0 {
		paths[largest] = candidate
	}
	return paths
}

fn keep_smallest_after(mut paths []string, candidate string, limit int) []string {
	if limit <= 0 {
		return paths
	}
	if paths.len < limit {
		paths << candidate
		return paths
	}
	mut smallest := 0
	for index in 1 .. paths.len {
		if natural_compare_paths(paths[index], paths[smallest]) < 0 {
			smallest = index
		}
	}
	if natural_compare_paths(candidate, paths[smallest]) < 0 {
		paths[smallest] = candidate
	}
	return paths
}

fn sibling_neighborhood_paths(image_files []string, target_path string, radius int) []string {
	if image_files.len == 0 {
		return []
	}
	mut resolved := target_path
	index := target_index(image_files, target_path)
	if index >= 0 {
		resolved = image_files[index]
	} else {
		resolved = first_image_path(image_files) or { return [] }
	}
	mut before := []string{}
	mut after := []string{}
	for path in image_files {
		if path == resolved {
			continue
		}
		comparison := natural_compare_paths(path, resolved)
		if comparison < 0 {
			before = keep_largest_before(mut before, path, radius)
		} else if comparison > 0 {
			after = keep_smallest_after(mut after, path, radius)
		}
	}
	natural_sort(mut before)
	natural_sort(mut after)
	mut result := before.clone()
	result << resolved
	result << after
	return result
}

fn default_sibling_directory_source(path string) ![]string {
	return os.ls(path)
}

fn scan_directory_siblings_with_source_and_sorter(dir_path string, target_path string,
	generation int, ch chan SiblingBatch, cancel chan bool, source SiblingDirectorySource,
	sorter SiblingPathSorter) {
	select {
		<-cancel {
			return
		}
		else {
		}
	}
	if !os.is_dir(dir_path) {
		send_scan_batch(ch, cancel, SiblingBatch{
			items:            []
			is_neighborhood:  true
			is_last:          true
			generation:       generation
			is_first_content: false
		})
		return
	}
	direct_target := target_path != '' && os.exists(target_path) && is_image_file(target_path)
		&& !os.is_dir(target_path)
	if direct_target {
		if !send_scan_batch(ch, cancel, SiblingBatch{
			items:            [target_path]
			is_neighborhood:  false
			is_last:          false
			generation:       generation
			is_first_content: true
		}) {
			return
		}
	}
	entries := source(dir_path) or {
		send_scan_batch(ch, cancel, SiblingBatch{
			items:            []
			is_neighborhood:  true
			is_last:          true
			generation:       generation
			is_first_content: false
		})
		return
	}
	mut image_files := []string{}
	for entry in entries {
		full_path := os.join_path(dir_path, entry)
		if !os.is_dir(full_path) && is_image_file(full_path) {
			image_files << full_path
		}
	}
	if image_files.len == 0 {
		send_scan_batch(ch, cancel, SiblingBatch{
			items:            []
			is_neighborhood:  true
			is_last:          true
			generation:       generation
			is_first_content: false
		})
		return
	}
	resolved_target := if direct_target {
		target_path
	} else {
		first_image_path(image_files) or { return }
	}
	if !direct_target {
		if !send_scan_batch(ch, cancel, SiblingBatch{
			items:            [resolved_target]
			is_neighborhood:  false
			is_last:          false
			generation:       generation
			is_first_content: true
		}) {
			return
		}
	}
	neighborhood_paths := sibling_neighborhood_paths(image_files, resolved_target, scanner_neighborhood_radius)
	if !send_scan_batch(ch, cancel, SiblingBatch{
		items:            neighborhood_paths
		is_neighborhood:  true
		is_last:          false
		generation:       generation
		is_first_content: direct_target
	}) {
		return
	}
	mut sent := map[string]bool{}
	for path in neighborhood_paths {
		sent[path] = true
	}
	sorter(mut image_files)
	mut remaining := []string{}
	for path in image_files {
		if path !in sent {
			remaining << path
		}
	}
	for start := 0; start < remaining.len; start += scanner_batch_size {
		end := math.min(remaining.len, start + scanner_batch_size)
		if !send_scan_batch(ch, cancel, SiblingBatch{
			items:            remaining[start..end].clone()
			is_neighborhood:  false
			is_last:          end == remaining.len
			generation:       generation
			is_first_content: false
		}) {
			return
		}
	}
	if remaining.len == 0 {
		send_scan_batch(ch, cancel, SiblingBatch{
			items:            []
			is_neighborhood:  false
			is_last:          true
			generation:       generation
			is_first_content: false
		})
	}
}

fn scan_directory_siblings_with_generation_and_cancel(dir_path string, target_path string,
	generation int, ch chan SiblingBatch, cancel chan bool) {
	scan_directory_siblings_with_source_and_sorter(dir_path, target_path, generation, ch, cancel,
		default_sibling_directory_source, natural_sort)
}

fn scan_directory_siblings_with_generation(dir_path string, target_path string, generation int,
	ch chan SiblingBatch) {
	cancel := chan bool{}
	scan_directory_siblings_with_generation_and_cancel(dir_path, target_path, generation, ch, cancel)
}

pub fn scan_directory_siblings(dir_path string, target_path string, ch chan SiblingBatch) {
	scan_directory_siblings_with_generation(dir_path, target_path, 0, ch)
}
