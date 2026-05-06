# Implement Real Recovery Actions

## Goal

Make run/recovery row actions use real Rust-owned recovery state instead of demo snapshot transitions. After a saved rule has been stopped or projected as recoverable, `恢复`, `改本地端口`, and `清除` should go through bridge commands backed by SQLite runtime/recovery state and return a fresh `RunRecoverySnapshotResult`.

## What I Already Know

- RelayDock is a native SwiftUI + AppKit shell with a Rust core reached through the JSON sidecar bridge.
- `start_rule` and `stop_runtime_instance` already exist as non-demo bridge commands.
- `stop_runtime_instance` persists a `RecoveryItem` after terminating the recorded provider pid.
- `load_run_recovery_snapshot` projects saved registry rules as recoverable candidates when no runtime exists.
- Swift still exposes and calls `retryDemoRuntime`, `clearDemoRecoveryItem`, and `applyDemoLocalPortOverride`.
- Rust still has demo snapshot transition commands for retry/recover/local-port/clear behavior.
- Recovery rows currently expose stable `rule_id`, optional `runtime_id`, optional `recovery_id`, row state, and action labels.

## Requirements

- Add real bridge commands for:
  - `recover_item`
  - `apply_local_port_override`
  - `clear_recovery_item`
- Real recovery commands must open the Rust-owned store, mutate persisted runtime/recovery state where needed, and return `run_recovery_snapshot`.
- `recover_item` should recover by rule identity from either a persisted `RecoveryItem` or the saved registry rule projected as recoverable.
- `apply_local_port_override` should recover the same item using the provided temporary local port without silently mutating saved rule configuration.
- `clear_recovery_item` should remove a persisted recovery item when one exists; for a projected configured-but-not-running rule, it should not delete the saved registry rule.
- Swift run/recovery actions should call the real command names and executor methods. Do not submit the current snapshot back to Rust for real actions.
- Keep demo helpers only as tests/legacy helpers if still needed; the app-facing run/recovery path must not depend on demo snapshot commands for these actions.

## Acceptance Criteria

- [ ] `恢复` on a recoverable row calls a real `recover_item` bridge command and returns an updated snapshot.
- [ ] `改本地端口` calls a real `apply_local_port_override` bridge command with `rule_id` and `local_port`, and returns an updated snapshot.
- [ ] `清除` calls a real `clear_recovery_item` bridge command, not `clear_demo_recovery_item`.
- [ ] Rust unit tests cover recovering a persisted recovery item into a runtime snapshot.
- [ ] Rust unit tests cover applying a manual local port override without mutating saved rule configuration.
- [ ] Rust unit tests cover clearing a persisted recovery item.
- [ ] Missing/invalid rule, recovery, runtime, and port inputs return structured bridge errors rather than silent snapshot edits.
- [ ] Swift builds with the new command models and executor methods.
- [ ] Existing visual QA still captures all four primary shell pages successfully.

## Definition Of Done

- `cargo test -p relaydock-core`
- `swift build`
- `git diff --check`
- `scripts/visual-qa/relaydock-window-snapshot.sh`
- Applicable Trellis specs updated if new bridge/runtime conventions are discovered.

## Out Of Scope

- No daemon, LaunchAgent, process tree supervisor, reconnect scheduler, or provider log streaming.
- No Tailscale provider integration.
- No Keychain or system permission implementation.
- No migration from JSON sidecar to FFI.
- No broad redesign of demo helpers unless required to keep tests coherent.
- No UI restyling except label/method renames needed to route real actions.

## Technical Notes

- Real bridge command shape is documented in `.trellis/spec/bridge/boundary-rules.md`.
- Runtime/recovery ownership is documented in `.trellis/spec/rust-core/domain-and-state.md` and `.trellis/spec/rust-core/provider-and-process.md`.
- Swift action labels and run/recovery layout rules are documented in `.trellis/spec/swift-shell/ui-patterns.md`.
- `RecoveryItem::recover` already creates a new `RuntimeInstance` from previous local bindings.
- `RuntimeInstance::apply_local_port_override` exists but should remain session/runtime scoped.
