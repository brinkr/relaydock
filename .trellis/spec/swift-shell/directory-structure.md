# Swift Shell Directory Structure

The concrete Xcode project has not been created yet. Use this structure when introducing it unless a later task records a better native layout.

Recommended top-level app shape:

- `App/` for app entry, scene setup, menu commands, app lifecycle
- `Shell/` for main window, sidebar/source list, toolbar, status bar
- `Features/RunAndRecovery/`
- `Features/Registry/`
- `Features/LogsAndDiagnostics/`
- `Features/Preferences/`
- `Platform/` for AppKit adapters, Keychain, LaunchAgent, file panels, notifications
- `Bridge/` for Swift wrappers around Rust FFI or command boundary
- `DesignSystem/` for native style tokens, icons, row components, status indicators

Rules:

- Do not mirror the LocalPort React component tree.
- Do not create web-style `pages`, `hooks`, or `components` directories.
- Keep platform integrations out of feature views unless the integration is view-specific.
