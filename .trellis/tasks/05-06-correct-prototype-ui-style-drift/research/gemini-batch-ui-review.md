# Gemini Batch UI Review

## Purpose

Run scoped `gemini-frontend-expert` checks after the MCP repair and turn the useful feedback into follow-up task candidates. This review is intentionally advisory: Gemini proposes or critiques, Codex filters against current code, screenshots, and Trellis specs before any work is scheduled.

## Inputs

- RelayDock visual QA screenshots:
  - `artifacts/visual-qa/relaydock-window-20260507-001637-run-recovery.png`
  - `artifacts/visual-qa/relaydock-window-20260507-001637-registry.png`
  - `artifacts/visual-qa/relaydock-window-20260507-001637-logs-diagnostics.png`
  - `artifacts/visual-qa/relaydock-window-20260507-001637-preferences.png`
- LocalPort rendered reference:
  - `artifacts/prototype-reference/localport-1600x1000-20260506-222153.png`
- LocalPort source references:
  - `/Users/workspace/LocalPort/src/components/Sidebar.tsx`
  - `/Users/workspace/LocalPort/src/components/TopBar.tsx`
  - `/Users/workspace/LocalPort/src/components/StatusBar.tsx`
  - `/Users/workspace/LocalPort/src/views/ForwardsView.tsx`
  - `/Users/workspace/LocalPort/src/views/RegistryView.tsx`
  - `/Users/workspace/LocalPort/src/views/LogsView.tsx`
  - `/Users/workspace/LocalPort/src/views/SettingsView.tsx`

## MCP Health Result

- `analyze` works for scoped requests.
- `patch` works for shell-level or text-only scoped requests, but full UI plus multiple screenshots still times out.
- `repair` works for small context and correctly recommended splitting future broad UI reviews by component/page.
- Best operating pattern: one page or one shell area per call, with screenshot observations summarized in text. Do not depend on one all-in broad patch pass.

## Batch Results

### 1. Shell, Sidebar, Topbar, Statusbar

Status: `patch` returned structured diffs.

Useful observations:

- Sidebar selected icon/text may still look heavier than LocalPort; a future polish pass can test `16pt medium` versus `14pt medium` icons and `semibold` versus `medium` selected text.
- Sidebar group spacing is worth a measured visual check. Gemini suggested increasing the `系统` group top spacing and group-title bottom spacing, but this should be compared in screenshot before applying.
- Topbar and statusbar divider opacity can be tuned, but this is lower priority because the current 52pt rhythm already matches the prototype.

Rejected or low-value suggestions:

- Search field `26pt -> 28pt` conflicts with the recorded LocalPort anchor of about 26pt.
- Adding opacity to `sidebarBackground` is not clearly beneficial in SwiftUI because the current color already matches `#F6F6F7` closely.
- Making statusbar labels medium-weight may make the statusbar heavier, not closer to the prototype.

### 2. Run And Recovery

Status: `patch` timed out twice, including text-only mode.

Useful observations from prior successful review and current screenshots:

- The red-box drift points are already addressed: 52pt topbar, 220pt sidebar, 30pt sidebar rows, text-only provider labels, and 20pt square-letter service glyphs.
- A future narrow pass may still be valuable for host header and service row micro-density because the native screenshot reads heavier than the browser prototype.

Rejected or low-value suggestions from previous Gemini runs:

- Re-adding `ServiceGlyph` is incorrect; the struct already exists.
- Claims that service rows still use semantic SF Symbols are stale. Host OS icons may use SF Symbols, but service glyphs use the fallback letter square.

### 3. Registry

Status: text-only `analyze` succeeded.

Useful observations:

- Registry detail rows and host rows may be visually heavier than LocalPort; a compact density pass could improve scan speed.
- The rule list may benefit from clearer running/stopped grouping and more stable right-side action/status alignment.
- Preset groups and rule rows should be checked against the spec requirement for compact single-line rows.

Needs verification before scheduling:

- Gemini mixed shell sidebar width, registry internal host-list width, and LocalPort registry column width in one comment. Width changes should not be made until the intended container is identified.

### 4. Logs And Diagnostics

Status: text-only `analyze` succeeded.

Useful observations:

- The native 3-column workspace direction is correct and should not be collapsed back into a black web-console card.
- Event row density, mono column rhythm, and `INFO/WARN/ERR` alignment are worth a focused pass.
- The right inspector width and stacking behavior should be checked at minimum window width so it does not crush the center event stream.

Rejected or low-value suggestions:

- The `180pt sidebar` warning refers to the internal diagnostic scope list, not the global shell sidebar. It should not be forced to 220pt just because the shell sidebar is 220pt.

### 5. Preferences

Status: text-only `analyze` succeeded.

Useful observations:

- The Preferences content area is sparse; a future pass should improve hierarchy without pretending settings are persisted.
- The MVP boundary text currently competes with navigation in the side list. Moving it into a footer or content boundary area may make the settings scope cleaner.
- Row rhythm and section grouping can be improved, but should stay native and avoid marketing-card styling.

Needs caution:

- Gemini suggested card-group containment because LocalPort uses rounded cards. RelayDock specs discourage card-heavy page composition, so the better target is native grouped rows/sections, not decorative cards.

## Follow-Up Task Candidates

### Candidate A: Shell Micro-Polish

Purpose: make the already-recovered shell feel closer to LocalPort by tuning only small visual weights.

Scope:

- Sidebar selected icon/text weight.
- Sidebar group spacing.
- Topbar/statusbar divider subtlety only if screenshot comparison shows a real mismatch.

Acceptance:

- No change to 220pt sidebar, 52pt topbar, 30pt nav rows, or 26pt search height unless measured evidence says otherwise.
- Fresh visual QA screenshots inspected before commit.

Priority: P3. The main red-box shell drift is already fixed.

### Candidate B: Registry Density And Rule Grouping

Purpose: bring `资源登记` closer to the LocalPort registry information density while preserving native SwiftUI behavior.

Scope:

- Compact host list rows and selected state if they still read oversized.
- Improve rule list grouping/status/action alignment.
- Keep rule rows single-line where possible.

Acceptance:

- No fake persistence or runtime state.
- No broad page redesign.
- Stable status/action columns under changing labels.

Priority: P2. This has visible product impact and likely improves daily scanning.

### Candidate C: Logs Event Stream And Inspector Rhythm

Purpose: improve diagnostic scanning without abandoning the native 3-column diagnostics workspace.

Scope:

- Align event level/time/source/title columns.
- Reduce row heaviness where safe.
- Verify inspector width at minimum window size.

Acceptance:

- Do not reintroduce a black console card.
- Inspector must not crush the event stream at the app minimum width.

Priority: P2.

### Candidate D: Preferences Hierarchy And MVP Boundary Placement

Purpose: make Preferences feel less sparse while keeping it honest about MVP-only/non-persisted behavior.

Scope:

- Move or restyle MVP boundary text so it does not compete with navigation.
- Improve detail-row grouping and section rhythm using native patterns.
- Keep copy explicit about non-persisted/session-local behavior.

Acceptance:

- No fake saved settings.
- No marketing-card layout.
- Works at current minimum window size.

Priority: P3.

### Candidate E: Run/Recovery Host Header And Row Micro-Density

Purpose: follow up on the one page Gemini could not review in patch mode by splitting it into smaller components.

Scope:

- Host header typography/action rhythm.
- Service row title/alias/telemetry/action weights.
- Error text and recoverable-row spacing.

Acceptance:

- Preserve current service fallback glyph style.
- Preserve stable columns and real recovery actions.
- Use smaller, component-specific Gemini requests instead of a whole-file request.

Priority: P2, but should be split into narrow slices to avoid Gemini timeout.

## Recommended Next Work

Start with Candidate B or Candidate C. They are more valuable than another shell polish pass because the shell red-box drift has already been corrected, while Registry and Logs still affect real workflows and scanning density.
