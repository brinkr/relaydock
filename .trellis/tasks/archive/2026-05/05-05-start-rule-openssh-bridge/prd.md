# Wire start rule bridge command to OpenSSH provider

## Goal

让 `运行与恢复` 的 `恢复` 动作开始走真实 Rust provider 启动路径：从 SQLite 资源登记配置中查找 `rule_id` 对应的 Host / Rule / ProviderTarget，构造并启动系统 OpenSSH 转发，立即观察一次状态，并把产生的 runtime snapshot 持久化。

## What I Already Know

* `资源登记` 已经能保存 Host / ProviderTarget / Rule。
* `load_run_recovery_snapshot` 已经能把保存的规则投影成 `recoverable` 行。
* Rust core 已有 `OpenSshProvider`、`build_openssh_launch_plan`、`start_rule`、`observe_status`、`RuntimeSnapshot` 和 SQLite runtime/recovery 表。
* 当前 Swift 运行页的恢复按钮仍调用 `start_demo_rule`，它只在传入 snapshot 上做内存转移。
* 当前 JSON sidecar bridge 是 one-command-per-process，不会长期持有 OpenSSH child handle。

## Key Constraint

当前 sidecar 不能可靠管理长期运行的 provider 进程句柄。这个任务不能假装完整进程生命周期已经打通。

本任务允许做：

* 调用 `OpenSshProvider::system().start_rule(...)` 启动 OpenSSH。
* 立即 `observe_status(...)` 一次。
* 如果启动并观察为 running，持久化 `RuntimeSnapshot` 中的 `RuntimeInstance`。
* 返回新的 `run_recovery_snapshot`，让对应行从 `recoverable` 变成 `connected` / `error`。

本任务不做：

* 在后续 bridge 命令中停止同一个 child handle。
* 守护 provider 进程、持续观察、自动重连。
* 完整替换 demo stop/clear action。

## Requirements

* Add bridge command `start_rule`.
* Add Swift bridge command/model/executor entrypoint for `startRule(ruleId:)`.
* Rust `start_rule` must:
  * read SQLite-backed `ConfigurationSnapshot`;
  * find host, rule, and provider target by `rule_id`;
  * reject missing rule/host/target with structured errors;
  * reject non-SSH provider target through existing provider diagnostics;
  * launch using structured `Rule` port mappings, not raw imported SSH text;
  * immediately observe process status once;
  * save a `RuntimeSnapshot` when a runtime instance is produced;
  * return a full `RunRecoverySnapshotResult`.
* `load_run_recovery_snapshot` should merge saved runtime snapshot state with config projection when runtime data exists.
* Swift `恢复` should call `startRule(ruleId:)` rather than `startDemoRule`.
* User-facing copy remains Chinese-first and must not mention demo for this path.

## Acceptance Criteria

* [ ] Unit tests cover successful start with a mock provider launcher and persisted runtime snapshot.
* [ ] Unit tests cover missing rule and non-SSH provider target errors.
* [ ] `load_run_recovery_snapshot` projects saved runtime instances as `connected` rows when runtime snapshot exists.
* [ ] Swift build compiles with the new `startRule` bridge path wired into `recover`.
* [ ] `swift build`, `cargo test -p relaydock-core`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, and `git diff --check` pass.

## Definition Of Done

* Implementation is committed with a document-style commit message.
* Bridge spec is updated with `start_rule` command shape, lifecycle limitation, and test expectations.
* Task is archived and journaled after commit.

## Out Of Scope

* Durable process supervisor or daemon architecture.
* `stop_runtime_instance` with actual child-handle termination.
* Auto reconnect or wake-from-sleep recovery.
* Tailscale provider launch.
* Keychain credential prompting or SSH key management UI.

## Technical Notes

* Likely Rust files:
  * `crates/relaydock-core/src/commands.rs`
  * `crates/relaydock-core/src/providers.rs` if a testable launcher injection boundary is needed
  * `crates/relaydock-core/src/storage.rs` if runtime merge helpers are missing
* Likely Swift files:
  * `apps/relaydock/Sources/Bridge/RelayDockBridgeModels.swift`
  * `apps/relaydock/Sources/Bridge/RelayDockBridgeExecutor.swift`
  * `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  * `apps/relaydock/Sources/Shell/RelayDockShellView.swift`
* Relevant specs/docs:
  * `.trellis/spec/bridge/boundary-rules.md`
  * `.trellis/spec/rust-core/provider-and-process.md`
  * `.trellis/spec/rust-core/storage-and-diagnostics.md`
  * `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  * `documents/04-runtime-state-machine.md`
  * `documents/06-provider-and-network-scenarios.md`
  * `documents/08-import-export-and-ai.md`
