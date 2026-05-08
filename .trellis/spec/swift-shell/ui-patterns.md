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

Show provider/host-scoped health or latency summaries in the host header when Rust returns `healthSummary`; do not repeat the same SSH-target latency on every row. Row telemetry should stay focused on runtime duration, failure count, and binding-specific differences.

When Rust returns `entryUrl`, show that complete URL instead of a bare alias. A `.localhost` hostname does not carry port information; `http://ssh-18317.localhost:18317/` and `http://ssh-18317.localhost/` are different local entries.

Actions must be explicit:

- page-level `停止全部运行` and `清空恢复列表` are separate
- host-level `恢复全部`, `停止运行中`, `清空待恢复` are separate
- recoverable rows use `恢复`, `改本地端口`, `清除`

Do not use unclear labels such as `编辑更改`.

## Registry

`资源登记` is configuration state.

It can show runtime summaries, but must not become a second runtime console.

Use a lighter left host list and right detail pane. The host list should feel like a source-list resource picker: roomy rows, low-contrast background, shallow selected accent, and minimal per-row metadata. Keep detailed endpoint/provider facts in the selected-host header rather than making the left list read like a data table.

The selected-host detail should use a host header plus a faint gray work surface. Let spacing, background, and calm containers carry the hierarchy instead of hard stacked bands.

`启动预设` should stay a lightweight flow, not a boxed table. Empty states should be one quiet line. Avoid combining outer overlay dividers with row dividers; that creates the double-line effect that made the section feel broken.

`规则清单` should prefer a compact toolbar plus calm rounded containers with shallow internal separators. Runtime-state grouping is a scanning aid only; it must not create new runtime behavior or hide rules. Prefer white rounded rule-group cards on the gray work surface over stacked hard bands.

Registry rule rows may use a compact two-line service-item layout when it better matches the prototype: first line for service identity, alias, and status; second line for local port and provider/link context. Keep row actions in stable fixed slots on the right: configuration actions first (`映射`, `规则`), followed by exactly one state action (`停止`, `启动`, `恢复`, or `重试`) when applicable. Long service names, aliases, ports, and provider labels should truncate inside their row areas rather than shifting the action cluster.

Access mode rules:

- `本地转发` rows may show tunnel lifecycle actions (`启动` / `停止` / `恢复` / `重试`) and mapping copy.
- `直达应用` and `本机应用` rows must show registry/open-entry behavior, not tunnel lifecycle. Use `入口` / `规则` / `打开` style actions and a neutral `已登记` status.
- Direct/local rows may appear in registry groups such as `直达应用` and `本机应用`; do not hide them under `已停止`, because they are not stopped tunnels.
- A host with no provider target is valid for direct/local resources. The host editor must allow removing the last provider target and should explain that SSH forwarding can add one later.
- Visual QA dense fixtures must include at least one direct and one local rule so UI regressions cannot assume every registry row is a tunnel.

Prefer:

- shallow borders on the host-list split, host header bottom, and rule-card container
- subtle card-internal separators only between rows
- spacing between sections instead of repeated `Divider()` / overlay lines

Avoid:

- table-wide single-line rule rows when they make the page feel like a spreadsheet
- repeated overlay top/bottom dividers around sections that already have row separators
- boxed preset bands or empty preset containers

## Logs

`日志` is a focused log workspace, not a mixed diagnostics dashboard.

Use:

- top tabs or segmented filters for log ranges
- full-width console/event workspace for structured lines
- current `run/recovery` and `registry` snapshots as the first data source
- `runRecoverySnapshot.events` as the first source for actual runtime/provider event lines
- snapshot-derived runtime host / reconnecting / error / recovery rows may appear when they read as event history

Avoid:

- a second left scope/sidebar inside the log console
- checklist-style diagnosis facts such as snapshot summary checks
- black card inside a white page
- inventing provider streaming logs when the bridge does not expose them

## Diagnostics

`诊断` is a separate facts-and-checks surface.

Use:

- active checks derived from current snapshots and bridge errors
- inspector-style bridge / snapshot facts
- recovery candidates and runtime issue rows
- current `run/recovery` and `registry` snapshots as the first data source

Avoid:

- inventing a second Swift-owned runtime or provider state machine
- moving log console scope navigation back into a second internal sidebar

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
