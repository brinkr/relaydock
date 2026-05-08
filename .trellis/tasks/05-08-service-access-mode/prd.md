# Add service access modes

## Goal

把 `Rule / Service` 从“默认都是需要 provider 启动的本地转发”扩展为明确的访问模式：`Forwarded`、`Direct`、`Local`。第一阶段先打通模型、bridge、资源登记和运行入口过滤，让 Tailscale/远程直达应用可以登记为可打开的服务，而不被强制塞进 OpenSSH 启动路径；同时保留现有 SSH 本地端口转发、运行恢复和端口冲突基础能力的方向。

## What I already know

- 用户已确认方案：按访问模式区分 `Forwarded / Direct / Local`。
- 早期历史需求明确包含本地端口转发、端口冲突、自动分配、临时改端口；这不是要被 Tailscale 直达替换掉。
- `Tailscale` 默认更适合 `Direct`：tailnet IP / MagicDNS 下的远程应用入口可以直接打开和探测，不需要本地 `ssh -L` 生命周期。
- `Tailscale` 也可能参与 `Forwarded`：远端服务只监听 loopback、需要固定本地域名/本地端口入口、或走中转链路时仍要创建本地绑定。
- 当前 Rust `OpenSshProvider` 只接受 `ProviderTargetType::Ssh`，非 SSH target 会被拒绝。
- 当前 `save_registry_host` 校验要求新建主机至少有一个 provider target，这对 direct/local-first 登记过严。
- 当前 `RegistryRuleDraft` / `Rule` 强制携带 `provider_target_id` 和本地端口映射，导致直达应用无法自然表达。

## Requirements

- 增加服务访问模式：
  - `Forwarded`：需要 provider target 和本地端口绑定，参与启动/停止/恢复、端口冲突、临时本地端口 override。
  - `Direct`：远程/内网地址可直接访问，无本地端口绑定，不进入 OpenSSH 启动/恢复路径；支持展示入口 URL 和连通性诊断。
  - `Local`：本机已有服务入口，无 provider 生命周期；可复用本地端口占用/诊断能力，但不进入隧道启动路径。
- Rust domain/storage/bridge snapshot 要能 round-trip `access_mode`，并保持旧数据/旧 JSON 兼容，缺省为 `Forwarded`。
- 资源登记必须允许 Host 不带 provider target 保存；主机可以先作为资源容器存在。
- 保存规则时：
  - `Forwarded` 仍要求有效 `provider_target_id`、本地端口、远端地址/端口。
  - `Direct` 不要求 `provider_target_id`，但需要可打开的入口 URL 或目标地址/端口。
  - `Local` 不要求 `provider_target_id`，但需要本地入口端口或 URL。
- 运行与恢复 / startRule 入口必须只对 `Forwarded` 服务有效；Direct/Local 不应显示 `启动/恢复/停止/重试` 这类隧道生命周期动作。
- 资源登记规则行需要表达访问模式，例如 `本地转发`、`直达应用`、`本机应用`，并对 Direct/Local 显示 `打开` 而不是 `启动`。
- SSH 命令导入产生的规则必须仍然是 `Forwarded`。
- Visual QA fixture 应包含至少一个 `Direct` 和一个 `Local` 服务，防止 UI 回归到“所有服务都是隧道行”的假设。

## Acceptance Criteria

- [ ] Rust domain 增加 `RuleAccessMode` 或等价模型，配置持久化和 snapshot 投影可 round-trip。
- [ ] 旧规则/旧 JSON 没有 `access_mode` 时按 `Forwarded` 处理。
- [ ] `save_registry_host` 允许 `provider_targets: []`。
- [ ] `save_registry_rule` 对 `Forwarded / Direct / Local` 执行不同校验，且错误为结构化 `registry_validation_failed`。
- [ ] `start_rule` 对非 `Forwarded` 规则返回明确结构化错误，不尝试 OpenSSH provider。
- [ ] Swift bridge models 编译通过，并能编码/解码规则访问模式。
- [ ] 资源登记新增/编辑规则表单可选择访问模式；Direct/Local 不强制 provider target。
- [ ] 规则行对 Direct/Local 显示打开入口，不显示隧道生命周期动作。
- [ ] SSH 导入规则仍能保存并启动为 Forwarded。
- [ ] `swift build` 通过。
- [ ] `cargo test -p relaydock-core` 通过。
- [ ] `git diff --check` 通过。

## Out Of Scope

- 不实现完整本地端口冲突弹窗、自动端口分配和 kill process 流程；这仍是后续端口基础能力任务。
- 不实现 Tailscale CLI 状态同步、MagicDNS 枚举、tailnet 设备发现或 Tailscale Serve 管理。
- 不实现 HTTP 协议级健康检查、favicon 抓取或应用登录态检查。
- 不修改凭据/Keychain 设计。
- 不引入 daemon、launch agent 或新的 provider 生命周期管理。

## Technical Notes

- Relevant docs/specs:
  - `documents/01-product-baseline.md`
  - `documents/02-scope-and-non-goals.md`
  - `documents/03-domain-model.md`
  - `documents/06-provider-and-network-scenarios.md`
  - `documents/07-port-management-foundation.md`
  - `.trellis/spec/project/index.md`
  - `.trellis/spec/bridge/index.md`
  - `.trellis/spec/bridge/boundary-rules.md`
  - `.trellis/spec/rust-core/index.md`
  - `.trellis/spec/rust-core/domain-and-state.md`
  - `.trellis/spec/rust-core/storage-and-diagnostics.md`
  - `.trellis/spec/rust-core/provider-and-process.md`
  - `.trellis/spec/swift-shell/index.md`
  - `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
  - `.trellis/spec/guides/cross-layer-thinking-guide.md`
- Likely Rust files:
  - `crates/relaydock-core/src/domain.rs`
  - `crates/relaydock-core/src/storage.rs`
  - `crates/relaydock-core/src/commands.rs`
  - `crates/relaydock-core/src/providers.rs`
  - `crates/relaydock-core/src/ssh_import.rs`
- Likely Swift files:
  - `apps/relaydock/Sources/Bridge/RelayDockBridgeModels.swift`
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `apps/relaydock/Sources/DesignSystem/RelayDockVisualQAFixtures.swift`
  - possibly `apps/relaydock/Sources/Features/RunRecovery/RunRecoveryView.swift`
- Data-flow sketch:
  - Swift rule draft -> bridge JSON -> Rust validation -> SQLite `ConfigurationSnapshot` -> Rust registry snapshot projection -> Swift registry rows.
  - Start action -> Swift `startRule(ruleId:)` -> Rust loads rule -> rejects non-Forwarded before provider launch -> Swift displays structured error.
