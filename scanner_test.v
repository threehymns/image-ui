module main

import os
import time

fn test_natural_compare_strings() {
	assert natural_compare_strings('img1.png', 'img2.png') < 0
	assert natural_compare_strings('img2.png', 'img10.png') < 0
	assert natural_compare_strings('img10.png', 'img2.png') > 0
	assert natural_compare_strings('img1.png', 'img1.png') == 0
	assert natural_compare_strings('a.png', 'b.png') < 0
	assert natural_compare_strings('A.png', 'b.png') < 0
	assert natural_compare_strings('a.png', 'B.png') < 0
	assert natural_compare_strings('img2.png', 'img02.png') != 0
	assert natural_compare_strings('v1.2.3', 'v1.10.0') < 0
	assert natural_compare_strings('photo_100_a', 'photo_100_b') < 0
}

fn test_natural_sort() {
	mut list := ['img10.png', 'img1.png', 'img2.png', 'img100.png', 'img20.png', 'a.png', 'B.png']
	natural_sort(mut list)
	assert list == ['a.png', 'B.png', 'img1.png', 'img2.png', 'img10.png', 'img20.png', 'img100.png']
}

fn test_is_image_file() {
	assert is_image_file('/path/to/photo.png') == true
	assert is_image_file('sample.jpg') == true
	assert is_image_file('sample.JPEG') == true
	assert is_image_file('sample.BMP') == true
	assert is_image_file('sample.webp') == true
	assert is_image_file('sample.gif') == true
	assert is_image_file('sample.tga') == true
	assert is_image_file('sample.hdr') == true

	// Hidden files / dotfiles must be ignored
	assert is_image_file('.hidden.png') == false
	assert is_image_file('/home/user/.photo.jpg') == false

	// Non-image extensions must be rejected
	assert is_image_file('document.pdf') == false
	assert is_image_file('code.v') == false
	assert is_image_file('notes.txt') == false
	assert is_image_file('archive.tar.gz') == false
}

fn test_find_first_image_in_dir() {
	tmp_dir := os.join_path(os.temp_dir(), 'test_find_first_${time.ticks()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	// Create files out of order
	os.write_file(os.join_path(tmp_dir, 'img10.png'), 'fake') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'img2.png'), 'fake') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'img1.png'), 'fake') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'notes.txt'), 'fake') or { panic(err) }

	first := find_first_image_in_dir(tmp_dir) or { panic('Expected image') }
	assert os.file_name(first) == 'img1.png'
}

fn test_scan_directory_siblings_streaming() {
	tmp_dir := os.join_path(os.temp_dir(), 'test_scan_siblings_${time.ticks()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	// Create 120 image files
	mut expected_files := []string{}
	for i := 1; i <= 120; i++ {
		filename := 'pic${i}.png'
		path := os.join_path(tmp_dir, filename)
		os.write_file(path, 'fake') or { panic(err) }
		expected_files << path
	}
	natural_sort(mut expected_files)

	// Pick target file in the middle (pic60.png)
	target := os.join_path(tmp_dir, 'pic60.png')

	ch := chan SiblingBatch{cap: 32}
	spawn scan_directory_siblings(tmp_dir, target, ch)

	mut batches := []SiblingBatch{}
	mut all_streamed := []string{}
	mut last_batch_seen := false

	for !last_batch_seen {
		select {
			batch := <-ch {
				batches << batch
				for it in batch.items {
					if it !in all_streamed {
						all_streamed << it
					}
				}
				if batch.is_last {
					last_batch_seen = true
				}
			}
			else {
				time.sleep(1 * time.millisecond)
			}
		}
	}

	// Verify prioritized neighborhood batch came first
	assert batches.len >= 2
	first_batch := batches[0]
	assert first_batch.is_neighborhood == true
	assert first_batch.is_last == false
	// Neighborhood of target pic60 (at index 59) should contain ±50 files (101 items)
	assert first_batch.items.len == 101

	// Verify target is present in neighborhood
	assert target in first_batch.items

	// Verify all 120 files were delivered
	assert all_streamed.len == 120
	natural_sort(mut all_streamed)
	assert all_streamed == expected_files

	// Verify final batch marked is_last == true
	last_batch := batches[batches.len - 1]
	assert last_batch.is_last == true
}
