module main

import os

pub struct BenchmarkSampleSummary {
pub:
	median_ns i64
	p95_ns    i64
}

pub fn summarize_samples(samples []i64) BenchmarkSampleSummary {
	assert samples.len > 0
	mut sorted := samples.clone()
	sorted.sort()
	middle := sorted.len / 2
	median := if sorted.len % 2 == 1 {
		sorted[middle]
	} else {
		(sorted[middle - 1] + sorted[middle]) / 2
	}
	p95_index := (sorted.len * 95 + 99) / 100 - 1
	return BenchmarkSampleSummary{
		median_ns: median
		p95_ns:    sorted[p95_index]
	}
}

pub fn benchmark_checksum(data []u8) u64 {
	mut hash := u64(14695981039346656037)
	for byte in data {
		hash ^= u64(byte)
		hash *= u64(1099511628211)
	}
	return hash
}

pub fn benchmark_checksum_u64(hash u64, value u64) u64 {
	return benchmark_checksum_text(hash, value.str())
}

pub fn benchmark_checksum_text(hash u64, value string) u64 {
	mut result := hash
	for byte in value.bytes() {
		result ^= u64(byte)
		result *= u64(1099511628211)
	}
	return result
}

pub struct BenchmarkBuildInfo {
pub:
	commit       string
	dirty        string
	v_version    string
	compiler     string
	module       string
	compile_flag string
}

pub fn benchmark_build_info() BenchmarkBuildInfo {
	root := benchmark_repository_root()
	commit := benchmark_command_output('git -C "${root}" rev-parse --short=12 HEAD', 'unknown')
	dirty := benchmark_command_output('git -C "${root}" status --porcelain', '')
	dirty_state := if dirty == '' { 'clean' } else { 'dirty' }
	return BenchmarkBuildInfo{
		commit:       commit
		dirty:        dirty_state
		v_version:    benchmark_command_output('v version', 'unavailable')
		compiler:     benchmark_command_output('cc --version', 'unavailable').all_before('\n')
		module:       benchmark_module_version()
		compile_flag: '-d sokol_wayland -d viewer_benchmark'
	}
}

pub struct BenchmarkHardwareInfo {
pub:
	architecture string
	os_name      string
	cpu_model    string
	logical_cpus int
	memory       string
	gpu_driver   string
}

pub fn benchmark_hardware_info() BenchmarkHardwareInfo {
	info := os.uname()
	mut cpu_model := 'unavailable'
	mut logical_cpus := 0
	mut memory := 'unavailable'
	mut gpu_driver := 'unavailable'
	$if linux {
		if cpuinfo := os.read_file('/proc/cpuinfo') {
			for line in cpuinfo.split_into_lines() {
				if line.starts_with('model name') {
					cpu_model = line.all_after(':').trim_space()
					break
				}
			}
		}
		if count := os.read_file('/proc/cpuinfo') {
			for line in count.split_into_lines() {
				if line.starts_with('processor') {
					logical_cpus++
				}
			}
		}
		if meminfo := os.read_file('/proc/meminfo') {
			for line in meminfo.split_into_lines() {
				if line.starts_with('MemTotal:') {
					memory = line.all_after(':').trim_space()
					break
				}
			}
		}
		if entries := os.ls('/sys/class/drm') {
			for entry in entries {
				driver_path := os.join_path('/sys/class/drm', entry + '/device/driver')
				if os.exists(driver_path) {
					gpu_driver = os.file_name(os.real_path(driver_path))
					break
				}
			}
		}
	}
	return BenchmarkHardwareInfo{
		architecture: info.machine
		os_name:      '${info.sysname} ${info.release}'
		cpu_model:    cpu_model
		logical_cpus: logical_cpus
		memory:       memory
		gpu_driver:   gpu_driver
	}
}

fn benchmark_repository_root() string {
	current := os.getwd()
	mut candidate := current
	for _ in 0 .. 8 {
		if os.exists(os.join_path(candidate, 'v.mod')) {
			return candidate
		}
		parent := os.dir(candidate)
		if parent == candidate || parent == '' {
			break
		}
		candidate = parent
	}
	return current
}

fn benchmark_module_version() string {
	$if viewer_benchmark ? {
		return '0.1.0 benchmark'
	}
	return '0.1.0'
}

fn benchmark_command_output(command string, fallback string) string {
	result := os.execute(command)
	if result.exit_code != 0 {
		return fallback
	}
	return result.output.trim_space()
}
