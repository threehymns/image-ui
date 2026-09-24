V ?= v
FLAGS ?=

# Prefer Wayland when WAYLAND_DISPLAY is present, including sessions that also
# expose DISPLAY through XWayland.
ifneq ($(WAYLAND_DISPLAY),)
WAYLAND_FLAG ?= -d sokol_wayland
endif

.PHONY: all build build-wayland build-x11 test clean

all: build

# App test files, scoped explicitly: a bare `v test .` would also descend
# into the ui2 submodule and run its whole suite (including platform-specific
# tests that fail elsewhere).
TEST_FILES ?= app_test.v checkerboard_test.v cli_test.v filter_test.v flip_test.v keys_test.v pan_test.v scanner_test.v scroll_test.v viewport_test.v

build:
	$(V) $(WAYLAND_FLAG) $(FLAGS) -o image-ui .

build-wayland:
	$(V) -d sokol_wayland $(FLAGS) -o image-ui .

build-x11:
	$(V) $(FLAGS) -o image-ui .

test:
	$(V) test $(TEST_FILES)

clean:
	rm -f image-ui
