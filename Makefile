V ?= v
FLAGS ?=
BENCHMARK_ARGS ?=
BENCHMARK_FLAGS ?= -d viewer_benchmark
BENCHMARK_FILE_LIST ?= benchmark_support.v,startup_trace.v,benchmark_fixtures.v,benchmark_live.v,image_load.v,image_resource.v,main.v,app.v,checkerboard.v,scanner.v,viewport.v

# Prefer Wayland when WAYLAND_DISPLAY is present, including sessions that also
# expose DISPLAY through XWayland.
ifneq ($(WAYLAND_DISPLAY),)
WAYLAND_FLAG ?= -d sokol_wayland
endif

.PHONY: all build build-wayland build-x11 benchmark benchmark-build benchmark-wayland benchmark-fixtures test clean

all: build

# App test files, scoped explicitly: a bare `v test .` would also descend
# into the ui2 submodule and run its whole suite (including platform-specific
# tests that fail elsewhere).
TEST_FILES ?= app_test.v benchmark_test.v checkerboard_test.v cli_test.v filter_test.v flip_test.v image_resource_test.v keys_test.v main_test.v pan_test.v scanner_test.v scroll_test.v startup_test.v viewport_test.v

build:
	$(V) $(WAYLAND_FLAG) $(FLAGS) -o image-ui .

build-wayland:
	$(V) -d sokol_wayland $(FLAGS) -o image-ui .

build-x11:
	$(V) $(FLAGS) -o image-ui .

benchmark-build:
	$(V) -d sokol_wayland $(BENCHMARK_FLAGS) $(FLAGS) -o image-ui-benchmark benchmark.v -file-list "$(BENCHMARK_FILE_LIST)"

benchmark: benchmark-build
	./image-ui-benchmark $(BENCHMARK_ARGS)

benchmark-wayland: benchmark-build
	./benchmarks/wayland_smoke.sh ./image-ui-benchmark

benchmark-fixtures: benchmark-build
	./image-ui-benchmark --prepare-fixtures $(BENCHMARK_ARGS)

test:
	$(V) -enable-globals test $(TEST_FILES)

clean:
	rm -f image-ui image-ui-benchmark
