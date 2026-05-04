# Swift Shell Quality Guidelines

- Prefer native controls and platform semantics over custom drawing.
- Keep row layouts stable under changing status text.
- Use short provider labels such as `SSH · 家庭宽带` or `Tailscale · 家里`.
- Do not show placeholder `-` values in recoverable rows when a metric does not apply.
- Keep destructive actions visually subordinate but discoverable.
- Provide accessible labels for icon-only controls.
- Avoid color-only status meaning; include text or stable icons.
- After UI shell changes, run `scripts/visual-qa/relaydock-window-snapshot.sh` and inspect the screenshot before completing the task.
- The main content must extend into the transparent titlebar area; do not leave a blank system titlebar strip above the toolbar.
- For native screenshot automation, launch RelayDock through a temporary `.app` bundle instead of the raw SwiftPM binary so macOS activation, Accessibility, Screen Recording, and Computer Use can identify the app consistently.
