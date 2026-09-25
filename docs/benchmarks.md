# Viewer performance benchmarks

The root benchmark suite measures the current Viewer before later image-resource, cache, and background-work changes land. CI compiles it and runs correctness tests, but hosted runners do not enforce wall-clock thresholds.

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
| `frame_prepare_4k` | Zoom, pan, and 4K screen-element construction with a warm checkerboard resource |
| `checkerboard_generate_4k` | Current full-window BMP encoding and file write after cache removal |
| `checkerboard_lookup_4k` | Existing-file branch of the current checkerboard cache |
| `screen_construct_4k` | Current UI2 element construction and checkerboard lookup or generation |
| `screen_resize_to_4k` | Three screen builds needed to move from 1920x1080 to 3840x2160 under the current two-stable-frame resize workaround |
| `startup_cpu` | `new_app`, 4K metadata decode, state setup, and 1024x768 screen construction; it is not process-launch time |

`screen_construct_4k` and `frame_prepare_4k` stop before GPU submission. They are CPU and element-construction measurements, not rendered-frame measurements.

Every row includes warmup count, fixed iteration count, cache label, median, p95, and a returned-value checksum. A checksum mismatch fails the command. CI does not run this timing suite and has no timing threshold.

## Cache controls

`--cache cold`, `--cache warm`, and `--cache both` control the current exact-size checkerboard BMP file.

- Cold removes the exact file before every measured sample. The timed operation regenerates and writes it.
- Warm creates the file before timing. The timed operation takes the existing-file branch and does not regenerate pixels.
- Image decode has no application cache in the current Viewer. Its rows say `no-app-cache`; filesystem page-cache state is not claimed or forcibly controlled.
- Live cold and warm runs control the same checkerboard resource. Fixture image bytes are shared by the two live processes, so the second run also has a warm filesystem cache.

## Live Wayland smoke

Each live run starts the benchmark build with the 4K fixture, waits for the first content screen and complete directory scan, then asks niri to resize the focused tiled window. On the scale-2 baseline machine, a 1920 logical-pixel column gives UI2 a 3840x2094 physical-pixel framebuffer. The run collects 360 frame callbacks, discards the first 60 as warmup, and reports median and p95 for the remaining 300.

The harness sends real Wayland key input through `wtype` and verifies each action before the next run:

- `t` toggles the checkerboard.
- `Right` switches to the next Sibling.
- `p` is available only in the benchmark build and calls the current `App.pan` path.
- `z` is available only in the benchmark build and calls the current `App.zoom_in` path.

The trace reports process launch to first content, process launch to the harness's first input, each input-to-next-screen-build interval, compositor resize request to the 3840-pixel resize observation, frame-callback cadence, and a trace checksum.

The cadence value is the interval between Viewer `build_screen` callbacks. UI2 does not expose a post-present fence or GPU timestamp, so these values do not prove when the compositor presented the frame.

## Recorded baseline

Recorded on 2026-09-24 from the issue #16 working tree based on commit `091183922eb6`. Re-run the commands after committing to replace the source-state label with a clean commit hash.

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
| Alpha image load | no app cache | 0.08 | 0.37 |
| Opaque image load | no app cache | 0.19 | 0.32 |
| 4K image load | no app cache | 231.51 | 242.50 |
| 128-Sibling discovery | filesystem state uncontrolled | 0.99 | 1.44 |
| Sibling navigation | no app cache | 0.19 | 0.24 |
| 4K frame preparation | warm checkerboard | 0.01 | 0.01 |
| 4K checkerboard generation | cold app cache | 675.56 | 775.25 |
| 4K screen construction | cold app cache | 661.15 | 783.61 |
| Resize to 4K | cold app cache | 681.84 | 727.26 |
| CPU startup path with 4K image | cold app cache | 277.82 | 287.46 |
| 4K checkerboard lookup | warm app cache | 0.00 | 0.00 |
| 4K screen construction | warm app cache | 0.00 | 0.01 |
| CPU startup path with 4K image | warm app cache | 215.01 | 241.41 |

All returned-value checks passed.

### Live Wayland baseline

| Measurement | Cold checkerboard | Warm checkerboard |
| --- | ---: | ---: |
| Process launch to first content | 498.60 ms | 472.02 ms |
| Process launch to harness first input | 2020.09 ms | 1829.76 ms |
| Toggle to screen build | 0.10 ms | 0.10 ms |
| Sibling switch to screen build | 1.43 ms | 3.26 ms |
| Pan to screen build | 0.12 ms | 2.63 ms |
| Zoom to screen build | 0.16 ms | 0.20 ms |
| Resize request to 3840-pixel screen build | 633.64 ms | 295.14 ms |
| Frame callback median | 16.77 ms | 16.77 ms |
| Frame callback p95 | 16.90 ms | 16.88 ms |
| Samples after warmup | 300 | 300 |
| Trace checksum | `299be1005ac7cc21` | `299be1005ac7cc21` |

The warm run was not consistently faster for process launch. Treat that spread as run-to-run noise, not a cache regression or improvement. The cold resize difference is more consistent with the exact-size BMP work, but one local pair is not a stable threshold.

## Diagnostics versus repeatable results

The table above is the checked-in baseline. It uses fixed fixtures, fixed sample counts, explicit cache controls, checksums, and recorded build and hardware state.

Earlier syscall tracing from issue #15 is diagnostic only. It recorded about 15 ms to Wayland connection, about 324 ms to a warm checkerboard resource access, and about 1.28 seconds to a cold full-window checkerboard write with a 1916x2094 window. Tracing changed scheduling and I/O cost, so those values are not benchmark samples and are not pass/fail gates.

The following remain targets rather than guarantees:

- Sub-10 ms complete process startup
- 60 FPS at 3840x2160
- p95 presented-frame time below 16.7 ms
- 8.3 ms frame headroom

The current live harness cannot prove presented-frame GPU time. A later resource or renderer change can add a backend fence or GPU timestamp without changing the fixture, statistics, build, hardware, or checksum reporting contract.
