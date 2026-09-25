# 1. Custom Canvas Rendering Engine Over Built-in Picture Widget

## Context
V UI provides a high-level `ui.picture` widget designed for static UI imagery. However, a dedicated system image viewer requires continuous cursor-anchored zoom, sub-pixel panning, arbitrary 90-degree rotations, horizontal/vertical flipping, and alpha checkerboard rendering with a measured performance path and a separately stated 4K frame-rate target.

## Decision
We bypass `ui.picture` and implement image presentation via a custom `ui.canvas_layout` utilizing low-level Sokol/`gg` context draw calls (`ctx.draw_image_with_config`).

## Consequences
- Full control over transformation matrices, viewport clipping, and zoom interpolation.
- Ability to draw transparent grid patterns and overlay HUD graphics without widget hierarchy overhead.
- Performance claims are checked against the root benchmark suite. The checked-in evidence covers deterministic screen-construction, cache, startup-phase, and live build-callback measurements. A 60+ FPS presented-frame result remains a target until an exact 3840x2160 viewport and a backend post-present fence record it.
- Requires managing image cache invalidation and mouse drag/wheel event coordinates manually within the canvas component.
