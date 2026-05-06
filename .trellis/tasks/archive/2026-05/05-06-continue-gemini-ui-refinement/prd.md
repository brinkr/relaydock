# Continue Gemini UI Refinement

## Goal

Complete the reasonable Gemini UI review items that were not finished in the previous UI density task. Keep the work scoped to native SwiftUI/AppKit shell polish and visual QA reliability so RelayDock continues moving toward a dense macOS port-forwarding workbench without changing Rust core behavior.

## What I Already Know

- Previous Gemini review correctly identified remaining native UI gaps: sidebar source-list feel, Logs/Preferences density, and screenshot QA reliability.
- The prior task already removed the stale SwiftUI toolbar, tightened Run/Recovery and Registry rows, and replaced several opacity-heavy shell tokens.
- Current shell specs require source-list style sidebar, AppKit toolbar, bottom status bar, dense diagnostic workspace, narrow native preferences, and visual QA inspection.
- `SidebarView`, `LogsAndDiagnosticsView`, and `PreferencesView` still contain hand-rolled source-list rows and some opacity-heavy surfaces.
- `scripts/visual-qa/relaydock-window-snapshot.sh` can locate and launch the temporary app, but macOS Screen Recording failures currently stop without preserving enough state for quick manual inspection unless the caller sets `RELAYDOCK_VISUAL_QA_KEEP_OPEN=1`.

## Assumptions

- Do not change Rust core, bridge contracts, storage, provider behavior, or mock/demo data flow.
- SwiftUI remains the main declarative view layer; AppKit remains responsible for the window toolbar/titlebar.
- This task should improve the existing native UI rather than redesigning all pages.
- Visual QA script changes should improve diagnostics and manual fallback without weakening screenshot quality checks.

## Requirements

- Make the main sidebar feel more like a macOS source list:
  - tighter row rhythm
  - stable icon/title alignment
  - accessible labels
  - native color/material tokens rather than extra opacity
- Tighten Logs/Diagnostics without inventing provider streaming logs:
  - keep left scope list, center console, right inspector
  - stabilize diagnostic row columns and truncate where appropriate
  - remove remaining persistent opacity-heavy panel surfaces where a shared token works
- Tighten Preferences without fake persistence:
  - keep left section list and right detail pane
  - compact row spacing and align title/value/detail columns
  - preserve copy that clearly states session-local / not-yet-persisted behavior
- Improve visual QA script usability:
  - keep failing on black or invalid screenshots
  - when Screen Recording prevents capture, provide the launched app bundle/pid/window rect if available
  - allow a documented keep-open fallback for manual/Computer Use inspection
- Preserve all callbacks and state ownership boundaries.

## Acceptance Criteria

- [ ] Changes are limited to Swift shell/design-system/visual-QA script/spec/task files.
- [ ] `swift build` passes.
- [ ] `git diff --check` passes.
- [ ] Visual QA script either captures a valid screenshot or fails with actionable app/pid/window information and a keep-open hint.
- [ ] Main sidebar, Logs, and Preferences no longer add persistent opacity-heavy sidebar/panel backgrounds.
- [ ] No Rust core, bridge, storage, provider, or demo/mock data files are modified.

## Out Of Scope

- New provider diagnostics or streaming logs.
- Real settings persistence.
- Replacing SwiftUI views with AppKit table/source-list implementations.
- Changing runtime/recovery data source or reintroducing hardcoded demo rows.
- Large LocalPort clone-style redesign.

## Technical Notes

- Relevant files:
  - `apps/relaydock/Sources/Shell/SidebarView.swift`
  - `apps/relaydock/Sources/Features/LogsAndDiagnostics/LogsAndDiagnosticsView.swift`
  - `apps/relaydock/Sources/Features/Preferences/PreferencesView.swift`
  - `apps/relaydock/Sources/DesignSystem/RelayDockColor.swift`
  - `scripts/visual-qa/relaydock-window-snapshot.sh`
- Relevant specs:
  - `.trellis/spec/swift-shell/index.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
  - `.trellis/spec/swift-shell/quality-guidelines.md`
  - `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  - `.trellis/spec/project/product-constraints.md`
  - `.trellis/spec/project/commit-guidelines.md`
