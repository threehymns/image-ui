# 3. Bounded LRU Thumbnail Cache for Filmstrip

## Context
Rendering thumbnails for hundreds or thousands of high-resolution images can rapidly exhaust system RAM and GPU VRAM if full images are loaded into textures.

## Decision
The filmstrip maintains a bounded LRU cache (capped at 100 entries / ~20MB) of downscaled 128x128 pixel preview textures. Textures are generated asynchronously by worker threads and lazily requested only for visible filmstrip slots plus a small off-screen prefetch buffer.

## Consequences
- Constant, deterministic memory footprint even in directories containing 10,000+ RAW/JPEG photos.
- Smooth scrolling is a target; 60 FPS has not been measured by the root Viewer benchmark.
- Cache misses during rapid scrolling show a lightweight placeholder until the worker downsamples the target thumbnail.
