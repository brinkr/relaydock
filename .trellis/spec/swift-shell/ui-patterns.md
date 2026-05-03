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
