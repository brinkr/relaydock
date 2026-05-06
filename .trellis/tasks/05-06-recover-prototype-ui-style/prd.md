# Recover Prototype UI Style

## Goal

把 RelayDock 当前 SwiftUI/AppKit 原生界面的视觉语言拉回 LocalPort 原型代表的桌面工具工作台风格，重点收回 `运行与恢复` 的信息密度、列表比例、主机分组、两行服务行、右侧状态/动作列和底部状态栏节奏，避免后续功能施工继续在已经漂移的 UI 基础上叠加。

## What I Already Know

- 用户明确指出当前实现效果距离最初 LocalPort 原型差距较大，要求在功能验证前先把风格收回来。
- RelayDock 正式技术选型已经固定为 `SwiftUI + AppKit shell + Rust core`。
- LocalPort 只能作为视觉、信息密度和交互语义参考，不能复制 React/Tailwind 结构，也不能引入 WebView/Tauri/React/Go。
- `documents/05-ui-information-architecture.md` 和 `documents/11-localport-prototype-reference.md` 已明确要求 source list 左栏、顶部原生 toolbar、底部状态栏、运行页主机分组和紧凑两行服务行。
- 当前视觉 QA 截图里 `运行与恢复` 只显示一个主机和一条服务行，导致页面大面积空白；这会掩盖真实密度问题。
- 视觉 QA 现在能一次捕获四个主页面，但它只能验证非空和可选中，不能自动判断风格是否回到原型密度。

## Assumptions

- 这轮先把最高风险的主工作台 `运行与恢复` 拉回原型风格；其它页面只做必要的壳层一致性和避免明显后台页漂移。
- 不把 mock/demo 数据重新塞回用户真实运行路径。
- 如果截图需要稳定评估密度，应使用 visual-QA-only fixture/store 或 app 运行环境开关，不能污染默认 bridge/storage 行为。
- 不更改 Rust provider、真实重试/恢复/停止等业务行为。

## Requirements

- 保持原生 macOS shell：
  - AppKit 继续负责 NSWindow、交通灯、可拖拽窗口和原生窗口行为。
  - SwiftUI 承载 sidebar/content/status bar，并在右侧内容区顶部渲染 52pt 上下文工具栏；该工具栏必须从 sidebar 右侧开始，不能跨过左栏。
  - 左侧 source list 保持轻量浅灰、紧凑选中态。
- `运行与恢复` 收回原型密度：
  - 主机 header 更像 sticky control bar，约 42-46pt 高。
  - 服务行两行紧凑布局，约 48-54pt 高。
  - 服务名/alias、端口、状态、telemetry、provider、行级动作保持稳定列宽。
  - recoverable 行不显示无意义的 `-` 指标。
  - 停止、清空等危险动作显式但视觉从属。
  - 空白区域减少；在有足够数据时首屏应能展示多个服务行。
- `资源登记` 和 shell 周边保持与原型同一视觉语言：
  - 左主机列表和右详情面板比例不要变成宽松后台页。
  - Preset/rule 区域避免卡片堆叠感，规则行保持紧凑列表。
  - 底部状态栏保持 28pt 左右、轻量信息，不承载主要操作。
- Visual QA 支持风格回归检查：
  - 提供 visual-QA-only 的密度样本路径，使截图至少包含一个展开主机组和多条服务行。
  - 默认用户运行路径仍读取真实 bridge/storage 数据。
  - 更新质量规范，使未来 UI 任务必须用密度样本截图检查风格，而不只看截图是否非黑。

## Acceptance Criteria

- [ ] `运行与恢复` visual QA 截图在样本模式下显示至少一个展开主机组和 7 条以上服务行。
- [ ] 样本截图覆盖 connected、reconnecting、error、recoverable 多种状态。
- [ ] `运行与恢复` 行布局看起来接近 LocalPort 原型的密集桌面工作台，而不是空白后台页。
- [ ] 顶部区域没有回归成跨全窗 AppKit toolbar 或厚重自绘标题栏；sidebar 从窗口顶部开始，右侧工具栏从内容区开始。
- [ ] `资源登记` 首屏仍保持左 host list + 右 detail/rule list 的紧凑信息架构。
- [ ] `swift build` 通过。
- [ ] `git diff --check` 通过。
- [ ] `scripts/visual-qa/relaydock-window-snapshot.sh` 成功生成四页截图，并人工检查 `运行与恢复` 和 `资源登记`。

## Definition of Done

- Swift shell/design-system/visual-QA/spec/task 文件完成必要修改。
- Swift shell 采用原生 NSWindow + 内容区上下文工具栏，不再使用跨 sidebar 的 AppKit `NSToolbar` 承载 RelayDock 页面标题、搜索和动作。
- 未引入 WebView、React、Tauri、Electron、Go 或 LocalPort 代码复制。
- 未改变 Rust provider、storage schema、bridge 命令语义，除非只是读取已有环境变量或 QA 辅助且有明确边界。
- 视觉 QA 截图路径记录在最终说明或任务日志中。

## Latest Visual QA

- 2026-05-06 verified screenshots:
  - `artifacts/visual-qa/relaydock-window-20260506-212015-run-recovery.png`
  - `artifacts/visual-qa/relaydock-window-20260506-212015-registry.png`
  - `artifacts/visual-qa/relaydock-window-20260506-212015-logs-diagnostics.png`
  - `artifacts/visual-qa/relaydock-window-20260506-212015-preferences.png`
- `运行与恢复` screenshot shows the dense visual-QA fixture with expanded host groups, more than seven visible service rows, and connected/reconnecting/error/recoverable states.
- `资源登记` screenshot keeps the left host list plus right detail/rule list structure and the content-pane top bar starts to the right of the sidebar.

## Out of Scope

- 新增或修复真实 SSH/Tailscale provider 功能。
- 做完整设计系统重构。
- 重写所有页面视觉。
- 把 LocalPort React/Tailwind 组件结构迁移到 Swift。
- 为用户真实数据路径重新添加生产 mock/demo 数据。

## Technical Notes

- Relevant specs:
  - `.trellis/spec/project/index.md`
  - `.trellis/spec/project/product-constraints.md`
  - `.trellis/spec/swift-shell/index.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
  - `.trellis/spec/swift-shell/quality-guidelines.md`
  - `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  - `.trellis/spec/guides/index.md`
- Product docs:
  - `documents/05-ui-information-architecture.md`
  - `documents/11-localport-prototype-reference.md`
  - `documents/10-technology-stack-decision.md`
- Current UI files likely affected:
  - `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
  - `apps/relaydock/Sources/Shell/SidebarView.swift`
  - `apps/relaydock/Sources/Shell/StatusBarView.swift`
  - `apps/relaydock/Sources/App/RelayDockWindowController.swift`
  - `apps/relaydock/Sources/DesignSystem/RelayDockColor.swift`
  - `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `scripts/visual-qa/relaydock-window-snapshot.sh`
