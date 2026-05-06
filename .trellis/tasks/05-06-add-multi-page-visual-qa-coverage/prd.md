# Add Multi-page Visual QA Coverage

## Goal

Extend RelayDock visual QA from a single default-window screenshot into multi-page evidence for the four primary shell pages. This gives future UI work a practical way to verify the AppKit toolbar, source-list sidebar, page layouts, and bottom status bar across `运行与恢复`, `资源登记`, `日志与诊断`, and `偏好设置`.

## What I Already Know

- The current visual QA script already builds SwiftPM, builds the bridge sidecar, wraps the app in a temporary `.app`, launches it, finds the window rectangle, captures a non-black window screenshot, and removes the temporary bundle.
- The script now rejects black screenshots and rejects missing window rectangles instead of treating full-screen fallbacks as success.
- Current visual QA normally lands on `运行与恢复`, so Logs/Preferences can still be code-reviewed without screenshot evidence.
- The shell sidebar exposes page labels in Chinese:
  - `运行与恢复`
  - `资源登记`
  - `日志与诊断`
  - `偏好设置`
- macOS accessibility / System Events is already used in the script for window geometry, so it is reasonable to use it for page selection when permissions allow.
- The app must continue to use a temporary `.app` bundle for reliable macOS activation and screenshot automation.

## Assumptions

- Multi-page capture can use System Events to click source-list buttons by accessible label or visible title.
- If page navigation cannot be performed, the script should fail with actionable context rather than silently producing only the default page.
- This task should not change product UI behavior, Rust core, bridge commands, storage, provider behavior, or mock/demo data flow.
- It is acceptable to add script helpers and visual QA spec guidance.

## Requirements

- Capture the four main pages in one visual QA run:
  - `run-recovery`
  - `registry`
  - `logs-diagnostics`
  - `preferences`
- Use stable output filenames that include the timestamp and page slug.
- Keep strict validation:
  - no black screenshots
  - no full-screen fallback success
  - no missing window rectangle success
  - no silent skip if a page cannot be selected
- Preserve the temporary `.app` launch path and cleanup behavior.
- Preserve `RELAYDOCK_VISUAL_QA_KEEP_OPEN=1` behavior for manual inspection.
- Print every generated screenshot path on success.
- Make failure output include app bundle, bundle id, pid, known window rect, and keep-open hint.
- Update Swift shell quality spec so future UI tasks know visual QA covers all primary pages.

## Acceptance Criteria

- [ ] `scripts/visual-qa/relaydock-window-snapshot.sh` captures all four page screenshots in one run.
- [ ] Screenshot filenames are page-specific and deterministic enough to inspect from terminal output.
- [ ] `swift build` passes.
- [ ] `git diff --check` passes.
- [ ] `bash -n scripts/visual-qa/relaydock-window-snapshot.sh` passes.
- [ ] Running the visual QA script succeeds in the current environment or fails with actionable context.
- [ ] No Rust core, bridge, storage, provider, Package.swift, or mock/demo data files are modified.

## Out Of Scope

- Pixel diffing against golden snapshots.
- CI integration.
- Browser/WebView testing.
- Changing app navigation semantics for testability.
- Adding artificial data or reintroducing demo rows to make screenshots busier.

## Technical Notes

- Primary file:
  - `scripts/visual-qa/relaydock-window-snapshot.sh`
- Supporting files, only if needed:
  - `.trellis/spec/swift-shell/quality-guidelines.md`
  - possibly `apps/relaydock/Sources/Shell/SidebarView.swift` only if accessibility labels are insufficient, but avoid product UI changes unless required.
- Relevant specs:
  - `.trellis/spec/swift-shell/index.md`
  - `.trellis/spec/swift-shell/quality-guidelines.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
  - `.trellis/spec/project/product-constraints.md`
  - `.trellis/spec/project/commit-guidelines.md`
