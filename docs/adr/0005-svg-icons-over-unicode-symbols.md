# 5. SVG Vector Icons Over Unicode/Emoji Symbols

## Context
User interface toolbars in desktop applications often attempt to use unicode characters or emojis (e.g. ⟲, ⟳, 🔍, 🎞, ⛶) for action buttons. However, emojis render inconsistently across Linux distributions, vary with installed system fonts (or render as unstyled monochrome wireframes or missing glyph tofu blocks), cannot be recolored cleanly to match UI themes, and look pixelated or blurry at high-DPI scaling factors.

## Decision
All user interface controls, buttons, status indicators, and actions strictly use dedicated SVG vector icons, rendered crisp at target device scale. The use of emojis or unicode character symbols for interface iconography is strictly prohibited.

## Consequences
- Guaranteed consistent, razor-sharp rendering on all platforms and HiDPI scales.
- Clean theming and color styling consistent with the application aesthetic.
- Requires embedding or bundling SVG assets or generating rasterized vector textures at runtime.
