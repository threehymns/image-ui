module main

import os
import time

fn next_viewer_scan_batch(ch chan SiblingBatch) SiblingBatch {
	select {
		batch := <-ch {
			return batch
		}
		5 * time.second {
			panic('scanner batch timeout')
		}
	}
	return SiblingBatch{}
}

fn test_viewer_directory_launch_defers_selection() {
	tmp_dir := os.join_path(os.temp_dir(), 'test_viewer_dir_${time.ticks()}')
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	for name in ['img2.png', 'img1.png'] {
		os.write_file(os.join_path(tmp_dir, name), 'data') or { panic(err) }
	}

	mut viewer := ViewerApp{
		core: new_app()
	}
	viewer.core.open_path(tmp_dir)
	viewer.load_image_internal(tmp_dir, true, true)

	assert viewer.has_scanner_ch == true
	assert viewer.core.playlist.len == 0
	assert viewer.core.target_path == tmp_dir

	first := next_viewer_scan_batch(viewer.scanner_ch)
	assert first.is_first_content == true
	assert first.items == [os.join_path(tmp_dir, 'img1.png')]

	mut current := first
	for !current.is_last {
		current = next_viewer_scan_batch(viewer.scanner_ch)
	}
}
