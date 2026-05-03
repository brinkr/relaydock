# LocalPort 原型参考边界

更新时间：2026-05-04

## 1. 来源

参考仓库：

- `https://github.com/brinkr/LocalPort`
- 本机路径：`/Users/workspace/LocalPort`
- 当前核对版本：`a360546a283b90bd8932bc4dd249bfebcf9223ae`

LocalPort 是 Gemini 生成的 Vite / React 静态原型。它只作为 RelayDock 的视觉、信息密度和交互语义参考，不作为正式技术栈或代码结构来源。

RelayDock 的正式技术选型仍以 [10-technology-stack-decision.md](/Users/workspace/relaydock/documents/10-technology-stack-decision.md) 为准：

`SwiftUI + AppKit shell + Rust core`

## 2. 可吸收的方向

### 2.1 桌面壳层

LocalPort 对 RelayDock 有参考价值的部分是 macOS 桌面工具壳层：

- 固定主窗口工作台
- 左侧 source list
- 顶部上下文工具栏
- 底部状态栏
- 运行区主机分组
- 资源区左主机列表、右详情面板
- 浅色、低阴影、紧凑信息密度

正式 SwiftUI/AppKit 实现时，应优先使用原生窗口、toolbar、sidebar、sheet、popover、menu、status bar 语义重新表达这些结构。

### 2.2 运行与恢复

可以吸收：

- 按 Host 分组
- 默认展开，支持折叠
- 只显示运行中或待恢复的 Host
- 服务行两行紧凑布局
- 第一行放服务身份、本地入口和轻量 provider/channel 指示
- 第二行放端口、状态、时长、延迟、失败次数和行级动作
- 状态与操作右对齐，停止类操作放在最右

正式实现中，provider 文案应更短，例如：

- `SSH · 家庭宽带`
- `Tailscale · 家里`
- `SSH · 广州跳板`

避免使用过重的 `链路：家庭宽带 (SSH)` 这类表述。

### 2.3 资源登记

可以吸收：

- 左侧 Host 列表
- 右侧当前 Host 详情
- Host 摘要区作为当前上下文，而不是独立大卡片
- 当前 Host 下的规则筛选、导入 SSH、新增规则
- SSH 命令导入弹窗
- 服务图标优先使用 favicon / repo icon / 类型推断

正式实现需要重新拆分配置态与运行态。资源登记页面可以展示运行状态摘要，但不应变成第二个运行控制台。

### 2.4 状态栏

可以吸收底部状态栏的思路：

- 当前连接主机数
- 当前运行转发数
- 异常数量
- 最近一次检查或整体健康状态

状态栏应保持轻量，不承载主要操作。

## 3. 不应照搬的问题

LocalPort 是原型，不应把以下问题带入正式设计：

- 不使用 React 组件结构作为 SwiftUI/AppKit 模块边界
- 不使用 WebView/Tailwind 视觉实现作为正式 UI 基础
- 不把 `停止并清空全部` 合并成一个危险动作
- 不把本地端口映射写得过长，例如 `本地 5672 → 远程 127.0.0.1:5672`
- 不在待恢复行显示无意义的 `-` 占位
- 不使用含糊的 `编辑更改`，应明确为 `改本地端口`
- 不让恢复动作因为描边、阴影、颜色过重而破坏列表密度
- 不把启动预设压得过碎，后续需要重新设计其层级

## 4. 对正式 UI 实现的约束

SwiftUI/AppKit 第一版 UI 应遵守：

- 中文优先
- 默认浅色
- 原生 macOS 工具型应用气质
- 避免网页后台感
- 避免 Dashboard/KPI 首页
- 避免大卡片套大卡片
- 避免过强阴影和过重按钮
- 图标用于识别，不用于装饰
- 行高、列宽、状态文案要为高密度长期使用服务

LocalPort 的价值在于帮助确认“像一个桌面工作台应该如何组织信息”。正式实现要吸收这个方向，但必须用 RelayDock 的领域模型、状态机和 Swift/Rust 边界重新落地。
