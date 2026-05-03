# RelayDock Documents

这个目录用于沉淀 RelayDock 的产品需求、方案设计和后续实现基线。

## Commit Message 约定

本项目的 commit message 不只用于记录文件变化，也应作为一份可追溯的小型工程文档。

每次提交都应满足：

- subject 符合常见 Git 提交规范，优先使用 `type: summary` 形式，例如 `docs: establish project baseline`
- body 说明本次改动的具体原因
- body 说明本次改动希望达成的目的
- body 说明本次改动的主要范围和边界
- 如果有重要取舍，应在 body 中写清楚为什么这么做

后续如果上下文不足，应优先回看：

- `/Users/brink/.codex/sessions/2026/03/31/rollout-2026-03-31T10-15-28-019d41ac-abaa-7e23-bad3-676c3a4d0a88.jsonl`
- [09-source-conversation-map.md](/Users/workspace/relaydock/documents/09-source-conversation-map.md)

当前已整理文档：

- [01-product-baseline.md](/Users/workspace/relaydock/documents/01-product-baseline.md)
  - 当前产品定位
  - 已确认需求
  - 范围边界
  - 运行模型
  - 视觉与交互基线
  - 项目命名约定
- [02-scope-and-non-goals.md](/Users/workspace/relaydock/documents/02-scope-and-non-goals.md)
  - 重点范围
  - 非目标
  - 基础能力与一级模块边界
- [03-domain-model.md](/Users/workspace/relaydock/documents/03-domain-model.md)
  - 领域对象
  - 字段方向
  - 对象之间的关系
- [04-runtime-state-machine.md](/Users/workspace/relaydock/documents/04-runtime-state-machine.md)
  - 运行态状态机
  - 恢复集合
  - 冲突处理
  - 临时本地端口覆盖
- [05-ui-information-architecture.md](/Users/workspace/relaydock/documents/05-ui-information-architecture.md)
  - 页面职责
  - 主工作流
  - 页面内结构
  - 行级交互
- [06-provider-and-network-scenarios.md](/Users/workspace/relaydock/documents/06-provider-and-network-scenarios.md)
  - SSH/Tailscale provider 抽象
  - 家里/公司/广州跳板场景
  - 预设与覆盖关系
- [07-port-management-foundation.md](/Users/workspace/relaydock/documents/07-port-management-foundation.md)
  - 本地端口扫描
  - 冲突提示
  - 自动递增分配
  - 释放占用进程
- [08-import-export-and-ai.md](/Users/workspace/relaydock/documents/08-import-export-and-ai.md)
  - SSH 命令导入
  - 配置导出导入
  - AI 友好要求
- [09-source-conversation-map.md](/Users/workspace/relaydock/documents/09-source-conversation-map.md)
  - 本项目关键结论来自哪些 `.codex` 真实对话
  - 每条会话主要贡献了什么
- [10-technology-stack-decision.md](/Users/workspace/relaydock/documents/10-technology-stack-decision.md)
  - 正式技术选型：`SwiftUI + AppKit shell + Rust core`
  - Swift/Rust 边界
  - 早期候选方案取舍
  - Trellis / harness 使用约束
- [11-localport-prototype-reference.md](/Users/workspace/relaydock/documents/11-localport-prototype-reference.md)
  - LocalPort 原型参考边界
  - 可吸收的桌面壳层与信息密度
  - 不应照搬的 React/Web 原型问题
