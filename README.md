# image-ui

A fast, lightweight desktop image viewer system application built with [V](https://vlang.io) and [V UI](https://github.com/vlang/ui).

## Features

- **Blazing Fast**: Sub-10ms startup (zero-TTI), immediate display of target images.
- **Hardware-Accelerated Canvas**: Direct Sokol/`gg` rendering pipeline with continuous cursor-anchored zoom, sub-pixel pan, 90-degree step rotation, and flip.
- **Prioritized Neighborhood Sibling Scan**: Immediate adjacent ±50 files streamed over worker channel for instant arrow navigation, with non-blocking background folder discovery.
- **Collapsible Filmstrip**: Bounded LRU-cached preview thumbnails (max 100 textures, ~20MB VRAM).
- **Dual Texture Filtering**: Bilinear anti-aliasing on downscaling, sharp nearest-neighbor at high magnification for pixel peeping.
- **Desktop & Wayland Integration**: Wayland CSD protocol support (`zxdg_decoration_manager_v1_mode_client_side`), FreeDesktop `.desktop` entry, OS trash integration (`gio trash`), and clipboard copy.
- **Crisp SVG Iconography**: Dedicated vector graphics for all UI controls; zero emojis or unicode symbol fallbacks.

## Building & Running

### Prerequisites
- [V compiler](https://github.com/vlang/v) (latest master or release)
- `ui` module (`v install ui`)
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

### Running Tests
```bash
v test .
```

## Architecture & Domain Model

- [Domain Glossary (CONTEXT.md)](./CONTEXT.md)
- [ADR-0001: Custom Canvas Rendering Engine Over Built-in Picture Widget](./docs/adr/0001-custom-canvas-rendering.md)
- [ADR-0002: Prioritized Neighborhood Sibling Scan](./docs/adr/0002-prioritized-neighborhood-sibling-scan.md)
- [ADR-0003: Bounded LRU Thumbnail Cache for Filmstrip](./docs/adr/0003-bounded-lru-thumbnail-cache.md)
- [ADR-0004: Wayland CSD Protocol and Hidden CSD Support](./docs/adr/0004-wayland-csd-and-borderless-fullscreen.md)
- [ADR-0005: SVG Vector Icons Over Unicode/Emoji Symbols](./docs/adr/0005-svg-icons-over-unicode-symbols.md)
