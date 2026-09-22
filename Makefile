V ?= v
FLAGS ?=

# Auto-detect Wayland session when WAYLAND_DISPLAY is present and DISPLAY is unset
ifeq ($(DISPLAY),)
ifneq ($(WAYLAND_DISPLAY),)
WAYLAND_FLAG ?= -d sokol_wayland
endif
endif

.PHONY: all build build-wayland build-x11 test clean

all: build

build:
	$(V) $(WAYLAND_FLAG) $(FLAGS) -o image-ui .

build-wayland:
	$(V) -d sokol_wayland $(FLAGS) -o image-ui .

build-x11:
	$(V) $(FLAGS) -o image-ui .

test:
	$(V) test .

clean:
	rm -f image-ui
