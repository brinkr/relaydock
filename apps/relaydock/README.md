# RelayDock macOS Shell

Native macOS application shell for RelayDock.

This target is intentionally named `relaydock` / `RelayDock`. `LocalPort` is only
the historical React prototype used for style and interaction-density reference.

Current scope:

- AppKit application lifecycle
- SwiftUI main window content
- source-list sidebar
- contextual toolbar row
- bottom status bar
- placeholder pages for the four confirmed product areas

Out of scope:

- Rust bridge
- provider runtime execution
- persistence
- SSH/Tailscale orchestration
