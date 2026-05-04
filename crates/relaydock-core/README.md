# relaydock-core

Reusable Rust core for RelayDock.

Current scope:

- domain identifiers and configuration objects
- runtime instance and recovery item state transitions
- local port binding, override, conflict, and allocation primitives
- SQLite-backed configuration, runtime snapshot, and recovery collection foundation

Out of scope for this crate stage:

- SwiftUI/AppKit UI
- Swift/Rust FFI bridge
- SSH/Tailscale process orchestration
