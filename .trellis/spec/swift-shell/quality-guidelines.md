# Swift Shell Quality Guidelines

- Prefer native controls and platform semantics over custom drawing.
- Keep row layouts stable under changing status text.
- Use short provider labels such as `SSH · 家庭宽带` or `Tailscale · 家里`.
- Do not show placeholder `-` values in recoverable rows when a metric does not apply.
- Keep destructive actions visually subordinate but discoverable.
- Provide accessible labels for icon-only controls.
- Avoid color-only status meaning; include text or stable icons.
- After UI shell changes, run `scripts/visual-qa/relaydock-window-snapshot.sh` and inspect the screenshot before completing the task.
- Use native AppKit titlebar/toolbar semantics for window-level actions. Do not replace the titlebar with a thick SwiftUI-drawn toolbar band.
- Visual QA must inspect the actual top region of the screenshot: search/actions should read as titlebar toolbar controls, and the sidebar/content must not start below an awkward blank strip.
- For native screenshot automation, launch RelayDock through a temporary `.app` bundle instead of the raw SwiftPM binary so macOS activation, Accessibility, Screen Recording, and Computer Use can identify the app consistently.
- Visual QA must fail on black screenshots or missing window rectangles. A black fallback screenshot is not evidence that the UI was inspected.
- On multi-display machines, keep the initial RelayDock window on the primary visible screen so screenshot automation does not capture an offscreen or unavailable display region.
