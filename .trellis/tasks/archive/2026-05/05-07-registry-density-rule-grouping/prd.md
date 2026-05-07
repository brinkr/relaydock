# Registry Density And Rule Grouping

## Goal

Refine `资源登记` so it keeps the native SwiftUI split-view shape while moving closer to the LocalPort prototype's scan density and rule organization. The page should remain configuration state, not become a second runtime console.

## Background

This task comes from `05-06-correct-prototype-ui-style-drift` and the batched Gemini review in `research/gemini-batch-ui-review.md`.

Useful review points:

- Registry detail rows and host rows may be visually heavier than LocalPort; a compact density pass could improve scan speed.
- The rule list may benefit from clearer running/stopped grouping and more stable right-side action/status alignment.
- Preset groups and rule rows should be checked against the Swift shell spec requirement for compact single-line rows.

Known caution:

- Gemini mixed shell sidebar width, registry internal host-list width, and LocalPort registry column width. Do not blindly resize the internal host list unless the current screenshot and code justify it.

## Requirements

### Host List

- Keep the internal registry host list on the left and detail pane on the right.
- Improve visual density only if it does not make host names/endpoints harder to scan.
- Keep selected state restrained and native.
- Do not change the global app shell sidebar.

### Host Detail

- Keep the host header compact and stable.
- Host status and provider summaries should stay readable without turning the header into a dashboard.
- Avoid broad redesigns or decorative card-heavy layout.

### Presets

- Keep startup presets compact.
- Preserve existing actions and placeholder flows.
- If changing row styling, keep it compatible with future real preset editing.

### Rule List

- Make rule rows compact and single-line where possible.
- Improve status/action alignment so labels do not cause the row to reflow.
- Preserve explicit actions: `映射`, `规则`, and exactly one runtime action based on state (`停止`, `恢复`, or `重试`).
- Consider grouping running/recoverable/error/idle rules only if it improves scanability without hiding all rules behind new behavior.
- Do not add fake runtime data or persistence.

## Out Of Scope

- Rust core or bridge model changes.
- New persisted registry settings.
- Replacing the native SwiftUI view with LocalPort React/Tailwind code.
- Reworking run/recovery behavior.
- Broad page redesign.

## Acceptance Criteria

- [ ] `资源登记` screenshot shows improved scan density in host list and rule list without losing readability.
- [ ] Rule row status/action columns remain stable under different runtime states.
- [ ] Rule rows avoid wrapping in normal dense fixture data.
- [ ] Existing import/edit/recover/retry/stop entry points still compile and remain wired.
- [ ] `swift build` passes.
- [ ] `git diff --check` passes.
- [ ] `scripts/visual-qa/relaydock-window-snapshot.sh` passes and the registry screenshot is inspected.

## Reference Files

- `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
- `apps/relaydock/Sources/DesignSystem/RelayDockColor.swift`
- `.trellis/spec/swift-shell/ui-patterns.md`
- `.trellis/spec/swift-shell/quality-guidelines.md`
- `.trellis/tasks/05-06-correct-prototype-ui-style-drift/research/gemini-batch-ui-review.md`
- `.trellis/tasks/05-06-correct-prototype-ui-style-drift/research/localport-style-audit.md`
- `/Users/workspace/LocalPort/src/views/RegistryView.tsx`
