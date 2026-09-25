# Viewer performance benchmarks

The root benchmark suite measures the current Viewer path, including asynchronous image resources, the background scanner, the byte-bounded Sibling resource cache, the cached transparency tile, Neighborhood prefetch, deterministic key-repeat simulations, startup phase tracing, and separate transparent/opaque 3840x2160 pan and zoom rows. Every row reports fixed warmup/iteration counts, a returned-value checksum, decode counts, cache accounting, prefetch behavior, and counter checks. CI compiles it and runs correctness tests, but hosted runners do not enforce wall-clock thresholds.

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
make benchmark BENCHMARK_ARGS="--cache-budget 67108864"
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

The live command needs a Wayland socket plus `niri`, `jq`, and `wtype`. It exits with a clear skipped message when those requirements are absent. The script restores the previously focused window on exit and sends a deterministic sustained Left/Right sequence; `IMAGE_UI_BENCHMARK_REPEAT_KEYS` controls the number of keys in each direction.

Native contract commands for the matching host are:

```bash
./benchmarks/native_contract_check.sh --commands
./benchmarks/native_contract_check.sh
```

On Linux the runner executes Linux checks and explicitly does not claim AppKit, UIKit, or Windows visual runs.

## Fixtures

`make benchmark` generates all fixtures in a temporary directory and removes them after the run. Generation uses fixed dimensions, fixed pixel formulas, and fixed file names.

| Fixture | Size | Purpose |
| --- | --- | --- |
| `alpha.tga` | 64x64 | Four deterministic alpha levels |
| `opaque.bmp` | 96x64 | Small opaque image decode |
| `large-4k.bmp` | 3840x2160 | 4K-class metadata decode and live rendering |
| `large-4k-previous.bmp` | 3840x2160 | 4K immediate previous Sibling |
| `large-4k_next.bmp` | 3840x2160 | 4K immediate next Sibling |
| `siblings/sibling-000.bmp` through `sibling-127.bmp` | 96x64 each | Directory discovery and adjacent navigation |

The 128 Sibling entries are hard links to the opaque fixture. They have independent paths for natural sorting and navigation without consuming 128 copies of the image. The two 4K Neighbor files are hard links to the 4K fixture, so the live target has a full-resolution previous and next Sibling. A user-supplied fixture directory is preserved; the suite only replaces its reserved `alpha.tga`, `opaque.bmp`, `large-4k*.bmp`, and `sibling-*.bmp` files.

## Headless measurements

The headless binary never calls `ui2.run_window`. It can therefore run on a machine with no display server.

| Case | What the timer covers |
| --- | --- |
| `image_load_alpha`, `image_load_opaque`, `image_load_4k` | File read, `stbi` metadata decode, and decode free through the production `load_image_metadata` seam; each row reports one decoder invocation |
| `sibling_cache_cold`, `sibling_cache_warm` | Full-resolution decode, signature capture, cache insertion, and resident lookup at the selected byte budget |
| `sibling_cache_4k_cold`, `sibling_cache_4k_warm` | The same cache path with the 4K fixture and a 256 MiB budget |
| `sibling_cache_invalidation` | A changed file signature removes the resident entry and reports the invalidation/miss behavior |
| `sibling_discovery` | Spawn, complete directory enumeration, natural sort, channel batches, and final batch through the current scanner |
| `sibling_navigation` | Playlist step plus the current synchronous metadata decode |
| `resident_sibling_switch` | One resident small-Sibling switch from key event through cache lookup, commit, and screen construction |
| `resident_sibling_switch_4k` | One resident 3840x2160 Sibling switch through cache lookup, commit, and screen construction; decode setup is outside the timer |
| `key_repeat_resident_right`, `key_repeat_resident_left` | Deterministic 16-key resident sequences that verify every available Sibling is displayed in order |
| `sustained_key_repeat_right`, `sustained_key_repeat_left` | Named sustained Left/Right repeat rows using the same resident-resource sequence and checksum contract |
| `key_repeat_faster_than_decode` | Deterministic 100-key burst with manual completions proving bounded pending work and latest-request-wins |
| `frame_prepare_4k` | Legacy combined zoom/pan and 4K screen-element construction row |
| `pan_4k_transparent`, `pan_4k_opaque` | Separate 3840x2160 pan construction rows with alpha-present and proven-opaque resource states |
| `zoom_4k_transparent`, `zoom_4k_opaque` | Separate 3840x2160 zoom construction rows with alpha-present and proven-opaque resource states |
| `toggle_checkerboard_4k` | 4K checkerboard visibility toggle and screen reconstruction |
| `pattern_tile` | Creation of the 32x32 logical repeat tile containing 16 px cells |
| `screen_construct_4k` | Current UI2 element construction and repeat-tile reuse |
| `screen_resize_to_4k` | Three screen builds needed to move from 1920x1080 to 3840x2160 |
| `startup_cpu_cold`, `startup_cpu_warm` | Labeled CPU startup-path rows: `new_app`, 4K metadata decode, state setup, and 1024x768 screen construction; neither is process-launch time |

`screen_construct_4k`, the four `pan_4k_*`/`zoom_4k_*` rows, `frame_prepare_4k`, and `toggle_checkerboard_4k` stop before GPU submission. They are CPU and element-construction measurements, not rendered-frame measurements. The resident-switch rows likewise measure the state transition and UI2 element construction; their fixture decode and cache population happen before the stopwatch starts and are identified separately from measured decode counters.

Every row includes warmup count, fixed measured iteration count, cache label, byte budget, median, p95, decode and prefetch-decode counts, cache hits/misses/updates/evictions/invalidations, resident/peak/CPU/renderer bytes, and a returned-value checksum. The `requested`, `displayed`, `skipped`, and `coalesced` columns count user Sibling requests. The prefetch columns count Neighborhood candidates, accepted full-resolution cache insertions, skips, coalescing, and cancellation. `checksum samples` and `checksum mismatches` make the fixed-iteration verification explicit. A checksum or counter mismatch fails the command. CI compiles the benchmark and runs correctness tests but does not run timing thresholds.

### Startup phase trace

The headless suite also emits a phase-order smoke table with monotonic timestamps for process launch, window creation, font work, UI2 setup, GPU setup, first content, first input, and directory completion. It validates the ordering seam without claiming to measure a real process launch or GPU present. The live suite records the same phase names from the running Viewer process. Font discovery, metrics, and symbol fallback preparation are scheduled after context creation and run in the background; the first-content mark is emitted only after an image resource is ready and the completed UI2 frame callback.

## Cache controls

`--cache cold`, `--cache warm`, and `--cache both` select which screen and Sibling-cache cases are run. `--cache-budget` replaces the default 16 KiB, 32 KiB, and 64 KiB Sibling-cache budgets with one byte value. The transparency background is a logical repeat tile and has no file cache.

- Pattern rows reuse the same 32x32 tile and do not allocate a window-sized raster.
- `sibling-lru` rows use the full-resolution Sibling resource cache. Their resident-byte totals include decoded CPU bytes and renderer bytes exposed by the production resource path.
- The Filmstrip Thumbnail Cache remains separate under ADR-0003. No Filmstrip rows are included in the Sibling-cache measurements.
- Live cold and warm labels describe separate process runs; they do not control a checkerboard file.

## Sibling Resource Cache baseline

The following rows were recorded on 2026-09-25 from commit `2defcde3dbe4` with 2 warmups and 10 measured iterations. The warm rows prefill the cache before starting the timer, so their timer covers signature validation and resident lookup. Byte totals include decoded CPU bytes and renderer bytes.

| Case | Budget | Median ms | p95 ms | Hits | Misses | Updates | Evictions | Resident bytes | Checksum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `sibling_cache_cold`, opaque | 16 KiB | 0.26 | 0.26 | 0 | 0 | 0 | 0 | 0 | `3e3b230aed0713ef` |
| `sibling_cache_warm`, opaque | 16 KiB | 0.00 | 0.00 | 0 | 1 | 0 | 0 | 0 | `300000005190` |
| `sibling_cache_cold`, opaque | 32 KiB | 0.23 | 0.24 | 0 | 0 | 0 | 0 | 0 | `3e3b230aed0713ef` |
| `sibling_cache_warm`, opaque | 32 KiB | 0.00 | 0.00 | 0 | 1 | 0 | 0 | 0 | `300000005190` |
| `sibling_cache_cold`, opaque | 64 KiB | 0.23 | 0.27 | 0 | 0 | 0 | 0 | 49,152 | `3e3b220aed07123c` |
| `sibling_cache_warm`, opaque | 64 KiB | 0.00 | 0.00 | 1 | 0 | 0 | 0 | 49,152 | `3e3b220aed07123c` |
| `sibling_cache_4k_cold`, large-4k | 256 MiB | 320.44 | 340.72 | 0 | 0 | 0 | 0 | 66,355,200 | `84f927381687d2bf` |
| `sibling_cache_4k_warm`, large-4k | 256 MiB | 0.00 | 0.00 | 1 | 0 | 0 | 0 | 66,355,200 | `84f927381687d2bf` |

The 16 KiB and 32 KiB opaque rows reject the 49,152-byte decoded-plus-renderer entry. The 64 KiB row retains it. The 4K row retains 33,177,600 CPU bytes plus 33,177,600 renderer bytes. The Filmstrip Thumbnail Cache is not part of these totals.

## Neighborhood prefetch and key-repeat baseline

The following repeatable headless rows were recorded on 2026-09-25 from commit `07702405e4b7` with `make benchmark`: two warmups, 10 measured iterations, both cache states, and the default 256 MiB full-resolution budget for the 4K row. The machine was the available Linux 7.1.8-arch1-3 x86_64 host with an Intel Core i7-8565U, 8 logical CPUs, 32,628,928 kB RAM, and `i915`; the V toolchain was 0.5.2 (`26fdab8`) with GCC 16.2.1.

| Case | Median ms | p95 ms | User requested/displayed/skipped/coalesced | Prefetch requested/prefetched/skipped/coalesced | Max user/total pending | Checksum |
| --- | ---: | ---: | --- | --- | --- | --- |
| `resident_sibling_switch`, small | 0.05 | 0.06 | 1/1/0/0 | 6/0/6/0 | 1/1 | `569416a912307dc6` |
| `resident_sibling_switch_4k`, 3840x2160 | 0.06 | 0.07 | 1/1/0/0 | 6/0/6/0 | 1/1 | `9792aa42137fcab5` |
| `key_repeat_resident_right`, 16 Siblings | 3.20 | 3.29 | 16/16/0/0 | 98/0/97/0 | 1/3 | `bde78c5b4a61bd17` |
| `key_repeat_resident_left`, 16 Siblings | 3.23 | 3.56 | 16/16/0/0 | 97/0/97/16 | 1/3 | `695b4adc8cb6062a` |
| `key_repeat_faster_than_decode`, 100 inputs | 5.25 | 5.33 | 100/1/99/98 | 600/0/598/196 | 2/5 | `e663f69a84b792e5` |

The 4K resident-switch row keeps two 4K resources resident: 132,710,400 bytes of decoded CPU plus renderer accounting under a 268,435,456-byte budget. The row measures cache lookup, request generation, latest-request commit, and 3840x2160 UI2 element construction; it does not measure a decode or GPU presentation. The resident key-repeat rows prefill the cache before timing, and the faster-than-decode row uses manual completions so correctness does not depend on sleeps or wall-clock thresholds. In the resident rows, prefetched is zero because every candidate was already resident; the live run below records actual prefetch insertions.

## Live Wayland smoke

Each live run starts the benchmark build with the 4K image fixture, waits for the first content screen, complete directory scan, and a `prefetch_cached` event for the next Sibling, then asks niri to resize the focused tiled window. The report uses the actual measured viewport; a 3840-pixel width without a 2160-pixel height is not 4K evidence. The run collects 360 frame callbacks, discards the first 60 as warmup, and reports median and p95 for the remaining 300. It records cold/warm process launches, first content, first input, resize, toggle, resident switch, pan, zoom, sustained Left/Right input, frame cadence, decode counts, cache metrics, and prefetch counters.

The harness sends real Wayland key input through `wtype` and verifies each action before the next run:

- `t` toggles the checkerboard.
- `Right` switches to the next Sibling.
- `p` is available only in the benchmark build and calls the current `App.pan` path.
- `z` is available only in the benchmark build and calls the current `App.zoom_in` path.

The trace reports process launch to first content, process launch to the harness's first input, separate monotonic startup-phase timestamps, each input-to-next-screen-build interval, compositor resize request to the 3840-pixel resize observation, frame-callback cadence, user Sibling counters, sustained Left/Right input counts, Neighborhood prefetch counters, decode counts, cache hit/miss/update/eviction/invalidation counters, cache byte budgets, and a trace checksum. The first-content mark is tied to a ready image resource rather than the initial empty/drop-target frame.

The cadence and `switch_to_frame` values are intervals between Viewer `build_screen` callbacks. UI2 does not expose a post-present fence or GPU timestamp, so these values do not prove when the compositor presented the frame. The live report prints `viewport_exact_3840x2160`, `post_present_fence`, and `target_4k60` explicitly; a false exact-viewport result or unavailable fence is a limitation, not a pass.

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

### Live Wayland #21 evidence

The following cold and warm runs were recorded on 2026-09-25 from commit `07702405e4b7` with `make benchmark-wayland`, 60 warmup frames, 360 total frames, and the same Intel Core i7-8565U / `i915` niri host. The harness observed the next 4K Sibling in the prefetch trace before sending Right.

| Measurement | Cold process | Warm process |
| --- | ---: | ---: |
| Measured viewport | 3840x2094 | 3840x2094 |
| Process launch to first content | 998.06 ms | 1231.02 ms |
| Process launch to harness first input | 1251.57 ms | 1466.63 ms |
| Toggle to screen build | 0.30 ms | 0.16 ms |
| Resident Sibling switch to screen build | 1.54 ms | 1.55 ms |
| Pan to screen build | 0.82 ms | 0.17 ms |
| Zoom to screen build | 0.20 ms | 0.32 ms |
| Resize request to measured-width screen build | 24.31 ms | 26.77 ms |
| Frame callback median | 16.78 ms | 16.78 ms |
| Frame callback p95 | 16.87 ms | 16.89 ms |
| User requested/displayed/skipped/coalesced | 2/2/0/0 | 2/2/0/0 |
| Prefetch requested/prefetched/skipped/coalesced | 9/3/6/0 | 9/3/6/0 |
| Prefetch cached events | 3 | 3 |
| Samples after warmup | 300 | 300 |
| Trace checksum | `e9cfcab7b65f4077` | `e9cfcab7b65f4077` |

The live viewport is 3840x2094 because the available compositor/window configuration reserves 66 vertical pixels; the image fixture itself is 3840x2160. The switch and frame values are build-callback measurements, not post-present GPU timestamps. This host therefore cannot provide a true 3840x2160 presented-frame claim, and the one-frame target remains a target for the cross-backend #26 integration work. The headless 3840x2160 resident-switch row is CPU/screen-construction evidence only.

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

## Final #26 validation report

Validation source: the `t3code/15-integration` branch with UI2 submodule `e740b6b09d8a`; each benchmark’s build output records the exact commit. All timing thresholds remain reporting-only in hosted CI. The final report is intentionally split into measured evidence, targets, and unverified platform work.

### Commands and evidence

| Check | Command | Result |
| --- | --- | --- |
| Root correctness | `make test` | 16 test files passed, including deterministic checkerboard phase/clipping, alpha reference compositing, resize, transform, decode-count, cache-invalidation, and repeat coverage |
| Root build | `make build` and `make build-wayland` | Passed on the Linux host |
| Headless benchmark | `make benchmark BENCHMARK_ARGS="--warmup 2 --iterations 10 --cache both"` | Passed; fixed-iteration checksum and counter status was `ok` for every row |
| Benchmark compile | `make benchmark-build` | Passed |
| Live Wayland | `make benchmark-wayland` | Passed cold and warm niri runs; evidence below |
| Linux UI2 checks | `make -C ui2 check-linux` | Passed |
| Focused UI2 contracts | `v test ui2/ui/image_resource_test.v ui2/ui/repeat_pattern_test.v` | 2 passed |
| UI2 cross source checks | `make -C ui2 check-macos check-ios check-android check-windows` | Passed |
| Custom cross checks | `make -C ui2 check-custom-macos check-custom-windows` | Blocked by stale `ui_custom_test.v` calls to the two-argument `handle_key_down`; no Viewer contract source error was reported |
| Native contract inventory | `./benchmarks/native_contract_check.sh --commands` | Printed runnable AppKit, UIKit, Windows, and Linux commands |
| Shell validation | `shellcheck benchmarks/wayland_smoke.sh benchmarks/native_contract_check.sh` | Passed after fixing the `CDPATH` assignment warning |

The root benchmark includes separate `pan_4k_transparent`, `pan_4k_opaque`, `zoom_4k_transparent`, and `zoom_4k_opaque` rows. Those rows measure Viewer/UI2 element construction at 3840x2160, not GPU presentation. The `decodes` and `prefetch decodes` columns count decoder invocations; cache hits and prefetched resources do not increment them. The cache columns expose hits, misses, updates, evictions, invalidations, resident/peak bytes, CPU/renderer bytes, and the configured budget. `checksum samples` equals the configured measured iteration count and `checksum mismatches` is zero for a passing row.

### Live Wayland evidence

| Measurement | Cold process | Warm process |
| --- | ---: | ---: |
| Measured viewport | 3840x2094 | 3840x2094 |
| Process launch to first content | 846.23 ms | 1221.77 ms |
| Process launch to first input | 1136.29 ms | 1489.33 ms |
| Toggle to screen build | 0.16 ms | 0.19 ms |
| Resident Sibling switch to screen build | 0.19 ms | 0.29 ms |
| Pan to screen build | 0.89 ms | 0.21 ms |
| Zoom to screen build | 0.31 ms | 0.55 ms |
| Resize request to measured-width screen build | 26.18 ms | 27.99 ms |
| Frame callback median | 16.78 ms | 16.78 ms |
| Frame callback p95 | 16.89 ms | 16.94 ms |
| Decode count / prefetch decode count | 2 / 4 | 2 / 4 |
| User requested / displayed / skipped / coalesced | 17 / 5 / 12 / 11 | 17 / 5 / 12 / 11 |
| Prefetch requested / prefetched / skipped / coalesced / cancelled | 85 / 2 / 83 / 4 / 11 | 85 / 2 / 83 / 4 / 11 |
| Prefetch cached events | 2 | 2 |
| Cache hits / misses / evictions / invalidations | 27 / 10 / 0 / 0 | 27 / 10 / 0 / 0 |
| Cache resident / peak / budget bytes | 199,114,752 / 199,114,752 / 268,435,456 | 199,114,752 / 199,114,752 / 268,435,456 |
| Sustained Left / Right input events | 8 / 8 | 8 / 8 |
| Samples after warmup | 300 | 300 |
| Trace checksum | `d5ba15f0ab240e98` | `d5ba15f0ab240e98` |

The niri host exposes a 3840x2160 physical eDP mode, but the measured Viewer viewport is 3840x2094 because the compositor/window configuration reserves 66 vertical pixels. UI2 exposes no post-present fence or GPU timestamp. Consequently these results are build-callback cadence and action-to-build evidence only. The 4K60 p95 target and 8.3 ms headroom goal are **not claimed as passed**.

### Acceptance audit and platform gaps

- Generic UI2 `ImageResource`/`RepeatPattern` contracts, the Viewer’s single non-platform-branched path, legacy path retention, cache/decode instrumentation, transparent/opaque transform rows, repeat rows, startup phases, and deterministic semantic tests are covered.
- AppKit, UIKit, and Windows source/contract tests are present in UI2 and their runnable commands are listed above, but native runtime builds and screenshots were not run on this Linux host. The non-custom macOS, iOS, Android, and Windows source checks pass; custom macOS/Windows checks are blocked by the stale two-call `handle_key_down` test calls, and the custom example build is blocked by the existing V script’s `string.join` usage. Windows/Linux cross-build availability is therefore a source/toolchain check, not a native visual pass.
- The legacy path remains documented because native runtime/visual verification is incomplete; removing it would weaken supported-backend compatibility.
- The 4K60 target requires a future exact 3840x2160 viewport and post-present fence measurement. The current checked-in evidence does not satisfy that hardware/fence prerequisite.
