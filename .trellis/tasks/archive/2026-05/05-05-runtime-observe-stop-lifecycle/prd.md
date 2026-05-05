# Add observable stoppable runtime lifecycle

## Goal

让 `start_rule` 启动后的运行实例具备最小真实生命周期：后续 `load_run_recovery_snapshot` 能通过持久化的 provider pid 观察 OpenSSH 是否仍在运行，`stop_runtime_instance` 能通过 pid 停止对应进程，并把运行实例转为可恢复项。

## What I Already Know

* 当前 `start_rule` 已经能从 SQLite 资源登记配置解析 Host / Rule / ProviderTarget，调用 OpenSSH provider 启动一次，并保存 `RuntimeSnapshot`。
* 当前 JSON sidecar 是 one-command-per-process，不能长期持有 Rust `Child` handle。
* Rust core 已有 `RuntimeSnapshot`、`RecoveryCollection`、`RuntimeInstance::stop`、`OpenSshProvider`、`ProviderProcess` 和 `SystemProviderProcess` 概念。
* 当前 Swift 运行页的 `停止` / `重试` / `清除` 仍走 demo action 路径。
* `load_run_recovery_snapshot` 已经能把 persisted runtime instance 投影成 `connected` 行，但不会检查进程是否仍然存在。

## MVP Decision

本任务不引入常驻 daemon，也不把 sidecar 改造成长连接服务。

本任务采用保守 MVP：

* 在 runtime persistence 中保存 provider process metadata，例如 `pid`、provider kind、启动命令摘要。
* `start_rule` 启动 OpenSSH 并观察为 running 时，保存 runtime instance + process metadata。
* `load_run_recovery_snapshot` 读取 runtime snapshot 后，基于 pid 做一次轻量观察：
  * pid 仍存在 -> 保留/标记 connected；
  * pid 不存在 -> 标记 error 或转入 recovery collection，具体按实现中最小安全路径处理。
* `stop_runtime_instance` 通过 pid 终止 OpenSSH，移除 runtime instance，写入 `RecoveryCollection`，返回完整 `run_recovery_snapshot`。

## Requirements

* Add bridge command `stop_runtime_instance`.
* Add Swift bridge model/executor/view model path for `stopRuntimeInstance(runtimeId:)`.
* Replace run/recovery row stop action from demo stop to real `stop_runtime_instance`.
* Rust runtime persistence must include enough process metadata to observe/stop a started provider after the starting sidecar exits.
* `start_rule` must save provider process metadata when the launched process exposes a pid.
* `load_run_recovery_snapshot` must reconcile persisted runtime state against process metadata before returning rows.
* `stop_runtime_instance` must:
  * find runtime instance by `runtime_id`;
  * find provider process metadata;
  * terminate the process by pid when possible;
  * convert the stopped runtime to a `RecoveryItem`;
  * remove the runtime instance from `RuntimeSnapshot`;
  * append/upsert recovery item in `RecoveryCollection`;
  * return a full `RunRecoverySnapshotResult`.
* Missing runtime or missing pid metadata must return structured bridge errors.

## Acceptance Criteria

* [ ] Rust tests cover saving provider process metadata during `start_rule`.
* [ ] Rust tests cover `load_run_recovery_snapshot` reconciling a missing process into non-connected state.
* [ ] Rust tests cover `stop_runtime_instance` removing a runtime and adding a recovery item using a mock process controller.
* [ ] Swift build compiles with real stop path wired from `RunAndRecoveryView`.
* [ ] `cargo test -p relaydock-core`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, `swift build`, and `git diff --check` pass.

## Definition Of Done

* Implementation is committed with document-style commit message.
* Bridge and Rust-core specs document pid-backed lifecycle MVP and its limitations.
* Task is archived and journaled after the work commit.

## Out Of Scope

* Long-running RelayDock daemon / launch agent.
* Continuous log streaming.
* Auto reconnect scheduler.
* Full process tree management beyond the provider pid recorded by RelayDock.
* Tailscale provider lifecycle.
* Keychain credential prompting.

## Technical Notes

* Likely Rust files:
  * `crates/relaydock-core/src/runtime.rs`
  * `crates/relaydock-core/src/providers.rs`
  * `crates/relaydock-core/src/storage.rs`
  * `crates/relaydock-core/src/commands.rs`
* Likely Swift files:
  * `apps/relaydock/Sources/Bridge/RelayDockBridgeModels.swift`
  * `apps/relaydock/Sources/Bridge/RelayDockBridgeExecutor.swift`
  * `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  * `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
* Specs/docs:
  * `.trellis/spec/bridge/boundary-rules.md`
  * `.trellis/spec/rust-core/provider-and-process.md`
  * `.trellis/spec/rust-core/storage-and-diagnostics.md`
  * `.trellis/spec/rust-core/domain-and-state.md`
  * `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  * `documents/04-runtime-state-machine.md`
  * `documents/07-port-management-foundation.md`
