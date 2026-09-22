# Spec: Fast Desktop Image Viewer System App (image-ui)

> GitHub Issue: [#1](https://github.com/threehymns/image-ui/issues/1)
> Triage Label: `ready-for-agent`

## Problem Statement

Users on desktop environments need an image viewer that launches instantly without startup delay, navigates directories containing thousands of photos smoothly without UI stutter, offers precise cursor-anchored zoom and sub-pixel panning, supports Wayland Client-Side Decorations (CSD) with hidden CSDs in borderless/fullscreen mode, uses crisp vector iconography rather than inconsistent emojis, and integrates safely with system facilities (Trash, Clipboard, File Manager).

## Solution

`image-ui`: A fast, lightweight desktop image viewer system application built with V and V UI. It features a custom hardware-accelerated Sokol/`gg` canvas rendering pipeline, zero-TTI startup with asynchronous prioritized neighborhood sibling scanning, a collapsible LRU-cached thumbnail filmstrip, Wayland client-side decoration protocol support with auto-hiding header in fullscreen, dedicated crisp SVG iconography, and safe desktop file integration.

## User Stories

1. As a desktop user, I want the viewer to launch and render a target image in under 10 milliseconds, so that opening pictures from my file manager feels instantaneous.
2. As a photographer, I want zooming with the mouse wheel to anchor to my cursor position, so that I can immediately inspect the exact detail under my pointer.
3. As a user reviewing large folders, I want sibling navigation via Left and Right arrow keys to work immediately upon launch without waiting for 20,000 files in the directory to scan.
4. As a digital artist or game developer, I want magnification above 200% to use nearest-neighbor pixel filtering, so that I can inspect pixel art and texture details with crisp, non-blurry edges.
5. As a photo reviewer, I want downscaled images (< 100%) to use smooth bilinear anti-aliasing, so that high-resolution photos don't suffer from moiré or jagged downsampling artifacts.
6. As a user, I want to click and drag with the left mouse button to smoothly pan around an image when zoomed in beyond the window boundaries.
7. As a user, I want double-clicking the image canvas to toggle between Fit to Window and Actual Size (1:1), so that I can quickly switch between overview and detail inspection.
8. As a photo enthusiast comparing burst shots or render versions, I want to toggle Lock Viewport (`L`), so that zoom magnification and pan coordinates remain unchanged as I switch between consecutive sibling images.
9. As a user, I want to rotate images in 90-degree steps using `R` (clockwise) and `Shift+R` (counter-clockwise), so that I can quickly fix photo orientation without permanent file modification.
10. As a user, I want to flip images horizontally (`H`) and vertically (`V`), so that I can mirror images on the fly.
11. As a user, I want a collapsible thumbnail filmstrip at the bottom of the window (`F`), so that I can visually preview and jump directly to any sibling image in the current folder.
12. As a user with limited system memory, I want the filmstrip to maintain a bounded LRU thumbnail cache capped at ~20MB, so that browsing massive folders never exhausts RAM or GPU VRAM.
13. As a Linux Wayland user, I want the application to support the Wayland CSD protocol (`zxdg_decoration_manager_v1_mode_client_side`), so that my window has clean client-side window management without duplicate titlebars.
14. As a Wayland user, I want the top headerbar to support window dragging from empty background areas and double-click to maximize/restore, matching native desktop behavior.
15. As an immersive media viewer, I want pressing `F11` or `Alt+Enter` to enter borderless fullscreen mode with all CSDs and titlebars completely suppressed.
16. As a fullscreen user, I want the top control header to auto-hide after 2.5 seconds of mouse inactivity and smoothly reappear when moving the mouse near the top edge.
17. As a desktop user, I want all toolbar buttons and controls to use crisp, scalable SVG vector icons, so that no broken, blurry, or missing emoji symbols appear regardless of system fonts.
18. As a user who encounters a corrupted, zero-byte, or unsupported file, I want to see a non-disruptive in-viewport Error Card, so that my sibling playlist and browsing flow remain intact without annoying modal alert popups.
19. As a presenter, I want to start a timed slideshow using `-s <seconds>` or `Space`, so that the viewer automatically advances through sibling photos.
20. As a presenter, I want manual navigation or zooming during a slideshow to interactively pause the timer, so that I can stop to discuss a photo without losing slideshow context.
21. As a desktop user, I want pressing `Ctrl+C` to copy the image to the system clipboard, so that I can paste it into documents or messaging apps.
22. As a desktop user, I want pressing `Delete` to move the current file safely to the desktop OS Trash (`gio trash`), so that I can triage unwanted photos without accidental permanent deletion.
23. As a desktop user, I want pressing `Ctrl+Shift+O` to reveal the current image in the system file manager, so that I can quickly access the underlying file.
24. As a terminal power user, I want to launch `image-ui [path] [flags]`, where path can be an image file or a directory, so that the app seamlessly fits my shell workflow.
25. As a desktop user, I want the application to register a FreeDesktop `.desktop` entry and MIME type associations, so that `image-ui` is available as a default image handler in desktop file managers.

## Implementation Decisions

- **Custom Canvas Rendering Engine Over Built-in Picture Widget**: Built upon `ui.canvas_layout` with direct Sokol/`gg` context draw calls (`draw_image_with_config`) to provide 60+ FPS hardware-accelerated transforms, cursor-anchored zoom matrix calculation, alpha transparency checkerboard rendering, and dual texture filtering (ADR-0001).
- **Prioritized Neighborhood Sibling Scan**: Decouples target image rendering from directory scanning. A background worker scans the immediate ±50 adjacent files first and streams them over a V channel to unblock Left/Right arrow navigation within milliseconds, before streaming the rest of the folder progressively (ADR-0002).
- **Bounded LRU Thumbnail Cache for Filmstrip**: The filmstrip requests low-resolution 128x128 preview textures on demand from a worker thread pool, evicting off-screen textures past a fixed LRU cap of 100 entries (~20MB) to preserve GPU VRAM (ADR-0003).
- **Wayland CSD Protocol and Hidden CSD Support**: Explicitly requests client-side decorations (`zxdg_decoration_manager_v1_mode_client_side`), using the custom top bar as the headerbar in windowed mode and suppressing all CSDs via `xdg_toplevel_set_fullscreen` and borderless modes (ADR-0004).
- **SVG Vector Iconography Over Unicode/Emoji Symbols**: Strictly renders dedicated SVG vector graphics at target display scale for all buttons, toggles, and status indicators. Emojis and unicode symbol characters are strictly prohibited (ADR-0005).
- **Non-Destructive File Operations**: Integrates with FreeDesktop standards using `gio trash` for recoverable file deletion and X11/Wayland clipboard copy.
- **Domain-Separated Codebase Architecture**: Decoupled into `main.v`, `app.v`, `canvas/` (rendering & viewport), `scanner/` (async directory traversal), `filmstrip/` (thumbnails & cache), `ui/` (top bar, CSD, shortcuts), and `assets/` (SVG icons, .desktop file).

## Testing Decisions

- **Testing Philosophy**: Focus entirely on testing external behavior, state transitions, and contract invariants. Never test internal UI widget layout details or private drawing coordinates.
- **Primary Testing Seam**:
  - The **`App` State and Event Dispatcher Seam (`App`)**. A headless-drivable application controller that accepts file inputs and dispatches actions (`open_path`, `next_sibling`, `prev_sibling`, `zoom_in`, `zoom_out`, `zoom_actual`, `zoom_fit`, `rotate_cw`, `rotate_ccw`, `flip_h`, `flip_v`, `toggle_filmstrip`, `delete_active`), verifying that playlist indexing, viewport transformation matrices, lock viewport states, and status text update correctly without requiring an active OpenGL/Wayland display server.
- **Secondary Testing Seams**:
  - **`scanner` Seam**: Verifies natural-alphanumeric sorting and asynchronous neighborhood channel streaming against temporary directory fixtures containing edge-case filenames (`img1.png`, `img2.png`, `img10.png`, mixed case, non-image files).
  - **`viewport` Seam**: Verifies coordinate transform math for cursor-anchored zoom, aspect-ratio preservation under Fit to Window, and 90-degree step rotation boundaries.
- **Prior Art**: Standard V unit test runner (`v test .`).

## Out of Scope

- Photo editing and image manipulation (crop saving, exposure adjustments, color filters, sharpening).
- Photo library cataloging (albums, tags, search database, face detection).
- Multi-track video and audio playback.
- Proprietary RAW camera formats without external conversion utilities.

## Further Notes

- Domain glossary defined in [CONTEXT.md](./CONTEXT.md).
- Architecture decision records: [ADR-0001](./docs/adr/0001-custom-canvas-rendering.md) through [ADR-0005](./docs/adr/0005-svg-icons-over-unicode-symbols.md).
- Built using V 0.5.2 and V UI (`vlang/ui`).
