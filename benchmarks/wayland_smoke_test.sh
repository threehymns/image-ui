#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
smoke_script=$script_dir/wayland_smoke.sh

without_wayland() {
	env -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR \
		-u IMAGE_UI_BENCHMARK_TRACE_WAIT_ATTEMPTS \
		-u IMAGE_UI_BENCHMARK_TRACE_WAIT_DELAY \
		-u IMAGE_UI_BENCHMARK_WINDOW_WAIT_ATTEMPTS \
		-u IMAGE_UI_BENCHMARK_WINDOW_WAIT_DELAY \
		"$@"
}

default_output=$(without_wayland "$smoke_script" 2>&1)
if [[ $default_output != *'trace wait 400 attempts x 0.025s'* || $default_output != *'window wait 400 attempts x 0.025s'* ]]; then
	printf 'default smoke wait configuration was not reported\n' >&2
	exit 1
fi

custom_output=$(without_wayland IMAGE_UI_BENCHMARK_TRACE_WAIT_ATTEMPTS=401 IMAGE_UI_BENCHMARK_TRACE_WAIT_DELAY=0.05 "$smoke_script" 2>&1)
if [[ $custom_output != *'trace wait 401 attempts x 0.05s'* ]]; then
	printf 'custom smoke wait configuration was not reported\n' >&2
	exit 1
fi

if invalid_output=$(without_wayland IMAGE_UI_BENCHMARK_TRACE_WAIT_ATTEMPTS=0 "$smoke_script" 2>&1); then
	printf 'invalid smoke wait configuration was accepted\n' >&2
	exit 1
fi
if [[ $invalid_output != *'IMAGE_UI_BENCHMARK_TRACE_WAIT_ATTEMPTS must be a positive integer'* ]]; then
	printf 'invalid smoke wait configuration was not diagnosed\n' >&2
	exit 1
fi
