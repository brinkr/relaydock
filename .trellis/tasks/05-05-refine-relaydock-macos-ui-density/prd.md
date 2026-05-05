# Refine RelayDock macOS UI Density

## Goal

Improve the current RelayDock SwiftUI/AppKit shell so the app feels like a dense, native macOS port-forwarding workbench instead of a loose generic SwiftUI page. Use the Gemini frontend expert as a patch-planning reviewer, then apply only scoped UI refinements that preserve the established SwiftUI + AppKit shell + Rust core architecture.

## What I Already Know

- The project technology choice is SwiftUI + AppKit shell + Rust core.
- RelayDock is Chinese-first and should feel like a local-first macOS engineering tool.
- LocalPort is a visual density and interaction reference only; do not copy its implementation stack.
- Existing Swift shell specs require source-list style sidebar, contextual top toolbar, bottom status bar, sheets/popovers for focused edits, and compact runtime rows.
- `ToolbarView.swift` appears to be a stale SwiftUI toolbar implementation while the real shell uses AppKit `NSToolbar` from `RelayDockWindowController.swift`.
- Previous Gemini analysis found the current UI too loose, opacity-heavy, and not native enough.
- The first improvement should focus on shell consistency, run/recovery row density, registry detail density, and design token hygiene.

## Assumptions

- This task should not change Rust core behavior or bridge contracts.
- This task should not introduce WebView, Tauri, React, Electron, or another UI stack.
- It is acceptable to remove unused SwiftUI UI remnants if they are not part of the current rendered shell.
- Screenshots are useful for later verification, but the patch proposal should be code-driven first per the current user request.

## Requirements

- Keep the UI native macOS and SwiftUI/AppKit-based.
- Preserve the existing page structure:
  - `运行与恢复`
  - `资源登记`
  - `日志与诊断`
  - `偏好设置`
- Improve run/recovery scanability by making host groups and service rows more column-stable and compact.
- Improve registry density without turning it into a second runtime console.
- Clean up toolbar direction so there is one source of truth for top-level commands.
- Reduce ad hoc opacity usage where a system color, material, or shared token is more appropriate.
- Keep destructive actions explicit and visually separated.
- Avoid broad redesigns, dashboard cards, hero sections, and marketing copy.

## Acceptance Criteria

- [ ] Gemini frontend expert returns a concrete patch proposal for the Swift shell UI.
- [ ] Applied changes are scoped to Swift shell/design-system files.
- [ ] `swift build` passes.
- [ ] The rendered app still opens as a native macOS window with AppKit toolbar and bottom status bar.
- [ ] Run/recovery rows are easier to scan, with stable alignment for status, ports, telemetry, and actions.
- [ ] Registry detail uses tighter spacing and clearer section rhythm.
- [ ] No Rust core, storage, or bridge behavior changes are introduced.

## Out Of Scope

- Implementing new provider behavior.
- Changing Rust domain logic.
- Adding persistence for settings.
- Rebuilding the full product visual language from scratch.
- Copying LocalPort code or changing the chosen architecture.

## Technical Notes

- Relevant Swift files:
  - `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
  - `apps/relaydock/Sources/Shell/SidebarView.swift`
  - `apps/relaydock/Sources/Shell/StatusBarView.swift`
  - `apps/relaydock/Sources/Shell/ToolbarView.swift`
  - `apps/relaydock/Sources/App/RelayDockWindowController.swift`
  - `apps/relaydock/Sources/DesignSystem/RelayDockColor.swift`
  - `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
- Relevant specs:
  - `.trellis/spec/swift-shell/index.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
  - `.trellis/spec/swift-shell/quality-guidelines.md`
  - `.trellis/spec/project/product-constraints.md`
