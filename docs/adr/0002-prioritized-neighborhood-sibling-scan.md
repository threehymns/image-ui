# 2. Prioritized Neighborhood Sibling Scan

## Context
Default desktop image viewers frequently encounter folders with thousands of media files. Performing a synchronous directory traversal and natural sort blocks the UI thread and delays initial Time to Interactive (TTI). Conversely, not scanning prevents Sibling traversal via arrow keys.

## Decision
The Viewer decouples initial image rendering from folder discovery. A supplied target is sent to the content path before directory enumeration. A worker then calls the portable V `os.ls` source, filters supported images, and emits the first natural image for a directory launch. It computes a bounded natural Neighborhood around the target before sorting the complete path list, then emits one final playlist snapshot containing the complete natural order. The Viewer replaces its provisional playlist once when that snapshot arrives instead of repeatedly sorting and merging every batch on the UI thread.

V's portable `os` module exposes `os.ls`, but not a streaming directory iterator. A directory launch therefore cannot emit its first selected path until `os.ls` returns the directory entries. The worker keeps that limitation off the UI thread and makes the source and sorter seams deterministic for tests. A platform-specific Viewer branch is not used.

## Consequences
- Sub-10ms complete startup remains a target, not a guarantee. The checked-in benchmark measures process-to-first-content, first-input, directory-completion, and headless phase-order paths separately.
- Direct-target launches can begin content work before directory enumeration and natural sorting complete.
- Sibling navigation has a bounded natural Neighborhood before the complete playlist is sorted.
- The final playlist snapshot crosses a bounded channel, replaces the provisional playlist in one operation, and preserves the active Sibling by path. Stale generations are ignored.
- The UI thread accepts scanner batches only within a small per-frame count and monotonic time budget.
- Portable current-resource validation performs one bounded background file read at a bounded interval when higher-resolution modification data is unavailable; cache validation is not described as I/O-free.
