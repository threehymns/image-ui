# 2. Prioritized Neighborhood Sibling Scan

## Context
Default desktop image viewers frequently encounter folders with thousands of media files. Performing a synchronous directory traversal and natural sort blocks the UI thread and delays initial Time to Interactive (TTI). Conversely, not scanning prevents sibling traversal via arrow keys.

## Decision
We decouple initial image rendering from folder discovery. The target image is loaded and rendered immediately on the main thread. A background worker thread is spawned to first scan and resolve an immediate neighborhood (±50 files) around the target image and stream it via a V channel to unblock Left/Right arrow navigation within milliseconds, followed by streaming the remaining folder entries in progressive batches.

## Consequences
- Guaranteed sub-10ms UI startup regardless of folder size.
- Sibling navigation works immediately for adjacent photos.
- Requires thread-safe playlist indexing and progressive UI list updates.
