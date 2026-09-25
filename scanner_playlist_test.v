module main

import os
import time

const scanner_playlist_entry_count = 20000
const scanner_playlist_target_index = scanner_playlist_entry_count / 2

__global scanner_playlist_release = chan bool{}
__global scanner_playlist_sort_started = chan bool{cap: 1}
__global scanner_playlist_entries = []string{}

fn scanner_playlist_source(_ string) ![]string {
	return scanner_playlist_entries.clone()
}

fn scanner_playlist_gated_sort(mut paths []string) {
	scanner_playlist_sort_started <- true
	_ = <-scanner_playlist_release
	natural_sort(mut paths)
}

fn scanner_playlist_names() []string {
	mut names := []string{cap: scanner_playlist_entry_count}
	for index in 1 .. scanner_playlist_entry_count + 1 {
		names << 'pic${index}.png'
	}
	return names
}

fn scanner_playlist_expected(root string) []string {
	mut expected := []string{cap: scanner_playlist_entry_count}
	for name in scanner_playlist_names() {
		expected << os.join_path(root, name)
	}
	natural_sort(mut expected)
	return expected
}

fn scanner_playlist_target(root string) string {
	return os.join_path(root, 'pic${scanner_playlist_target_index}.png')
}

fn scanner_playlist_root(prefix string) string {
	root := os.join_path(os.temp_dir(), '${prefix}_${time.ticks()}')
	os.mkdir_all(root) or { panic(err) }
	return root
}

fn scanner_playlist_prepare(root string) []string {
	scanner_playlist_entries = scanner_playlist_names()
	target := scanner_playlist_target(root)
	os.write_file(target, 'fixture') or { panic(err) }
	return scanner_playlist_expected(root)
}

fn scanner_playlist_next_batch(ch chan SiblingBatch) SiblingBatch {
	select {
		batch := <-ch {
			return batch
		}
		10 * time.second {
			panic('scanner playlist batch timeout')
		}
	}
	return SiblingBatch{}
}

fn scanner_playlist_assert_no_trailing_batch(ch chan SiblingBatch) {
	select {
		extra := <-ch {
			panic('unexpected trailing scanner batch with ${extra.items.len} items')
		}
		else {
		}
	}
}

fn test_scanner_20k_delivers_first_content_and_neighborhood_before_full_sort() {
	root := scanner_playlist_root('image-ui-scanner-20k-sort')
	defer {
		os.rmdir_all(root) or {}
	}
	expected := scanner_playlist_prepare(root)
	target := scanner_playlist_target(root)
	scanner_playlist_release = chan bool{}
	scanner_playlist_sort_started = chan bool{cap: 1}
	ch := chan SiblingBatch{}
	cancel := chan bool{}
	spawn scan_directory_siblings_with_source_and_sorter(root, target, 31, ch, cancel,
		scanner_playlist_source, scanner_playlist_gated_sort)

	first := scanner_playlist_next_batch(ch)
	assert first.is_first_content
	assert first.is_last == false
	assert first.items == [target]

	neighborhood := scanner_playlist_next_batch(ch)
	assert neighborhood.is_neighborhood
	assert neighborhood.is_last == false
	assert neighborhood.items.len == scanner_neighborhood_radius * 2 + 1
	assert target in neighborhood.items

	select {
		<-scanner_playlist_sort_started {
		}
		5 * time.second {
			panic('scanner sort did not start')
		}
	}

	scanner_playlist_release.close()
	snapshot := scanner_playlist_next_batch(ch)
	assert snapshot.generation == 31
	assert snapshot.is_last
	assert snapshot.is_neighborhood == false
	assert snapshot.is_playlist_snapshot
	assert snapshot.items.len == scanner_playlist_entry_count
	assert snapshot.items == expected
	scanner_playlist_assert_no_trailing_batch(ch)
}

fn test_app_integrates_20k_scanner_playlist_snapshot() {
	root := scanner_playlist_root('image-ui-scanner-20k-app')
	defer {
		os.rmdir_all(root) or {}
	}
	expected := scanner_playlist_prepare(root)
	target := scanner_playlist_target(root)

	mut app := new_app()
	app.open_path(target)
	generation := app.scan_generation
	ch := chan SiblingBatch{cap: 8}
	spawn scan_directory_siblings_with_source_and_sorter(root, target, generation, ch, chan bool{},
		scanner_playlist_source, natural_sort)

	mut batches := 0
	mut snapshots := 0
	for {
		batch := scanner_playlist_next_batch(ch)
		batches++
		if batch.is_playlist_snapshot {
			snapshots++
		}
		app.integrate_batch(batch)
		if batch.is_last {
			break
		}
	}

	assert batches == 3
	assert snapshots == 1
	assert app.playlist.len == scanner_playlist_entry_count
	assert app.playlist == expected
	assert app.active_sibling_path() == target
	assert app.active_index == scanner_playlist_target_index - 1
	assert app.scan_complete
	assert app.is_scanning == false
	assert app.has_first_content
}

fn test_app_rejects_stale_20k_playlist_snapshot_generation() {
	root := scanner_playlist_root('image-ui-scanner-20k-stale')
	defer {
		os.rmdir_all(root) or {}
	}
	expected := scanner_playlist_prepare(root)
	target := scanner_playlist_target(root)

	mut app := new_app()
	app.open_path(target)
	app.begin_scan(app.scan_generation)
	app.integrate_batch(SiblingBatch{
		items:                expected
		is_last:              true
		generation:           app.scan_generation - 1
		is_playlist_snapshot: true
	})

	assert app.playlist == [target]
	assert app.active_sibling_path() == target
	assert app.is_scanning
	assert app.scan_complete == false
}

fn test_app_playlist_snapshot_replaces_provisional_playlist_without_merge() {
	root := scanner_playlist_root('image-ui-scanner-20k-replace')
	defer {
		os.rmdir_all(root) or {}
	}
	expected := scanner_playlist_prepare(root)
	target := scanner_playlist_target(root)

	mut app := new_app()
	app.open_path(target)
	generation := app.scan_generation
	app.integrate_batch(SiblingBatch{
		items:            [target]
		is_first_content: true
		generation:       generation
	})
	mut provisional := []string{cap: scanner_neighborhood_radius * 2 + 1}
	for offset in -scanner_neighborhood_radius .. scanner_neighborhood_radius + 1 {
		provisional << os.join_path(root, 'pic${scanner_playlist_target_index + offset}.png')
	}
	app.integrate_batch(SiblingBatch{
		items:           provisional.clone()
		is_neighborhood: true
		generation:      generation
	})
	assert app.playlist.len == scanner_neighborhood_radius * 2 + 1
	assert app.active_index == scanner_neighborhood_radius

	app.integrate_batch(SiblingBatch{
		items:                expected
		is_last:              true
		generation:           generation
		is_playlist_snapshot: true
	})

	assert app.playlist.len == scanner_playlist_entry_count
	assert app.playlist == expected
	assert app.active_sibling_path() == target
	assert app.active_index == scanner_playlist_target_index - 1
	assert app.target_path == target
	assert app.scan_complete
}

fn test_poll_scanner_budget_bounds_batches_per_frame() {
	mut app := &ViewerApp{
		core: new_app()
	}
	app.core.open_path('/photos/budget.png')
	app.core.begin_scan(app.core.scan_generation)
	queued := scanner_poll_max_batches + 5
	app.scanner_ch = chan SiblingBatch{cap: queued}
	app.has_scanner_ch = true
	for index in 0 .. queued {
		app.scanner_ch <- SiblingBatch{
			items:      ['/photos/budget-${index}.png']
			generation: app.core.scan_generation
		}
	}

	app.poll_scanner()

	assert app.core.sibling_count() == 1 + scanner_poll_max_batches
	assert '/photos/budget-${scanner_poll_max_batches}.png' !in app.core.playlist
	assert app.has_scanner_ch
	mut remaining := 0
	for {
		select {
			<-app.scanner_ch {
				remaining++
			}
			else {
				break
			}
		}
	}
	assert remaining == queued - scanner_poll_max_batches
	assert scanner_poll_allows_batch(0, 0, scanner_poll_budget_ns * 10)
	assert scanner_poll_allows_batch(scanner_poll_max_batches - 1, 0, 0)
	assert !scanner_poll_allows_batch(scanner_poll_max_batches, 0, 0)
	assert !scanner_poll_allows_batch(1, 0, scanner_poll_budget_ns)
}
