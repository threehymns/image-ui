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

pub struct SiblingBatch {
pub:
	items           []string
	is_neighborhood bool
	is_last         bool
}

// is_image_file checks if the path points to a non-hidden file with a supported image extension.
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

// natural_compare_strings compares two strings chunk by chunk.
// Numeric sequences are evaluated numerically; alphabetic sequences are compared case-insensitively.
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

// natural_compare_paths compares two file paths based on their filenames naturally.
pub fn natural_compare_paths(a &string, b &string) int {
	fa := os.file_name(*a)
	fb := os.file_name(*b)
	res := natural_compare_strings(fa, fb)
	if res != 0 {
		return res
	}
	return natural_compare_strings(*a, *b)
}

// natural_sort sorts a list of file paths or strings in place using natural alphanumeric comparison.
pub fn natural_sort(mut items []string) {
	items.sort_with_compare(natural_compare_paths)
}

// find_first_image_in_dir locates the first supported image file in a directory in natural sort order.
pub fn find_first_image_in_dir(dir_path string) ?string {
	if !os.is_dir(dir_path) {
		return none
	}
	entries := os.ls(dir_path) or { return none }
	mut image_files := []string{}
	for entry in entries {
		full_path := os.join_path(dir_path, entry)
		if !os.is_dir(full_path) && is_image_file(full_path) {
			image_files << full_path
		}
	}
	if image_files.len == 0 {
		return none
	}
	natural_sort(mut image_files)
	return image_files[0]
}

// scan_directory_siblings traverses dir_path, identifies supported sibling images,
// sorts them naturally, and streams the immediate ±50 neighborhood first over ch,
// followed by remaining entries in progressive batches.
pub fn scan_directory_siblings(dir_path string, target_path string, ch chan SiblingBatch) {
	if !os.is_dir(dir_path) {
		ch <- SiblingBatch{
			items:           []
			is_neighborhood: true
			is_last:         true
		}
		return
	}

	entries := os.ls(dir_path) or {
		ch <- SiblingBatch{
			items:           []
			is_neighborhood: true
			is_last:         true
		}
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
		ch <- SiblingBatch{
			items:           []
			is_neighborhood: true
			is_last:         true
		}
		return
	}

	natural_sort(mut image_files)

	mut target_idx := 0
	target_clean := os.real_path(target_path)
	for i, p in image_files {
		if p == target_path || os.real_path(p) == target_clean {
			target_idx = i
			break
		}
	}

	// Immediate neighborhood: closest ±50 files around target
	neigh_start := math.max(0, target_idx - 50)
	neigh_end := math.min(image_files.len, target_idx + 51)
	neighborhood := image_files[neigh_start..neigh_end].clone()

	if image_files.len <= neighborhood.len {
		ch <- SiblingBatch{
			items:           neighborhood
			is_neighborhood: true
			is_last:         true
		}
		return
	}

	// 1. Stream prioritized neighborhood batch first
	ch <- SiblingBatch{
		items:           neighborhood
		is_neighborhood: true
		is_last:         false
	}

	// 2. Stream succeeding files in progressive batches
	batch_size := scanner_batch_size
	for i := neigh_end; i < image_files.len; i += batch_size {
		chunk_end := math.min(image_files.len, i + batch_size)
		is_last := (chunk_end == image_files.len) && (neigh_start == 0)
		ch <- SiblingBatch{
			items:           image_files[i..chunk_end].clone()
			is_neighborhood: false
			is_last:         is_last
		}
	}

	// 3. Stream preceding files in progressive batches
	for i := neigh_start; i > 0; {
		chunk_start := math.max(0, i - batch_size)
		is_last := (chunk_start == 0)
		ch <- SiblingBatch{
			items:           image_files[chunk_start..i].clone()
			is_neighborhood: false
			is_last:         is_last
		}
		i = chunk_start
	}
}
