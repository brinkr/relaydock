# Swift Shell Directory Structure

The first native app shell is a Swift Package executable rooted at:

- `Package.swift`
- `apps/relaydock/Sources/`

Current app shape:

- `App/` for app entry, scene setup, menu commands, app lifecycle
- `Shell/` for main window, sidebar/source list, toolbar, status bar
- `Features/RunAndRecovery/`
- `Features/Registry/`
- `Features/LogsAndDiagnostics/`
- `Features/Preferences/`
- `DesignSystem/` for native style tokens, icons, row components, status indicators

Planned app directories:

- `Platform/` for AppKit adapters, Keychain, LaunchAgent, file panels, notifications
- `Bridge/` for Swift wrappers around Rust FFI or command boundary

Rules:

- Do not mirror the LocalPort React component tree.
- Do not create web-style `pages`, `hooks`, or `components` directories.
- Keep platform integrations out of feature views unless the integration is view-specific.
