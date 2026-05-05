# Connect run recovery workspace to saved registry configuration

## Goal

让 `运行与恢复` 工作区开始读取已经保存到资源登记 SQLite 配置里的主机和规则，而不是继续完全依赖 Rust 中的硬编码 demo snapshot。这个任务的目标是打通“资源登记 -> bridge -> 运行页”的真实数据链路，为后续真实 SSH provider 启停打基础。

## What I Already Know

* 项目技术栈固定为 `SwiftUI + AppKit shell + Rust core`。
* `资源登记` 已经可以通过 `load_registry_snapshot` / `save_registry_host` / `save_registry_rule` 读写 SQLite。
* `导入 SSH` 已经可以把多个 `-L` / `LocalForward` 解析成规则草稿，并保存到资源登记。
* 当前 `load_run_recovery_snapshot()` 仍返回硬编码 demo hosts/rows。
* 运行页 Swift UI 已经能渲染 host-grouped `RunRecoverySnapshotResult`，并支持 `recover` / `retry` / `stop` / `clear` / `change_local_port` 这些行级动作。

## Assumptions

* 本任务先做配置投影，不在这一刀里启动真实 OpenSSH 进程。
* 没有持久化 runtime/recovery 集合之前，保存的规则在运行页中先显示为 `recoverable` 候选，以便用户能从运行页看到资源登记结果并验证数据链路。
* 现有 demo action commands 可以继续作为 snapshot-local 交互，占位真实 `start_rule` / `stop_runtime_instance` 之前的 UI 行为。

## Requirements

* `load_run_recovery_snapshot` must load the same SQLite-backed configuration used by `load_registry_snapshot`.
* Empty storage must return an empty `run_recovery_snapshot`, not fallback demo rows.
* Saved hosts with saved rules must appear in `运行与恢复` grouped by host.
* Projected rows must use the existing bridge state contract:
  * `state = recoverable`
  * `runtime_id = null`
  * `recovery_id` stable enough for snapshot-local clear
  * actions include `恢复`, `改本地端口`, `清除`
* Host endpoint, provider summary, service name, alias, provider label, and port summary must be derived from the persisted domain configuration.
* Bridge/storage failures must return structured bridge errors instead of silent demo fallback.
* Swift must not invent registry-to-runtime projection rules; the snapshot remains Rust-owned.

## Acceptance Criteria

* [ ] Saving a host and at least one rule through the existing registry commands, then calling `load_run_recovery_snapshot`, returns that host and rule in the run/recovery snapshot.
* [ ] Empty SQLite storage returns `hosts: []` and summary message `没有运行或待恢复项目`.
* [ ] Rust tests assert the projected snapshot row count, `recoverable` state, provider label, alias, and port summary.
* [ ] Existing demo action tests still cover snapshot-local recover/retry/stop/clear behavior.
* [ ] `swift build`, `cargo test -p relaydock-core`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, and `git diff --check` pass.

## Definition Of Done

* Implementation is committed with the project’s document-style commit message.
* `.trellis/spec/bridge/boundary-rules.md` records the new `load_run_recovery_snapshot` projection contract.
* Task context files identify the specs/documents needed by implementation and check agents.

## Out Of Scope

* Launching real SSH/Tailscale provider processes.
* Persisting runtime instances, recovery collections, logs, uptime, latency, or failure counts.
* Replacing demo action commands with durable `start_rule`, `stop_runtime_instance`, `recover_item`, or `clear_recovery_item`.
* Changing the overall navigation or LocalPort visual reference boundary.

## Technical Notes

* Likely Rust files:
  * `crates/relaydock-core/src/commands.rs`
  * `crates/relaydock-core/src/storage.rs` only if existing store APIs are insufficient
* Likely Swift files:
  * `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  * `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
  * Swift changes should stay minimal if the existing bridge result shape remains unchanged.
* Relevant specs/docs:
  * `.trellis/spec/project/index.md`
  * `.trellis/spec/bridge/boundary-rules.md`
  * `.trellis/spec/rust-core/index.md`
  * `.trellis/spec/rust-core/domain-and-state.md`
  * `.trellis/spec/rust-core/storage-and-diagnostics.md`
  * `.trellis/spec/swift-shell/index.md`
  * `.trellis/spec/swift-shell/ui-patterns.md`
  * `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  * `documents/03-domain-model.md`
  * `documents/04-runtime-state-machine.md`
  * `documents/05-ui-information-architecture.md`
  * `documents/07-port-management-foundation.md`
