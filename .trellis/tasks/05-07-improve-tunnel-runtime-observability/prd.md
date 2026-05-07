# Improve tunnel runtime observability

## Goal

让 RelayDock 的“运行中”变成可信状态，而不是只表示 OpenSSH 进程还活着；同时把隧道启动、观测、断联、延迟和本地别名访问问题沉淀成可诊断的事实。

## What I Already Know

- 用户已验证：从资源登记启动隧道后，`http://127.0.0.1:18317/` 可以访问，说明启动路径和本地端口转发基本可用。
- 用户切换网络回家后，隧道实际断了，但 UI 仍显示 `运行中`。
- 当前 Rust 运行态 reconciliation 主要通过 `ProviderProcessController::is_running(pid)` 判断，也就是 `kill -0 <pid>`；只要 OpenSSH 进程未退出，就会继续投影为 connected。
- `build_openssh_launch_plan_with_bindings` 已加入 `ExitOnForwardFailure=yes`、`ServerAliveInterval=15`、`ServerAliveCountMax=2`，但 UI 不能只依赖 ssh 进程最终退出。
- 现有日志页是从当前 run/recovery 和 registry snapshot 拼出来的结构化线索，尚未持久化真实启动事件、OpenSSH command、stderr/stdout 或健康检查事件。
- 现有 `RuntimeInstance` 已有 `latency_ms` 字段，但当前没有真实测量路径。
- 用户认为每条隧道都显示延迟可能重复：同一个 SSH provider target 下的多条本地转发共享一条 SSH 连接语义，延迟更适合主机/目标级展示，再在行内按需显示异常或补充信息。
- 本机快速验证：`ssh-18317.localhost` 在 macOS 上可解析到 `127.0.0.1` / `::1`。因此“127.0.0.1 可访问但 ssh-18317.localhost 不可访问”不一定是 DNS 失败，更可能是上游 Web 服务的 `Host` header 限制、IPv4/IPv6 差异、服务自身允许列表、或 HTTP virtual host 规则。

## Requirements

### P0: Running state must be trustworthy

- `运行中` 不应只表示 pid 存在。
- 每次刷新运行态时，应执行至少一种隧道可用性观测：
  - OpenSSH pid still exists.
  - local forwarded port can be reached on loopback.
  - for HTTP-like aliases, optional entry URL diagnosis can distinguish DNS/connection/HTTP-host failures.
- 当 pid 存在但本地转发端口不可达，应转为 `重连中` 或 `异常`，并显示原因。
- 当 pid 已退出，应继续沿用现有 recovery 流程。

### P0: Runtime events and command diagnostics

- 启动隧道时记录结构化事件：
  - rule id / runtime id / host id / provider target id
  - OpenSSH command summary
  - local bindings
  - provider target label
  - started/observed timestamp
  - start result
- OpenSSH 启动失败或快速退出时，日志应包含可诊断的 detail。
- 后续刷新观测到断联、端口不可达、pid 消失时，应追加结构化事件。
- 日志与诊断页应优先消费 Rust core/bridge 返回的真实事件，不再只由 Swift 从 snapshot 临时拼文本。

### P1: Latency display should be provider-target/host scoped first

- 延迟不要默认重复显示在同一 SSH provider target 下的每条规则行。
- 第一版优先在主机组 header 或 provider target 摘要中显示延迟/健康摘要。
- 行级 telemetry 保留运行时长、失败次数和必要异常摘要；只有当某条规则的端口健康检查与其它规则不同，才显示行级差异。

### P1: Localhost alias diagnosis

- RelayDock 需要解释 `127.0.0.1:<port>` 可访问但 `<alias>.localhost:<port>` 不可访问的原因。
- 诊断应区分：
  - alias DNS 解析失败。
  - alias 解析到 IPv6 `::1` 但服务只在 IPv4 路径可用。
  - TCP 连接失败。
  - HTTP 服务返回 Host header / virtual-host 相关错误。
  - 隧道正常，但远端应用不接受该 Host。
- 不应先假设必须修改 `/etc/hosts`；`.localhost` 在 macOS 上通常已经解析到 loopback。

## MVP Proposal

本任务第一轮建议只做“运行态可信度 + 真实日志骨架”，不先重做日志页面布局：

1. Rust core 增加 runtime event 模型和 SQLite 持久化/加载。
2. `start_rule` 记录启动命令、绑定、本次启动结果。
3. `load_run_recovery_snapshot` 在 pid 检查之外，对本地转发端口做 loopback TCP health check。
4. pid 存在但端口不可达时，标记为 `reconnecting` 或 `error`，写入诊断事件，并让 UI 不再显示纯绿色 `运行中`。
5. bridge snapshot 增加必要的 host/provider health 摘要或诊断事件字段。
6. Swift 日志与诊断页先显示真实 runtime events。
7. 延迟展示先做主机/provider target 层，不在每条隧道重复铺开。

## Out Of Scope

- 不实现后台 daemon / launch agent。
- 不实现持续实时日志流。
- 不实现完整 OpenSSH stdout/stderr 长期流式采集；第一版只记录启动结果和可获得的错误摘要。
- 不实现自动修改 `/etc/hosts`。
- 不保证所有 HTTP 应用都能通过 `<alias>.localhost` 工作；RelayDock 只诊断并解释原因。
- 不在本轮重做日志与诊断页面的大布局。

## Acceptance Criteria

- [ ] 网络切换或远端不可达后，刷新运行态不能继续把不可达隧道显示为健康 `运行中`。
- [ ] pid still alive but local forwarded port unreachable 的场景有 Rust 单元测试覆盖。
- [ ] 启动隧道产生可查询的结构化 runtime event。
- [ ] OpenSSH command summary 和 local bindings 能在日志/诊断里看到。
- [ ] 日志与诊断页能展示真实 runtime event，而不是只拼 snapshot。
- [ ] 同一 SSH provider target 下的延迟/健康摘要优先显示在主机/provider 层。
- [ ] `ssh-18317.localhost` 类问题至少能给出诊断结论：DNS / TCP / HTTP Host 之一。
- [ ] `cargo test -p relaydock-core` 通过。
- [ ] `swift build` 通过。
- [ ] `git diff --check` 通过。

## Technical Notes

- Relevant Rust files:
  - `crates/relaydock-core/src/providers.rs`
  - `crates/relaydock-core/src/runtime.rs`
  - `crates/relaydock-core/src/storage.rs`
  - `crates/relaydock-core/src/commands.rs`
- Relevant Swift files:
  - `apps/relaydock/Sources/Bridge/RelayDockBridgeModels.swift`
  - `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
  - `apps/relaydock/Sources/Features/LogsAndDiagnostics/LogsAndDiagnosticsView.swift`
- Existing spec constraint:
  - Rust core owns process lifecycle tracking, status observation, reconnect/recovery decisions, structured diagnostics.
  - Swift shell owns presentation and must not invent its own runtime state machine.
