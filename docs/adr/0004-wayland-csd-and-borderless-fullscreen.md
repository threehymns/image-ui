# 4. Wayland CSD Protocol and Hidden CSD Support

## Context
On modern Linux desktop environments running Wayland (such as GNOME Mutter and wlroots-based compositors), window decoration negotiation varies: some force Client-Side Decorations (CSD), while others negotiate Server-Side Decorations (SSD) via `zxdg_decoration_manager_v1`. In a dedicated image viewer, displaying an unremovable compositor title bar conflicts with immersive edge-to-edge viewing, borderless windowing, and fullscreen auto-hiding headers.

## Decision
We configure the windowing layer to explicitly support the Wayland CSD protocol (`zxdg_decoration_manager_v1_mode_client_side`). The top control bar doubles as the integrated client-side headerbar (supporting window dragging and window controls when SSD is unavailable), and cleanly unsets decorations or transitions through `xdg_toplevel_set_fullscreen` when entering borderless or fullscreen modes so CSDs are completely hidden.

## Consequences
- Prevents redundant, double titlebars on GNOME/Sway/KDE Wayland sessions.
- Allows the top bar to auto-hide cleanly without leaving an orphan system bar in fullscreen.
- Requires coordinating window drag/close gestures with the display server when native SSD is disabled.
