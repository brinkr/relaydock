# Swift Shell UI Patterns

## Shell

Use a native desktop shell:

- source-list style sidebar
- content-pane top context bar with title, search, and contextual actions
- bottom status bar
- sheet/popover for focused edits
- preferences window for settings

The window and traffic-light/titlebar behavior should remain AppKit-native, but the visible RelayDock context bar belongs to the SwiftUI content pane so it starts after the sidebar, matching the LocalPort prototype structure. Do not use an AppKit `NSToolbar` that spans across the sidebar when it makes the title/icon/search/action region drift from the prototype.

When recovering prototype style, measure from LocalPort source or a fresh LocalPort render before changing SwiftUI values. Current prototype anchors:

- sidebar width: about 220pt
- sidebar traffic-light/titlebar zone: 52pt
- sidebar nav row: about 30pt with 13pt text and 16pt icons
- content top context bar: 52pt
- top search control: about 26pt high and 300pt wide
- service fallback icon: 20pt rounded square with uppercase first letter

The content-pane top context bar should not be bounded by a hard horizontal line. With the AppKit full-size transparent titlebar, set the native window titlebar separator to hidden and do not add a visible `ShellTopBar` bottom `Divider`; otherwise the separator becomes the perceived titlebar bottom and makes the bar look too short compared with the LocalPort prototype.

Keep dense visual-QA fixtures as a first-class UI testing asset while shell layouts are still stabilizing. Full-data screenshots are required to catch row wrapping, unstable columns, crowded sidebars, and action overflow. These fixtures must remain behind an explicit opt-in switch such as `RELAYDOCK_VISUAL_QA_FIXTURE=prototype-density`; normal app runs must continue to read from the bridge and SQLite store.

Avoid:

- dashboard home pages
- KPI cards
- card-in-card layouts
- heavy shadows
- landing-page hero sections
- web-admin navigation patterns

## Run And Recovery

`运行与恢复` is a runtime workspace.

Use:

- host-grouped list
- default expanded groups
- collapsible host sections
- only active or recoverable hosts
- compact two-line service rows

Keep service rows column-stable. Ports, status, telemetry, provider labels, and row actions should use explicit widths or equivalent stable alignment so changing status text does not reflow the row.

Until the bridge exposes favicon or repo-icon fields for runtime rows, use the LocalPort fallback glyph style for run/recovery services: a subtle 20pt rounded square with an uppercase first letter. Do not invent per-service SF Symbol mappings in Swift based only on service names; those create a different icon language from the prototype and duplicate future domain/icon inference work.

Actions must be explicit:

- page-level `停止全部运行` and `清空恢复列表` are separate
- host-level `恢复全部`, `停止运行中`, `清空待恢复` are separate
- recoverable rows use `恢复`, `改本地端口`, `清除`

Do not use unclear labels such as `编辑更改`.

## Registry

`资源登记` is configuration state.

It can show runtime summaries, but must not become a second runtime console.

Use a left host list and right detail pane. Prefer modal/sheet flows for SSH command import and focused edits.

Keep rule rows compact and single-line. Service names, status labels, and action clusters should truncate or align inside stable columns instead of wrapping into taller rows.

When registry rules include mixed runtime states, group them by state only as a scanning aid; the grouping must not create new runtime behavior or hide rules. Keep row actions in fixed slots: configuration actions first (`映射`, `规则`), followed by exactly one state action (`停止`, `启动`, `恢复`, or `重试`) when applicable. Use fixed widths for service, alias, port, provider, status, and action columns so long aliases or provider labels truncate rather than shifting the action cluster.

## Logs And Diagnostics

`日志与诊断` is a diagnostic workspace, not a themed placeholder.

Use:

- left scope/source list for diagnostic ranges
- center console/event workspace for structured lines
- right inspector for checks, recovery candidates, and bridge facts
- current `run/recovery` and `registry` snapshots as the first data source

Avoid:

- black card inside a white page
- inventing a second Swift-owned runtime or provider state machine
- pretending provider streaming logs already exist when the bridge does not expose them

## Preferences

`偏好设置` should stay narrow and native.

Use:

- left settings sections and right detail pane
- bridge/provider/recovery summaries that reflect current shell context
- sheet/popover explanations for MVP-only entry points
- explicit copy when a control is session-local and not yet persisted

Avoid:

- fake saved settings when no persistence exists yet
- dashboard-style cards or marketing copy
- writing runtime strategy logic into Swift just to make the settings page feel richer
