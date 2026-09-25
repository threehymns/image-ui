#!/usr/bin/env bash
set -euo pipefail

trace_wait_attempts=${IMAGE_UI_BENCHMARK_TRACE_WAIT_ATTEMPTS:-400}
trace_wait_delay=${IMAGE_UI_BENCHMARK_TRACE_WAIT_DELAY:-0.025}
window_wait_attempts=${IMAGE_UI_BENCHMARK_WINDOW_WAIT_ATTEMPTS:-400}
window_wait_delay=${IMAGE_UI_BENCHMARK_WINDOW_WAIT_DELAY:-0.025}

validate_wait_attempts() {
	local name=$1
	local value=$2
	if [[ ! $value =~ ^[1-9][0-9]*$ ]]; then
		printf 'Wayland smoke failed: %s must be a positive integer (got %s)\n' "$name" "$value" >&2
		return 1
	fi
}

validate_wait_delay() {
	local name=$1
	local value=$2
	if [[ ! $value =~ ^[0-9]+([.][0-9]+)?$ ]]; then
		printf 'Wayland smoke failed: %s must be seconds (got %s)\n' "$name" "$value" >&2
		return 1
	fi
}

validate_wait_attempts IMAGE_UI_BENCHMARK_TRACE_WAIT_ATTEMPTS "$trace_wait_attempts"
validate_wait_attempts IMAGE_UI_BENCHMARK_WINDOW_WAIT_ATTEMPTS "$window_wait_attempts"
validate_wait_delay IMAGE_UI_BENCHMARK_TRACE_WAIT_DELAY "$trace_wait_delay"
validate_wait_delay IMAGE_UI_BENCHMARK_WINDOW_WAIT_DELAY "$window_wait_delay"
trace_wait_timeout="${trace_wait_attempts} attempts x ${trace_wait_delay}s"
window_wait_timeout="${window_wait_attempts} attempts x ${window_wait_delay}s"

binary=${1:-./image-ui-benchmark}
if [[ -z ${WAYLAND_DISPLAY:-} || ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY} ]]; then
	printf 'Wayland smoke skipped: no Wayland display socket (trace wait %s; window wait %s)\n' "$trace_wait_timeout" "$window_wait_timeout"
	exit 0
fi
for command in niri jq wtype date mktemp grep seq sleep; do
	if ! command -v "$command" >/dev/null 2>&1; then
		printf 'Wayland smoke skipped: missing %s (trace wait %s; window wait %s)\n' "$command" "$trace_wait_timeout" "$window_wait_timeout"
		exit 0
	fi
done
if [[ ! -x $binary ]]; then
	printf 'Wayland smoke failed: benchmark executable not found: %s (trace wait %s; window wait %s)\n' "$binary" "$trace_wait_timeout" "$window_wait_timeout" >&2
	exit 1
fi

tmp=$(mktemp -d)
pid=
window_id=
original_focus=$(niri msg --json windows | jq -r '[.[] | select(.is_focused)][0].id // empty')
cleanup() {
	if [[ -n ${pid:-} ]] && kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		wait "$pid" 2>/dev/null || true
	fi
	if [[ -n ${original_focus:-} ]]; then
		niri msg action focus-window --id "$original_focus" >/dev/null 2>&1 || true
	fi
	rm -rf "$tmp"
}
trap cleanup EXIT INT TERM

"$binary" --prepare-fixtures "$tmp/fixtures" >"$tmp/fixtures.log"
prefetch_target='large-4k_next.bmp'
repeat_keys=${IMAGE_UI_BENCHMARK_REPEAT_KEYS:-8}
if (( repeat_keys < 1 )); then
	repeat_keys=8
fi

wait_for_trace() {
	trace=$1
	pattern=$2
	for _ in $(seq 1 "$trace_wait_attempts"); do
		if [[ -f $trace ]] && grep -Pq "$pattern" "$trace"; then
			return 0
		fi
		if [[ -n ${pid:-} ]] && ! kill -0 "$pid" 2>/dev/null; then
			printf 'Wayland smoke failed: benchmark process exited while waiting for trace event after %s: %s\n' "$trace_wait_timeout" "$pattern" >&2
			if [[ -n ${log:-} && -f $log ]]; then
				cat "$log" >&2
			fi
			return 1
		fi
		sleep "$trace_wait_delay"
	done
	printf 'Wayland smoke failed: trace event not observed after %s: %s\n' "$trace_wait_timeout" "$pattern" >&2
	grep -Ev '^(frame_interval|complete)' "$trace" >&2 || true
	niri msg --json windows | jq --argjson id "$window_id" '[.[] | select(.id == $id)]' >&2 || true
	return 1
}

run_smoke() {
	cache=$1
	opacity=$2
	if [[ $opacity == transparent ]]; then
		target="$tmp/fixtures/large-alpha.tga"
		expected_opacity=transparent
	else
		target="$tmp/fixtures/large-4k.bmp"
		expected_opacity=opaque
	fi
	trace="$tmp/wayland-$cache-$opacity.tsv"
	log="$tmp/wayland-$cache-$opacity.log"
	before_ids=$(niri msg --json windows | jq -c '[.[].id]')
	rm -f "$trace" "$trace.resize_request_us" "$trace.resize_request_width"
	launch_us=$(date +%s%6N)
	IMAGE_UI_BENCHMARK_CACHE="$cache" \
	IMAGE_UI_BENCHMARK_TRACE="$trace" \
	IMAGE_UI_BENCHMARK_LAUNCH_US="$launch_us" \
	IMAGE_UI_BENCHMARK_EXPECTED_OPACITY="$expected_opacity" \
	IMAGE_UI_BENCHMARK_FRAME_TARGET=360 \
	IMAGE_UI_BENCHMARK_WARMUP_FRAMES=60 \
	IMAGE_UI_BENCHMARK_REPEAT_KEYS="$repeat_keys" \
		"$binary" --wayland-smoke "$target" >"$log" 2>&1 &
	pid=$!
	window_id=
	for _ in $(seq 1 "$window_wait_attempts"); do
		if [[ -n ${pid:-} ]] && ! kill -0 "$pid" 2>/dev/null; then
			break
		fi
		window_id=$(niri msg --json windows | jq -r --argjson before "$before_ids" '[.[] | select((.id as $id | ($before | index($id)) == null) and (.title | startswith("image-ui")))][0].id // empty')
		if [[ -n $window_id ]]; then
			break
		fi
		sleep "$window_wait_delay"
	done
	if [[ -z $window_id ]]; then
		if [[ -n ${pid:-} ]] && ! kill -0 "$pid" 2>/dev/null; then
			printf 'Wayland smoke failed: benchmark process exited before its window appeared (window wait %s)\n' "$window_wait_timeout" >&2
		else
			printf 'Wayland smoke failed: benchmark window not found after %s\n' "$window_wait_timeout" >&2
		fi
		cat "$log" >&2
		exit 1
	fi
	niri msg action focus-window --id "$window_id" >/dev/null
	wait_for_trace "$trace" '^first_content'
	wait_for_trace "$trace" '^scan_complete'
	wait_for_trace "$trace" $'^prefetch_cached\t[^\t]*\t[^\t]*\t[^\t]*\t[^\t]*\t0\t.*'"$prefetch_target"'$'
	niri msg action focus-window --id "$window_id" >/dev/null
	workspace_id=$(niri msg --json windows | jq -r --argjson id "$window_id" '.[] | select(.id == $id) | .workspace_id')
	output_name=$(niri msg --json workspaces | jq -r --argjson id "$workspace_id" '.[] | select(.id == $id) | .output')
	scale=$(niri msg --json outputs | jq -r --arg name "$output_name" '.[$name].logical.scale')
	logical_width=$(jq -n --argjson scale "$scale" '3840 / $scale | round')
	date +%s%6N >"$trace.resize_request_us"
	printf '3840\n' >"$trace.resize_request_width"
	niri msg action set-column-width "$logical_width" >/dev/null
	wait_for_trace "$trace" $'^resize_observed\t[^\t]*\t3840\t'
	niri msg action focus-window --id "$window_id" >/dev/null
	wtype -k t
	sleep 0.2
	niri msg action focus-window --id "$window_id" >/dev/null
	wtype -k z
	sleep 0.2
	niri msg action focus-window --id "$window_id" >/dev/null
	wtype -k p
	sleep 0.2
	niri msg action focus-window --id "$window_id" >/dev/null
	wtype -k Right
	for _ in $(seq 1 $((repeat_keys - 1))); do
		niri msg action focus-window --id "$window_id" >/dev/null
		wtype -k Right
		sleep 0.03
		niri msg action focus-window --id "$window_id" >/dev/null
		wtype -k Left
		sleep 0.03
	done
	niri msg action focus-window --id "$window_id" >/dev/null
	wtype -k Left
	if ! wait "$pid"; then
		printf 'Wayland smoke failed: benchmark process failed (trace wait %s; window wait %s)\n' "$trace_wait_timeout" "$window_wait_timeout" >&2
		cat "$log" >&2
		grep -Ev '^(frame_interval|complete)' "$trace" >&2 || true
		exit 1
	fi
	pid=
	cat "$log"
}

run_smoke cold opaque
run_smoke cold transparent
run_smoke warm opaque
run_smoke warm transparent
