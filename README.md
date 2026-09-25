# image-ui

A fast, lightweight desktop image viewer system application built with [V](https://vlang.io) and [V UI](https://github.com/vlang/ui).

## Features

- **Measured Performance**: Checked-in headless and live Wayland benchmarks with deterministic fixtures, cache controls, median/p95 output, and checksum gates. Sub-10ms startup and 60 FPS at 4K remain targets.
- **Hardware-Accelerated Canvas**: Direct Sokol/`gg` rendering pipeline with continuous cursor-anchored zoom, sub-pixel pan, 90-degree step rotation, and flip.
- **Prioritized Neighborhood Sibling Scan**: Immediate adjacent ±50 files streamed over worker channel for instant arrow navigation, with non-blocking background folder discovery.
- **Full-Resolution Sibling LRU**: Byte-bounded current and nearby decoded resources reuse resident data without another file read or full decode.
- **Collapsible Filmstrip**: Bounded LRU-cached preview thumbnails (max 100 textures, ~20MB VRAM).
- **Dual Texture Filtering**: Bilinear anti-aliasing on downscaling, sharp nearest-neighbor at high magnification for pixel peeping.
- **Desktop & Wayland Integration**: Wayland CSD protocol support (`zxdg_decoration_manager_v1_mode_client_side`), FreeDesktop `.desktop` entry, OS trash integration (`gio trash`), and clipboard copy.
- **Crisp SVG Iconography**: Dedicated vector graphics for all UI controls; zero emojis or unicode symbol fallbacks.

## Building & Running

### Prerequisites
- The [threehymns/v](https://github.com/threehymns/v) toolchain fork (`dev` branch) — it carries patches stock V releases lack (see "Forks & upstream" below). Build it with `make` inside the checkout, then ensure its `v` is on your `PATH`:
```bash
git clone --branch dev https://github.com/threehymns/v.git
make -C v
export PATH="$PWD/v:$PATH"
```
- The `ui2` fork submodule — clone with submodules:
```bash
git clone --recurse-submodules https://github.com/threehymns/image-ui.git
# or, inside an existing checkout:
git submodule update --init
```
- Wayland development libraries (on Linux Wayland sessions: `wayland-client`, `wayland-cursor`, `wayland-egl`, `xkbcommon`)

### Build Commands

Using `make` (auto-detects Wayland session):
```bash
make
```

Or using the V compiler directly:
- **Wayland session (pure Wayland compositors e.g. Niri, Sway, GNOME Wayland)**:
  ```bash
  v -d sokol_wayland -o image-ui .
  ```
- **X11 / Xwayland session**:
  ```bash
  v -o image-ui .
  ```

### Running
```bash
./image-ui [path_to_image]
```

The full-resolution Sibling cache uses `IMAGE_UI_SIBLING_CACHE_BUDGET_BYTES` for its byte budget. `IMAGE_UI_SIBLING_CACHE_NEIGHBOR_RADIUS` controls how many discovered Siblings on each side of the current image are retained. The Filmstrip Thumbnail Cache keeps its separate ADR-0003 budget.

### Running Tests
```bash
make test
```

### Running Benchmarks
The CPU and screen-construction suite needs no display server:
```bash
make benchmark
```

The live niri/Wayland smoke records process launch, first content, real key input, resize, Sibling switching, pan, zoom, and Viewer frame-callback cadence. It reports the actual measured viewport and does not treat a 4K image fixture as a 4K viewport:
```bash
make benchmark-wayland
```

Use `--warmup`, `--iterations`, `--cache`, and `--cache-budget` through `BENCHMARK_ARGS` to control sampling. CI only compiles the benchmark; it has no noisy wall-clock gates. See the [benchmark methodology and recorded baseline](./docs/benchmarks.md).

## Performance claims

The checked-in measurements describe the current path. The current 4K image metadata decode and synchronous Sibling decode are measured costs, not guarantees; the transparency background uses a small repeat tile rather than a full-window raster. Sub-10ms complete startup, 60 FPS at 3840x2160, p95 presented-frame time below 16.7ms, and 8.3ms headroom remain targets. The live suite records Viewer build-callback cadence because UI2 does not expose a post-present GPU fence.

## Forks & upstream

This project depends on two personal forks, both tracked on their `dev` branches. Each exists only to carry a small patch set until it lands upstream:

- **[threehymns/v](https://github.com/threehymns/v)** (toolchain): folds Shift-modified keysyms to lowercase in the Sokol Wayland backend so Shift+letter shortcuts resolve, and stops V3 codegen from emitting `typedef struct T T;` guesses for types owned by system headers (e.g. X11's anonymous-struct typedefs), which broke every local build. CI builds this fork from source.
- **[threehymns/ui2](https://github.com/threehymns/ui2)** (vendored above as the `ui2/` submodule): forwards unhandled scroll gestures as `scroll:` events, adds `pixelated` sampling and `flip_h`/`flip_v` mirroring, decodes keyboard modifiers with the correct `sapp.Modifier` masks, and provides a backend-neutral repeat-pattern background contract.

## Architecture & Domain Model

- [Domain Glossary (CONTEXT.md)](./CONTEXT.md)
- [ADR-0001: Custom Canvas Rendering Engine Over Built-in Picture Widget](./docs/adr/0001-custom-canvas-rendering.md)
- [ADR-0002: Prioritized Neighborhood Sibling Scan](./docs/adr/0002-prioritized-neighborhood-sibling-scan.md)
- [ADR-0003: Bounded LRU Thumbnail Cache for Filmstrip](./docs/adr/0003-bounded-lru-thumbnail-cache.md)
- [ADR-0004: Wayland CSD Protocol and Hidden CSD Support](./docs/adr/0004-wayland-csd-and-borderless-fullscreen.md)
- [ADR-0005: SVG Vector Icons Over Unicode/Emoji Symbols](./docs/adr/0005-svg-icons-over-unicode-symbols.md)
