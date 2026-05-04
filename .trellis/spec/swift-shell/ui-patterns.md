# Swift Shell UI Patterns

## Shell

Use a native desktop shell:

- source-list style sidebar
- top toolbar with contextual actions
- bottom status bar
- sheet/popover for focused edits
- preferences window for settings

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

Actions must be explicit:

- page-level `停止全部运行` and `清空恢复列表` are separate
- host-level `恢复全部`, `停止运行中`, `清空待恢复` are separate
- recoverable rows use `恢复`, `改本地端口`, `清除`

Do not use unclear labels such as `编辑更改`.

## Registry

`资源登记` is configuration state.

It can show runtime summaries, but must not become a second runtime console.

Use a left host list and right detail pane. Prefer modal/sheet flows for SSH command import and focused edits.

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
