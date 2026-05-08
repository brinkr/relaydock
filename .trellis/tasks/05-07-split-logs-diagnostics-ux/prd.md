# Split logs and diagnostics UX

## Goal

把当前 `日志与诊断` 三列混合页面拆成更清晰的用户体验：`日志` 回到更接近 LocalPort 原型方向的高密度日志工作区，`诊断` 成为独立模块/表面承载检查、事实和恢复候选。Swift 只做展示，继续消费 Rust/bridge 的 snapshots 和 runtime events。

## What I Already Know

- 用户明确要求停止把 logs 和 diagnosis 混在一个三列页面。
- 现有 shell 有 top-level sidebar module 结构，理论上可增加一个顶层 `诊断` 模块。
- 现有 `LogsAndDiagnosticsView.swift` 已经消费 `runRecoverySnapshot.events`、run/recovery snapshot、registry snapshot、bridge error 和 bridge executable facts。
- 现有 spec 要求日志与诊断消费当前 snapshots 和 runtime events，不要在 Swift 发明第二套 runtime/provider state machine。
- 工作树中已有上一轮未提交的 Swift 修改，不能回退。

## Requirements

- 将当前顶层 `日志与诊断` 用户区拆成两个模块，优先使用真正的顶层 split：
  - `日志`：聚焦日志工作区，靠近 LocalPort 原型方向；使用顶部 tabs/segmented filter，移除当前左侧 diagnostic scope sidebar，让主日志 console 获得更多横向空间。
  - `诊断`：独立模块/表面，承载 active checks、inspector-style facts、recovery candidates、bridge snapshot facts。
- Swift 保持 presentation-only，不新增 runtime/diagnostic 状态机；继续消费当前 snapshots、runtime events、bridge errors、registry facts。
- 复用当前数据和 UI 内容；把现有 check/inspector 内容抽到新的诊断表面，而不是删除。
- UI 中文优先，保持 LocalPort prototype 式信息密度；避免 dashboard cards 和 web-admin feel。
- 如果真正顶层模块 split 过于侵入，选择最干净的原生 shell 解法，但必须移除 log console 左侧分类 sidebar，并让诊断和日志明显分离。

## Acceptance Criteria

- [ ] Sidebar/top-level shell 中用户能分别进入 `日志` 和 `诊断`。
- [ ] `日志` 页面没有当前左侧诊断 scope sidebar，主 console 变宽，并用顶部 segmented/tabs filter 切换日志范围。
- [ ] `诊断` 页面显示当前 active checks / inspector facts / recovery candidates / bridge snapshot facts。
- [ ] 现有 runtime events 和 snapshots 继续作为数据源；Swift 不合成 provider/runtime 事件。
- [ ] `swift build` 通过。
- [ ] `git diff --check` 通过。

## Out Of Scope

- 不改 Rust runtime、storage、diagnostic event 模型。
- 不新增 bridge 命令。
- 不实现实时日志流、daemon/background agent 或完整 HTTP Host 诊断。
- 不做 LocalPort prototype 的逐像素复刻。

## Technical Notes

- Likely files:
  - `apps/relaydock/Sources/Features/LogsAndDiagnostics/LogsAndDiagnosticsView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - `apps/relaydock/Sources/Shell/SidebarView.swift`
  - optional small supporting SwiftUI view file for diagnosis module
- Relevant specs:
  - `.trellis/spec/project/index.md`
  - `.trellis/spec/bridge/index.md`
  - `.trellis/spec/bridge/boundary-rules.md`
  - `.trellis/spec/swift-shell/index.md`
  - `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
  - `.trellis/spec/swift-shell/quality-guidelines.md`
  - `documents/05-ui-information-architecture.md`
  - `documents/11-localport-prototype-reference.md`
