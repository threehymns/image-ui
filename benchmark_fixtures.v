module main

import os

pub const benchmark_large_width = 3840
pub const benchmark_large_height = 2160
pub const benchmark_sibling_count = 128

pub struct BenchmarkFixtures {
pub:
	root                   string
	alpha                  string
	opaque                 string
	large_4k               string
	large_sibling_previous string
	large_sibling_next     string
	siblings               string
	sibling_count          int
}

pub fn (fixtures BenchmarkFixtures) sibling(index int) string {
	return os.join_path(fixtures.siblings, 'sibling-${index:03d}.bmp')
}

pub fn generate_benchmark_fixtures(root string, count int) !BenchmarkFixtures {
	if count < 2 {
		return error('benchmark fixture set requires at least two Siblings')
	}
	os.mkdir_all(root) or { return err }
	siblings := os.join_path(root, 'siblings')
	os.mkdir_all(siblings) or { return err }
	if entries := os.ls(siblings) {
		for entry in entries {
			if entry.starts_with('sibling-') && entry.ends_with('.bmp') {
				os.rm(os.join_path(siblings, entry)) or { return err }
			}
		}
	}

	alpha := os.join_path(root, 'alpha.tga')
	opaque := os.join_path(root, 'opaque.bmp')
	large := os.join_path(root, 'large-4k.bmp')
	large_previous := os.join_path(root, 'large-4k-previous.bmp')
	large_next := os.join_path(root, 'large-4k_next.bmp')
	os.write_bytes(alpha, encode_alpha_tga(64, 64)) or { return err }
	os.write_bytes(opaque, encode_opaque_bmp(96, 64, 17)) or { return err }
	os.write_bytes(large, encode_opaque_bmp(benchmark_large_width, benchmark_large_height, 31)) or {
		return err
	}
	for path in [large_previous, large_next] {
		if os.exists(path) {
			os.rm(path) or { return err }
		}
		os.link(large, path) or {
			data := os.read_bytes(large) or { return err }
			os.write_bytes(path, data) or { return err }
		}
	}
	for index in 0 .. count {
		path := os.join_path(siblings, 'sibling-${index:03d}.bmp')
		os.link(opaque, path) or {
			data := os.read_bytes(opaque) or { return err }
			os.write_bytes(path, data) or { return err }
		}
	}
	return BenchmarkFixtures{
		root:                   root
		alpha:                  alpha
		opaque:                 opaque
		large_4k:               large
		large_sibling_previous: large_previous
		large_sibling_next:     large_next
		siblings:               siblings
		sibling_count:          count
	}
}

fn fixture_put_u16_le(mut data []u8, offset int, value int) {
	data[offset] = u8(value & 0xff)
	data[offset + 1] = u8((value >> 8) & 0xff)
}

fn fixture_put_u32_le(mut data []u8, offset int, value int) {
	data[offset] = u8(value & 0xff)
	data[offset + 1] = u8((value >> 8) & 0xff)
	data[offset + 2] = u8((value >> 16) & 0xff)
	data[offset + 3] = u8((value >> 24) & 0xff)
}

fn encode_opaque_bmp(width int, height int, seed int) []u8 {
	row_size := ((width * 3 + 3) / 4) * 4
	pixel_bytes := row_size * height
	mut data := []u8{len: 54 + pixel_bytes}
	data[0] = `B`
	data[1] = `M`
	fixture_put_u32_le(mut data, 2, data.len)
	fixture_put_u32_le(mut data, 10, 54)
	fixture_put_u32_le(mut data, 14, 40)
	fixture_put_u32_le(mut data, 18, width)
	fixture_put_u32_le(mut data, 22, height)
	fixture_put_u16_le(mut data, 26, 1)
	fixture_put_u16_le(mut data, 28, 24)
	fixture_put_u32_le(mut data, 34, pixel_bytes)
	mut offset := 54
	for row in 0 .. height {
		y := height - row - 1
		for x in 0 .. width {
			data[offset] = u8((x * 13 + y * 7 + seed) & 0xff)
			data[offset + 1] = u8((x * 5 + y * 17 + seed * 3) & 0xff)
			data[offset + 2] = u8((x * 19 + y * 11 + seed * 7) & 0xff)
			offset += 3
		}
		offset += row_size - width * 3
	}
	return data
}

fn encode_alpha_tga(width int, height int) []u8 {
	mut data := []u8{len: 18 + width * height * 4}
	data[2] = 2
	fixture_put_u16_le(mut data, 12, width)
	fixture_put_u16_le(mut data, 14, height)
	data[16] = 32
	data[17] = 0x28
	mut offset := 18
	for y in 0 .. height {
		for x in 0 .. width {
			quadrant := (x / 8 + y / 8) % 4
			data[offset] = u8((x * 11 + y * 3) & 0xff)
			data[offset + 1] = u8((x * 5 + y * 13) & 0xff)
			data[offset + 2] = u8((x * 17 + y * 7) & 0xff)
			data[offset + 3] = u8(quadrant * 85)
			offset += 4
		}
	}
	return data
}
