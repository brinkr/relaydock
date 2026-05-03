# RelayDock 技术选型决策

更新时间：2026-05-04

## 1. 决策状态

状态：已确认

RelayDock 的正式技术选型采用：

`SwiftUI + AppKit shell + Rust core`

这个决策覆盖真实开发主线。此前讨论中出现过的 `Tauri + React + Go`、`Tauri + React + Rust`、`Electron + React` 等方案均视为早期候选或原型阶段参考，不作为当前实现主线。

## 2. 决策背景

RelayDock 是 macOS 优先的本地桌面隧道与端口转发工作台。它需要长期处理：

- 桌面原生壳层
- source list / toolbar / status bar / inspector 等 macOS 风格结构
- SSH 进程生命周期
- 本地端口扫描与冲突处理
- 运行态恢复
- 日志与诊断
- 配置导入导出
- 后续可能出现的 CLI / agent 能力

因此技术栈不能只按“原型容易做”选择，也不能继续依赖 React 静态原型去假装桌面应用。正式开发应优先保证 macOS 原生体验、系统集成能力和核心逻辑可测试性。

## 3. 选型结论

### 3.1 SwiftUI + AppKit shell

SwiftUI 和 AppKit 负责应用壳层与 macOS 集成。

职责包括：

- 主窗口结构
- sidebar / source list
- toolbar
- status bar
- inspector / sheet / popover
- 菜单栏
- 托盘 / menu bar item
- 偏好设置窗口
- 系统通知
- Keychain 集成
- LaunchAgent / 开机启动入口
- 文件导入导出面板
- 与 Finder / 默认浏览器的系统交互

SwiftUI 用于主要声明式界面。AppKit 用于 SwiftUI 难以精细控制的桌面行为和原生组件补位。

### 3.2 Rust core

Rust 负责核心运行逻辑和可复用能力。

职责包括：

- 领域模型
- 运行态状态机
- 规则解析与校验
- SSH 命令导入解析
- 本地端口扫描
- 端口冲突检测
- 临时本地端口覆盖
- SSH / provider 进程编排的核心抽象
- 日志归一化
- 恢复集合持久化逻辑
- 后续 CLI / agent 复用接口

Rust core 不直接负责绘制 UI。它应该暴露清晰、稳定、可测试的 API 给 Swift shell 调用。

## 4. 边界划分

### 4.1 Swift 层不承担的职责

Swift 层不应承载复杂业务状态机，也不应把 SSH 命令解析、端口扫描、恢复策略等核心逻辑写散在 ViewModel 里。

Swift 层可以保留：

- UI 状态
- 用户选择状态
- 表单编辑草稿
- 系统权限交互
- macOS 平台适配

### 4.2 Rust 层不承担的职责

Rust 层不应感知具体 SwiftUI 视图结构，也不应决定页面排版和视觉细节。

Rust 层可以输出：

- 结构化运行状态
- 结构化错误
- 诊断事件
- 可恢复项
- provider 结果
- 端口占用信息

### 4.3 跨语言接口原则

Swift 与 Rust 的边界应保持粗粒度。

推荐接口形态：

- Swift 发出明确命令，例如 `start_rule`、`stop_runtime_instance`、`scan_ports`、`parse_ssh_command`
- Rust 返回结构化结果
- 错误统一映射成可展示、可记录、可诊断的错误类型
- 避免把 UI 层的细粒度交互事件频繁穿透到 Rust

第一版可以先用较简单的 FFI/命令封装方式落地，后续再根据工程复杂度抽象稳定 SDK。

## 5. 持久化方向

本地配置和运行态数据仍以 SQLite 为主。

建议分层：

- Swift shell 负责用户选择文件、授权、偏好设置入口
- Rust core 负责配置 schema、迁移、导入导出校验、运行态持久化
- 敏感凭据优先交给 macOS Keychain，不写入普通 SQLite

## 6. Provider 与系统依赖

第一阶段不自研 SSH 协议实现。

默认策略：

- SSH provider 优先调用系统 OpenSSH
- Tailscale provider 优先调用系统 Tailscale CLI 或本机可用状态
- Rust core 负责进程编排、状态观测、错误归因
- Swift shell 负责权限提示和用户可见的操作反馈

本地反向代理能力后续可在 Rust core 内实现，也可在早期通过明确的 sidecar 方案验证。但无论使用哪种方式，都必须服务于 RelayDock 的运行模型，而不是把产品重新变成 Web 面板。

## 7. 被拒绝或降级的候选方案

### 7.1 Tauri + React + Go

这是早期方案建议，不作为当前主线。

拒绝原因：

- UI 仍是 WebView，容易延续网页后台感
- React 原型可复用，但也会继承原型阶段的网页化惯性
- `React + Tauri/Rust + Go` 三层栈对当前个人项目偏重
- macOS 原生 toolbar、source list、status bar、菜单、偏好设置等细节需要额外模拟

### 7.2 Tauri + React + Rust

保留为跨平台优先时的备选，不作为当前主线。

拒绝原因：

- Rust core 合适，但 UI 仍受 WebView 限制
- 当前目标是 macOS-first，不应为了未来可能跨平台牺牲第一版桌面质感

### 7.3 Electron + React + Node

不推荐。

拒绝原因：

- 资源占用高
- 包体重
- 最容易做成 Web admin 风格
- 对 RelayDock 这类本地基础设施工具来说过度

### 7.4 SwiftUI + AppKit only

可作为极简 MVP 的临时降级路径，但不是正式架构目标。

降级条件：

- 如果 Rust FFI 在第一阶段显著拖慢启动，可先把少量核心逻辑写在 Swift 层验证 UI 和状态流
- 但应保留 Rust core 的模块边界，避免后续迁移困难

## 8. 对原型和协作方式的影响

Gemini/React 原型仍然可以作为视觉和交互参考，但不能直接决定工程结构。

当前可参考的原型为 `https://github.com/brinkr/LocalPort`，参考边界详见 [11-localport-prototype-reference.md](/Users/workspace/relaydock/documents/11-localport-prototype-reference.md)。

后续协作方式应调整为：

- 原型用于讨论布局、信息密度、文案和交互语义
- SwiftUI/AppKit 实现时重新按原生桌面结构建模
- Rust core 优先沉淀领域模型和状态机
- 不把 React 组件结构当成正式代码结构

## 9. 对 Trellis / harness 的影响

如果后续初始化 Trellis，不应使用 `electron-fullstack` 之类模板。

更合适的方式是：

- 用 Trellis 管理 spec、task、implementation plan
- 以本决策文档作为技术栈约束
- 自定义任务切片为 Swift shell、Rust core、FFI bridge、storage、provider、diagnostics
- 保持 spec-driven / harness 风格，但不套用和本项目技术栈不匹配的模板

## 10. 下一步工程顺序

正式开发建议按以下顺序推进：

1. 定义 Rust core 的领域模型与状态机接口
2. 定义 Swift shell 的页面与 ViewModel 边界
3. 建立最小 Swift/Rust bridge
4. 落地本地配置存储与运行态存储
5. 先接 SSH provider
6. 再接 Tailscale provider
7. 补导入导出、图标探测、日志增强
