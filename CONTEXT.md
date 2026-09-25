# Image UI

A fast, lightweight desktop image viewer system application built with V and V UI.

## Language

**Viewer**:
The application window and orchestration layer responsible for displaying an image and coordinating user interactions.
_Avoid_: Editor, photo manager, catalog

**Canvas**:
The interactive rendering surface where the image is drawn using direct graphics context calls.
_Avoid_: Picture box, image widget, drawing area

**Viewport**:
The visible coordinate frame and transformation state (zoom scale, pan offsets, rotation, flip) mapping image space to screen space.
_Avoid_: Camera, window frame, view bounds

**Sibling**:
An image file located within the same directory as the active image that can be traversed sequentially.
_Avoid_: adjacent picture

**Filmstrip**:
The collapsible row of thumbnails representing sibling images for direct random-access navigation.
_Avoid_: Photo reel, bottom bar, carousel

**Transform**:
A non-destructive geometric adjustment (pan, zoom, 90-degree step rotation, horizontal/vertical flip) applied in the viewport.
_Avoid_: Edit, modification, filter

**Neighborhood**:
The localized sliding window of adjacent sibling images scanned with highest priority to guarantee zero-TTI navigation.
_Avoid_: Buffer, chunk, cluster

**Lock Viewport**:
An operational mode that maintains exact zoom magnification and pan coordinates across sibling image transitions.
_Avoid_: Freeze view, pin zoom, sticky scale

**Thumbnail Cache**:
A bounded, LRU in-memory store of low-resolution downscaled preview textures used exclusively by the filmstrip.
_Avoid_: Image pool, texture store, icon cache

**Sibling Resource Cache**:
A byte-bounded, LRU-managed store of decoded full-resolution resources for the current image and discovered nearby Siblings.
_Avoid_: Thumbnail Cache, Filmstrip Cache, image pool

**Fit to Window**:
A viewport calculation that scales and centers an image to maximally fill the canvas while preserving aspect ratio.
_Avoid_: Best fit, auto scale, letterbox mode

**Actual Size**:
A viewport calculation setting zoom magnification to exactly 1:1 (one image pixel to one physical display pixel).
_Avoid_: 100% view, original size, unscaled

**Decoration**:
System window frame elements (title bar, borders, window controls) negotiated with the desktop display server.
_Avoid_: Window border, chrome frame

**CSD**:
Client-side decorations rendered within the application surface complying with Wayland protocols (`zxdg_decoration_manager_v1`).
_Avoid_: App titlebar, custom chrome

**Trash**:
The recoverable desktop file discard facility accessed via platform specifications (`gio trash` / FreeDesktop Trash).
_Avoid_: Recycle bin, discard folder, delete queue

**Error Card**:
An in-viewport graphic and textual state displaying file decoding failures without disrupting the sibling playlist.
_Avoid_: Error dialog, alert box, crash popup

**Slideshow**:
An automated playback mode advancing sequentially through sibling images on a timed interval with interactive pause.
_Avoid_: Auto play, presentation mode

**Icon**:
A scalable vector graphic (SVG) asset rendered to pixels for user interface controls.
_Avoid_: Emoji, unicode symbol, glyph character

**FreeDesktop Integration**:
Desktop environment registration adhering to XDG specifications for application shortcuts, MIME types, and icons.
_Avoid_: Linux installer, launcher script
