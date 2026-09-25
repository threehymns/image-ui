#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
v=${V:-v}

if [[ ${1:-} == --commands ]]; then
	printf '%s\n' \
		'AppKit: make -C ui2 check-macos && v test ui2/appkit/ui_macos_test.v ui2/ui/image_resource_test.v ui2/ui/repeat_pattern_test.v' \
		'UIKit: make -C ui2 check-ios && v -shared -os ios -check .' \
		'Windows: make -C ui2 check-windows && v test ui2/windows/ui_windows_test.v' \
		'Linux: make -C ui2 check-linux'
	exit 0
fi

case $(uname -s) in
	Darwin)
		make -C "$root/ui2" check-macos
		"$v" test "$root/ui2/appkit/ui_macos_test.v" "$root/ui2/ui/image_resource_test.v" "$root/ui2/ui/repeat_pattern_test.v"
		;;
	Linux)
		make -C "$root/ui2" check-linux
		printf '%s\n' 'Native AppKit, UIKit, and Windows visual runs were not attempted on Linux.'
		;;
	Windows*|MINGW*|MSYS*)
		make -C "$root/ui2" check-windows
		"$v" test "$root/ui2/windows/ui_windows_test.v"
		;;
	*)
		printf 'Native contract platform unsupported: %s\n' "$(uname -s)" >&2
		exit 1
		;;
esac
