# Correct Prototype UI Style Drift

## Goal

Bring RelayDock's visible shell back toward the LocalPort prototype where the current implementation is plainly drifting: top titlebar rhythm, sidebar density, and run/recovery icon styling. The purpose is not to copy React/Tailwind or change the chosen stack; it is to translate the prototype's measured layout and icon language into the native SwiftUI + AppKit shell.

## What I Already Know

- The user marked three visible mismatches in the current screenshot:
  - the titlebar/top context bar appears too short and cramped;
  - left sidebar entries are too crowded vertically;
  - right content icons differ from the prototype's icon treatment.
- LocalPort is available locally at `/Users/workspace/LocalPort`.
- LocalPort remains only a visual/information-density reference. RelayDock remains SwiftUI + AppKit shell + Rust core.
- The previous recovery task removed the cross-window AppKit toolbar, but the shell still does not match the prototype closely enough.

## Requirements

- Titlebar/top context bar:
  - Match the LocalPort prototype's 52px titlebar rhythm.
  - Keep the content-pane top bar starting to the right of the sidebar.
  - Avoid visually collapsing the controls into the top edge.
  - Keep title icon, title text, search field, and page actions vertically centered and prototype-like.
- Sidebar:
  - Match the LocalPort source-list spacing more closely: 220px sidebar, 52px traffic-light/titlebar zone, grouped nav with visible breathing room, and approximately 30pt nav rows.
  - Use prototype-equivalent icon choices where SF Symbols has a close native equivalent.
  - Keep the selected row background and accent restrained.
- Run/recovery icon styling:
  - Stop using overly semantic SF Symbol service glyphs that do not exist in the prototype.
  - Use the prototype fallback style for services unless richer favicon/repoIcon data is available: 20pt rounded square, subtle border/background, uppercase first letter.
  - Keep row density close to the prototype while preserving stable right-side columns.
- Native implementation boundary:
  - Do not introduce React, Tailwind, WebView, Tauri, Electron, or Go.
  - Do not copy the LocalPort component tree as module architecture.

## Acceptance Criteria

- [x] LocalPort source evidence is recorded in `research/localport-style-audit.md`.
- [x] `运行与恢复` screenshot shows a 52pt-ish content top bar that no longer looks too short or jammed into the traffic-light/titlebar area.
- [x] Sidebar rows have prototype-like breathing room, not fixed 24pt cramped rows.
- [x] Sidebar icons align closer to the prototype: Activity-like run/recovery, server/resource, document/logs, gear/settings.
- [x] Run/recovery service glyphs use the prototype fallback square-letter treatment rather than unrelated per-service SF Symbol guesses.
- [x] `swift build` passes.
- [x] `git diff --check` passes.
- [x] `scripts/visual-qa/relaydock-window-snapshot.sh` passes and the generated run/recovery screenshot is inspected.

## Out Of Scope

- Adding real favicon/repoIcon fields to the Rust bridge model.
- Reworking the entire registry/logs/preferences pages.
- Reintroducing an AppKit `NSToolbar` spanning the full window.
- Changing product architecture or domain behavior.

## Research References

- `research/localport-style-audit.md`

## Technical Notes

- Likely Swift files:
  - `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
  - `apps/relaydock/Sources/Shell/SidebarView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
  - `apps/relaydock/Sources/DesignSystem/RelayDockColor.swift`
- LocalPort source files reviewed:
  - `/Users/workspace/LocalPort/src/App.tsx`
  - `/Users/workspace/LocalPort/src/components/Sidebar.tsx`
  - `/Users/workspace/LocalPort/src/components/TopBar.tsx`
  - `/Users/workspace/LocalPort/src/views/ForwardsView.tsx`
  - `/Users/workspace/LocalPort/src/components/OsIcon.tsx`

## Implementation Notes

- RelayDock screenshot inspected: `artifacts/visual-qa/relaydock-window-20260506-223148-run-recovery.png`.
- LocalPort rendered reference captured with Chrome headless: `artifacts/prototype-reference/localport-1600x1000-20260506-222153.png`.
- Gemini frontend expert patch and full row-review passes timed out and produced no usable advice.
- Gemini frontend expert topbar/sidebar analyze pass completed and mostly confirmed the dirty patch: 220pt sidebar, 52pt topbar, 30pt sidebar rows, 16pt topbar padding, and regular unselected sidebar icons. Its stale 212pt sidebar note was verified against current code and ignored.
- Follow-up Gemini frontend expert calls on May 6 were attempted with narrower payloads. They failed with an absolute-path input error, a model timeout, invalid JSON, and a non-action/non-final model response. No additional Gemini patch was applied from those failed calls.
- Remaining known visual difference: RelayDock still renders somewhat larger/heavier than the browser prototype because it is a native macOS app with the current 1120x760 default window and SwiftUI system typography. This task only fixed the red-box drift points; broader information-density normalization should be a separate task if desired.
