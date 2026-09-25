# Viewer performance benchmarks

The root benchmark suite measures the current Viewer path, including the asynchronous image resource, background scanner, cached transparency tile, and startup phase trace. CI compiles it and runs correctness tests, but hosted runners do not enforce wall-clock thresholds.

## Commands

Run the headless suite without `WAYLAND_DISPLAY`, `DISPLAY`, X11, or Wayland:

```bash
make benchmark
```

The default is two warmup iterations followed by 10 measured iterations. Override those controls through `BENCHMARK_ARGS`:

```bash
make benchmark BENCHMARK_ARGS="--warmup 3 --iterations 20 --cache both"
make benchmark BENCHMARK_ARGS="--cache cold"
make benchmark BENCHMARK_ARGS="--cache warm"
```

Compile without running measurements:

```bash
make benchmark-build
```

Prepare the deterministic fixture set in a chosen directory:

```bash
make benchmark-fixtures BENCHMARK_ARGS=/tmp/image-ui-benchmark-fixtures
```

Run the live smoke on niri:

```bash
make benchmark-wayland
```

The live command needs a Wayland socket plus `niri`, `jq`, and `wtype`. It exits with a clear skipped message when those requirements are absent. The script restores the previously focused window on exit.

## Fixtures

`make benchmark` generates all fixtures in a temporary directory and removes them after the run. Generation uses fixed dimensions, fixed pixel formulas, and fixed file names.

| Fixture | Size | Purpose |
| --- | --- | --- |
| `alpha.tga` | 64x64 | Four deterministic alpha levels |
| `opaque.bmp` | 96x64 | Small opaque image decode |
| `large-4k.bmp` | 3840x2160 | 4K-class metadata decode and live rendering |
| `siblings/sibling-000.bmp` through `sibling-127.bmp` | 96x64 each | Directory discovery and adjacent navigation |

The 128 Sibling entries are hard links to the opaque fixture. They have independent paths for natural sorting and navigation without consuming 128 copies of the image. A user-supplied fixture directory is preserved; the suite only replaces its reserved `alpha.tga`, `opaque.bmp`, `large-4k.bmp`, and `sibling-*.bmp` files.

## Headless measurements

The headless binary never calls `ui2.run_window`. It can therefore run on a machine with no display server.

| Case | What the timer covers |
| --- | --- |
| `image_load_alpha`, `image_load_opaque`, `image_load_4k` | File read, `stbi` metadata decode, and decode free through the production `load_image_metadata` seam |
| `sibling_discovery` | Spawn, complete directory enumeration, natural sort, channel batches, and final batch through the current scanner |
| `sibling_navigation` | Playlist step plus the current synchronous metadata decode |
| `frame_prepare_4k` | Zoom, pan, and 4K screen-element construction with one logical repeat tile |
| `pattern_tile` | Creation of the 32x32 logical repeat tile containing 16 px cells |
| `screen_construct_4k` | Current UI2 element construction and repeat-tile reuse |
| `screen_resize_to_4k` | Three screen builds needed to move from 1920x1080 to 3840x2160 |
| `startup_cpu` | `new_app`, 4K metadata decode, state setup, and 1024x768 screen construction; it is not process-launch time |

`screen_construct_4k` and `frame_prepare_4k` stop before GPU submission. They are CPU and element-construction measurements, not rendered-frame measurements.

Every row includes warmup count, fixed iteration count, cache label, median, p95, and a returned-value checksum. A checksum mismatch fails the command. CI does not run this timing suite and has no timing threshold.

### Startup phase trace

The headless suite also emits a phase-order smoke table with monotonic timestamps for process launch, window creation, font work, UI2 setup, GPU setup, first content, first input, and directory completion. It validates the ordering seam without claiming to measure a real process launch or GPU present. The live suite records the same phase names from the running Viewer process. Font discovery, metrics, and symbol fallback preparation are scheduled after context creation and run in the background; the first-content mark is emitted only after an image resource is ready and the completed UI2 frame callback.

## Cache controls

`--cache cold`, `--cache warm`, and `--cache both` select which screen-construction cases are run. The transparency background is a logical repeat tile and has no file cache.

- Pattern rows reuse the same 32x32 tile and do not allocate a window-sized raster.
- Image decode has no application cache in the current Viewer. Its rows say `no-app-cache`; filesystem page-cache state is not claimed or forcibly controlled.
- Live cold and warm labels describe separate process runs; they do not control a checkerboard file.

## Live Wayland smoke

Each live run starts the benchmark build with the 4K image fixture, waits for the first content screen and complete directory scan, then asks niri to resize the focused tiled window. The report uses the actual measured viewport; a 3840-pixel width without a 2160-pixel height is not 4K evidence. The run collects 360 frame callbacks, discards the first 60 as warmup, and reports median and p95 for the remaining 300.

The harness sends real Wayland key input through `wtype` and verifies each action before the next run:

- `t` toggles the checkerboard.
- `Right` switches to the next Sibling.
- `p` is available only in the benchmark build and calls the current `App.pan` path.
- `z` is available only in the benchmark build and calls the current `App.zoom_in` path.

The trace reports process launch to first content, process launch to the harness's first input, separate monotonic startup-phase timestamps, each input-to-next-screen-build interval, compositor resize request to the 3840-pixel resize observation, frame-callback cadence, and a trace checksum. The first-content mark is tied to a ready image resource rather than the initial empty/drop-target frame.

The cadence value is the interval between Viewer `build_screen` callbacks. UI2 does not expose a post-present fence or GPU timestamp, so these values do not prove when the compositor presented the frame.

## Recorded baseline

Recorded on 2026-09-25 from the #18 implementation on branch `t3code/15-transparency`. The benchmark output records the exact source commit used for each run.

- OS: Linux 7.1.8-arch1-3, x86_64
- CPU: Intel Core i7-8565U at 1.80 GHz, 8 logical CPUs
- Memory: 32,628,928 kB reported by the kernel
- GPU driver: `i915`
- V: 0.5.2, commit `26fdab8`
- Compiler: GCC 16.2.1
- Build flags: `-d sokol_wayland -d viewer_benchmark`
- Headless controls: 2 warmups, 10 iterations, both cache states

### Headless baseline

| Case | Cache | Median ms | p95 ms |
| --- | --- | ---: | ---: |
| Alpha image load | no app cache | 0.10 | 0.51 |
| Opaque image load | no app cache | 0.30 | 0.48 |
| 4K image load | no app cache | 529.47 | 804.27 |
| 128-Sibling discovery | filesystem state uncontrolled | 1.51 | 2.48 |
| Sibling navigation | no app cache | 0.29 | 0.43 |
| Pattern tile creation | constant | 0.28 | 0.39 |
| 4K frame preparation | pattern resource | 0.01 | 0.02 |
| 4K screen construction, first selection | pattern resource | 0.49 | 0.52 |
| Resize to 4K | pattern resource | 0.04 | 0.04 |
| CPU startup path with 4K image, first selection | pattern resource | 481.35 | 786.86 |
| 4K screen construction, second selection | pattern resource | 0.39 | 0.48 |
| CPU startup path with 4K image, second selection | pattern resource | 459.64 | 602.97 |

All returned-value checks passed.

### Live Wayland baseline

| Measurement | Cold process | Warm process |
| --- | ---: | ---: |
| Measured viewport | 3840x2094 | 3840x2094 |
| Process launch to first content | 1265.65 ms | 1251.70 ms |
| Process launch to harness first input | 2346.38 ms | 2421.62 ms |
| Toggle to screen build | 0.17 ms | 0.16 ms |
| Sibling switch to screen build | 0.16 ms | 0.14 ms |
| Pan to screen build | 0.14 ms | 0.18 ms |
| Zoom to screen build | 0.25 ms | 0.18 ms |
| Resize request to measured-width screen build | 33.97 ms | 52.87 ms |
| Frame callback median | 16.75 ms | 16.75 ms |
| Frame callback p95 | 17.00 ms | 18.31 ms |
| Samples after warmup | 300 | 300 |
| Trace checksum | `1e2c2b207cd66efd` | `1e2c2b207cd66efd` |

The two process labels are separate launches, not cold and warm versions of a file-backed background resource. The measured 3840x2094 viewport is not 4K, and the warm callback p95 exceeded 16.7 ms; no 4K or frame-time target claim is made. Frame callback cadence does not include a post-present GPU fence.

### Startup phase evidence

Recorded on 2026-09-25 from commit `3abdad6` with `make benchmark-wayland` on niri, the available Intel Core i7-8565U / `i915` machine. Values are monotonic elapsed milliseconds from process launch at the phase mark. The font mark is the scheduling point for background font preparation; the first-content mark follows a ready decoded resource and the completed UI2 frame callback.

| Phase | Cold process | Warm process |
| --- | ---: | ---: |
| Process launch | 0.00 | 0.00 |
| Window creation | 79.20 | 115.43 |
| Font work scheduled | 0.10 | 0.14 |
| UI2 setup | 0.09 | 0.12 |
| GPU setup | 79.23 | 115.51 |
| First content | 1764.56 | 1941.09 |
| First input | 1933.09 | 2105.12 |
| Directory completion | 129.92 | 181.83 |

The observed order was `process_launch > ui2_setup > font_work > window_creation > gpu_setup > directory_completion > first_content > first_input` for both runs. The live checksum was `df304cfd721b348c`; the measured viewport was 3840x2094. These are local timing samples, not a 10 ms, 4K, or post-present GPU guarantee.

## Diagnostics versus repeatable results

The table above is the checked-in baseline. It uses fixed fixtures, fixed sample counts, explicit cache controls, checksums, and recorded build and hardware state.

Earlier syscall tracing from issue #15 is diagnostic only and predates the repeat-tile path. It recorded about 15 ms to Wayland connection, about 324 ms to a warm full-window resource access, and about 1.28 seconds to a cold full-window write with a 1916x2094 window. Tracing changed scheduling and I/O cost, so those values are not benchmark samples and are not pass/fail gates.

The following remain targets rather than guarantees:

- Sub-10 ms complete process startup
- 60 FPS at 3840x2160
- p95 presented-frame time below 16.7 ms
- 8.3 ms frame headroom

The current live harness cannot prove presented-frame GPU time. A later resource or renderer change can add a backend fence or GPU timestamp without changing the fixture, statistics, build, hardware, or checksum reporting contract.
