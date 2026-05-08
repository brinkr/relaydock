# Refine registry prototype style

## Goal

把 RelayDock 的 `资源登记` 页面往 LocalPort 原型的结构与气质收回来，重点修正当前实现中过重的分割线、连续表格感、启动预设区块空洞感，以及规则清单缺少卡片式分组容器的问题。

## What I Already Know

- 用户明确指出当前 `资源登记` 页面相比原型“看起来很糟糕”，尤其是：
  - `启动预设` 下方出现多条分割线，怀疑与空内容和容器处理有关；
  - 整页线条过多、过重；
  - 原型是按区块组织的，`规则清单` 在一个卡片式容器中；
  - 当前 SwiftUI 实现没有把这些层次表达出来。
- LocalPort 原型源码可直接对照：
  - `/Users/workspace/LocalPort/src/views/RegistryView.tsx`
- 当前 SwiftUI 对应文件：
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
- 从原型代码读取到的关键结构：
  - 左侧 host list 是 `260px` 宽、浅背景、轻边界，行与行之间几乎没有可见分隔线；
  - 右侧 detail 是 `Host Header` + 可滚动内容；
  - 可滚动内容背景是轻微灰底，内部由 `启动预设` 和 `规则清单` 两个区块组成；
  - `启动预设` 是无重边框的清单流，空状态只是一行轻量文案；
  - `规则清单` 的运行中 / 未启动列表放在圆角白色卡片中，卡片内部才使用极浅的分隔线。
- 当前 SwiftUI 主要偏差：
  - `RegistryPresetsSection` 用了上下 overlay 分割线，再加行间 `Divider()`，导致视觉上出现双线/重线；
  - `RegistryRuleGroupBand` 也是 band + overlay + 内部分割线的组合，页面整体线条密度过高；
  - 整个右侧内容直接贴在白底上，没有把原型中的“灰底工作区 + 白色规则卡片”层次翻译出来；
  - 左侧 host list 当前只有 224pt，且行组织更像数据列表，不像原型里的轻量资源分组列表。

## Requirements

- 资源登记页需要更接近原型的分块组织，而不是连续表格：
  - 左侧 `资源分组` 列表保留 native source-list 气质，但行密度、宽度和选中态要更接近原型；
  - 右侧 detail 保持 `Host Header` + 下方滚动工作区；
  - 滚动工作区应体现“浅灰工作区背景 + 内部区块”的结构。
- `启动预设` 区块：
  - 去掉当前过重的上下边线和重复分割；
  - 空状态保持轻量，不因为空内容制造双线或空盒子感；
  - 有内容时按原型做成轻量列表流，不要套明显表格框。
- `规则清单` 区块：
  - 更接近原型的“工具条 + 卡片容器 + 卡片内轻分割线”；
  - 运行中 / 已停止 / 可恢复 / 异常分组应保留当前 Swift 运行态语义，但视觉上不要像多条被硬切开的 band；
  - 优先把规则内容收进一层白色圆角容器，由容器承担分组感，而不是靠大量 Divider。
- 线条和边界：
  - 明显减少线条数量；
  - 保持边线更浅、更克制；
  - 避免一块区域同时出现 overlay 顶底线 + 行间 Divider 的重复分割。
- 测试数据 / QA：
  - 需要保证 visual QA fixture 下 `资源登记` 页面有足够密度，便于判断 `启动预设` 和 `规则清单` 的真实视觉效果；
  - 如当前 fixture 不足以暴露问题，可补充或调整 fixture 数据，但不要影响普通 bridge/SQLite 路径。
- 新增 / 编辑资源分组弹窗：
  - 输入框不应出现过重的系统蓝色焦点边框，也不应在左右边缘裁切文本；
  - 弹窗应提供保存前的 `测试连接` 入口；
  - 不应让用户手动选择 `未探测 / 在线 / 离线`，这些状态应来自探测结果；
  - 连接测试必须通过 Swift/Rust bridge 调用 Rust core 的结构化命令完成，Swift 只管理表单草稿和结果展示；
  - 当前测试语义限定为 provider target 的 TCP 可达性，不宣称 SSH 认证或远端应用协议已通过。

## Acceptance Criteria

- [ ] `资源登记` 页面明显减少重复分割线，尤其是 `启动预设` 区块不再出现双线/重线感。
- [ ] 左侧 `资源分组` 列表和右侧 detail 的层次更接近原型：轻列表 + header + 灰底工作区。
- [ ] `规则清单` 使用更接近原型的卡片式容器组织，而不是连续 band/table 感。
- [ ] `新建资源分组` / `主机设置` 弹窗输入框使用克制浅边框，不再出现粗蓝色焦点框或左右裁切。
- [ ] 弹窗可在保存前测试当前 provider target 的 TCP 可达性，并以内联结果显示成功、失败和诊断。
- [ ] 主机在线状态不再由手动表单选择决定；未测试或连接目标变更后未重测时保存为 `未探测`。
- [ ] visual QA 密集 fixture 下，`资源登记` 页面截图能看出更克制的线条和更清晰的区块关系。
- [ ] `swift build` 通过。
- [ ] `cargo test -p relaydock-core` 通过。
- [ ] `git diff --check` 通过。

## Out Of Scope

- 不修改 storage / runtime 持久化行为。
- 不做 SSH 认证、Keychain 凭据、远端应用协议探测或后台健康轮询。
- 不重做资源登记的数据模型或交互语义。
- 不把 React/Tailwind 结构照搬到 SwiftUI。
- 不为了追求“像原型”而牺牲当前已存在的真实运行态动作语义。

## Technical Notes

- Likely files:
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `apps/relaydock/Sources/Bridge/RelayDockBridgeModels.swift`
  - `apps/relaydock/Sources/Bridge/RelayDockBridgeExecutor.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - `crates/relaydock-core/src/commands.rs`
  - `apps/relaydock/Sources/DesignSystem/RelayDockVisualQAFixtures.swift`
  - `scripts/visual-qa/relaydock-window-snapshot.sh` only if fixture navigation/coverage needs adjustment
- LocalPort reference:
  - `/Users/workspace/LocalPort/src/views/RegistryView.tsx`
  - `/Users/workspace/LocalPort/src/index.css`
