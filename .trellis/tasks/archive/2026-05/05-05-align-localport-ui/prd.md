# Align RelayDock UI with LocalPort prototype

## Goal

Bring RelayDock's current native SwiftUI/AppKit UI closer to the LocalPort prototype's information architecture, visual density, and interaction semantics while preserving RelayDock's confirmed implementation architecture: `SwiftUI + AppKit shell + Rust core`.

LocalPort is a reference for layout and density only. RelayDock must not copy its React/Tailwind structure or become a web-style dashboard.

## What I Already Know

- The user supplied the live LocalPort prototype URL as the visual reference: `https://ais-dev-dlnvkb6ix5ivzfyzv74kyt-281326998829.us-east1.run.app/`.
- Chrome with the user's existing session can view the prototype directly; isolated Playwright may hit Google authentication and is not authoritative for this URL.
- LocalPort's `运行与恢复` screen shows a compact host-grouped runtime table with many services, statuses, telemetry values, provider labels, and row actions.
- LocalPort's `资源登记` screen shows a left host list, selected-host context header, launch presets, current-host rule filtering, import/new-rule actions, and dense rule rows.
- RelayDock currently has the native shell/titlebar direction mostly corrected, but its content still has too little density and too few demo domain states.
- RelayDock's current architecture is fixed in `documents/10-technology-stack-decision.md`: `SwiftUI + AppKit shell + Rust core`.
- Product docs already define LocalPort as a visual/information-density reference in `documents/11-localport-prototype-reference.md`.

## Requirements

- Preserve native macOS shell semantics: AppKit window/titlebar, SwiftUI sidebar/content/status bar, no WebView or fake web app shell.
- Keep user-facing copy Chinese-first.
- Improve `运行与恢复` so the first visible screen resembles the prototype's density:
  - host-grouped list
  - multiple service rows under a host
  - connected, reconnecting, error, and recoverable states
  - compact two-line row layout
  - right-aligned provider, telemetry, and row actions
  - separate destructive actions such as stopping runtime and clearing recovery items
- Improve `资源登记` so it has the same major information architecture as the prototype:
  - left host/resource group list with many hosts
  - selected-host context header
  - launch preset summary
  - current-host rule filter and import/new-rule commands
  - dense rule rows with provider labels and actions
- Keep Rust core responsible for structured demo/domain snapshots and Swift responsible for native layout and UI state.
- Add deterministic sample data only as a development/demo bridge snapshot, not as hardcoded UI-only state that bypasses the bridge.
- Verify with build/test commands and visual screenshots after implementation.

## Acceptance Criteria

- [ ] `运行与恢复` screenshot shows at least one expanded host group with 7+ visible service rows and multiple runtime states.
- [ ] `运行与恢复` keeps explicit row actions: running rows can stop/retry where appropriate, recoverable rows can recover/change local port/clear.
- [ ] `资源登记` screenshot shows a host list with many host entries and a selected-host detail pane with presets plus rule list.
- [ ] Toolbar/titlebar remains native and does not regress into the earlier oversized titlebar issue.
- [ ] Rust tests pass and cover any expanded demo snapshot behavior where practical.
- [ ] Swift build passes.
- [ ] Visual QA produces fresh screenshots for at least `运行与恢复` and `资源登记`.

## Out of Scope

- Full SSH/Tailscale provider implementation.
- Real persistence-backed registry editing.
- Full import-SSH modal behavior.
- Copying LocalPort React/Tailwind code or component structure.
- Switching to Tauri/React/Go or any WebView-based UI.

## Technical Notes

- Relevant RelayDock files likely include:
  - `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - `crates/relaydock-core/src/commands.rs`
  - `scripts/visual-qa/relaydock-window-snapshot.sh`
- Relevant LocalPort reference files:
  - `/Users/workspace/LocalPort/src/views/ForwardsView.tsx`
  - `/Users/workspace/LocalPort/src/views/RegistryView.tsx`
  - `/Users/workspace/LocalPort/src/components/TopBar.tsx`
  - `/Users/workspace/LocalPort/src/components/Sidebar.tsx`
  - `/Users/workspace/LocalPort/src/components/StatusBar.tsx`
  - `/Users/workspace/LocalPort/src/data.ts`
- First implementation should favor deterministic UI/data parity and visual QA over deep behavior expansion.
