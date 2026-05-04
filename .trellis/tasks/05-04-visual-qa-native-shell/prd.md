# Add Visual QA For Native Shell

## Purpose

Fix the visible native shell titlebar/content integration issue and add a repeatable screenshot-based QA workflow for future RelayDock macOS UI tasks.

## Inputs

- `documents/05-ui-information-architecture.md`
- `documents/11-localport-prototype-reference.md`
- `.trellis/spec/swift-shell/index.md`
- `.trellis/spec/swift-shell/quality-guidelines.md`

## Requirements

- Fix the current titlebar/toolbar layout so the app does not show a large blank native titlebar area above the content.
- Preserve formal naming as `RelayDock` / `relaydock`; `LocalPort` remains only a prototype reference.
- Add a script that can build, launch, capture a screenshot of the RelayDock window, and clean up the launched process.
- Add the screenshot QA expectation to Swift shell spec so future UI tasks run it before completion.
- Keep generated screenshots/build products out of git.

## Non-Goals

- No Rust bridge.
- No provider runtime.
- No persistence.
- No full pixel-perfect UI pass beyond the titlebar/shell integration issue.

## Acceptance Criteria

- `swift build` passes.
- `cargo test` passes.
- The visual QA script captures a screenshot under an ignored output path.
- The captured screenshot can be inspected by the AI before finalizing UI tasks.
