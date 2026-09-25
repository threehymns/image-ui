#!/usr/bin/env bash
set -euo pipefail

binary=${1:-./image-ui-benchmark}
if [[ -z ${WAYLAND_DISPLAY:-} || ! -S ${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY} ]]; then
	printf 'Wayland smoke skipped: no Wayland display socket\n'
	exit 0
fi
for command in niri jq wtype date mktemp grep seq sleep; do
	if ! command -v "$command" >/dev/null 2>&1; then
		printf 'Wayland smoke skipped: missing %s\n' "$command"
		exit 0
	fi
done
if [[ ! -x $binary ]]; then
	printf 'Wayland smoke failed: benchmark executable not found: %s\n' "$binary" >&2
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
target="$tmp/fixtures/large-4k.bmp"

wait_for_trace() {
	trace=$1
	pattern=$2
	limit=${3:-200}
	for _ in $(seq 1 "$limit"); do
		if [[ -f $trace ]] && grep -Pq "$pattern" "$trace"; then
			return 0
		fi
		sleep 0.025
	done
	printf 'Wayland smoke failed: trace event not observed: %s\n' "$pattern" >&2
	grep -Ev '^(frame_interval|complete)' "$trace" >&2 || true
	niri msg --json windows | jq --argjson id "$window_id" '[.[] | select(.id == $id)]' >&2 || true
	return 1
}

run_smoke() {
	cache=$1
	trace="$tmp/wayland-$cache.tsv"
	log="$tmp/wayland-$cache.log"
	before_ids=$(niri msg --json windows | jq -c '[.[].id]')
	rm -f "$trace" "$trace.resize_request_us" "$trace.resize_request_width"
	launch_us=$(date +%s%6N)
	IMAGE_UI_BENCHMARK_CACHE="$cache" \
	IMAGE_UI_BENCHMARK_TRACE="$trace" \
	IMAGE_UI_BENCHMARK_LAUNCH_US="$launch_us" \
	IMAGE_UI_BENCHMARK_FRAME_TARGET=360 \
	IMAGE_UI_BENCHMARK_WARMUP_FRAMES=60 \
		"$binary" --wayland-smoke "$target" >"$log" 2>&1 &
	pid=$!
	window_id=
	for _ in $(seq 1 200); do
		window_id=$(niri msg --json windows | jq -r --argjson before "$before_ids" '[.[] | select((.id as $id | ($before | index($id)) == null) and (.title | startswith("image-ui")))][0].id // empty')
		if [[ -n $window_id ]]; then
			break
		fi
		if ! kill -0 "$pid" 2>/dev/null; then
			break
		fi
		sleep 0.025
	done
	if [[ -z $window_id ]]; then
		printf 'Wayland smoke failed: benchmark window not found\n' >&2
		cat "$log" >&2
		exit 1
	fi
	niri msg action focus-window --id "$window_id" >/dev/null
	wait_for_trace "$trace" '^first_content'
	wait_for_trace "$trace" '^scan_complete'
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
	if ! wait "$pid"; then
		printf 'Wayland smoke failed: benchmark process failed\n' >&2
		cat "$log" >&2
		grep -Ev '^(frame_interval|complete)' "$trace" >&2 || true
		exit 1
	fi
	pid=
	cat "$log"
}

run_smoke cold
run_smoke warm
