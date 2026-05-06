# Implement Real Retry Action

## Goal

Move the run/recovery `重试` action from demo snapshot mutation to a real Rust-owned bridge command backed by persisted runtime/provider state. After this task, app-facing retry should no longer submit the current `RunRecoverySnapshotResult` back to Rust.

## What I Already Know

- RelayDock uses SwiftUI + AppKit shell with a Rust core reached through a JSON sidecar bridge.
- `start_rule`, `stop_runtime_instance`, `recover_item`, `apply_local_port_override`, and `clear_recovery_item` now exist as real bridge commands.
- `运行与恢复` still routes row retry through `retryDemoRuntime(runtimeId:snapshot:)`.
- Swift bridge models/executor still expose demo action commands as app-facing methods.
- Rust still keeps deterministic demo snapshot commands for legacy tests/smoke behavior.
- Runtime rows already distinguish `connected`, `reconnecting`, `error`, and `recoverable`.

## Requirements

- Add a real bridge command named `retry_runtime_instance`.
- The command input is `runtime_id`; it must not require or accept a Swift-submitted snapshot.
- Rust must load the store, find the persisted runtime instance, and allow retry only for `RuntimeStatus::Reconnecting` or `RuntimeStatus::Error`.
- Real retry should use the runtime's existing rule/provider/local bindings to launch OpenSSH again, observe the provider, persist fresh provider pid metadata, clear the previous runtime error on success, and return a fresh `run_recovery_snapshot`.
- If retry launch reports provider diagnostics or cannot persist pid metadata, return structured bridge errors/status without silently converting the runtime to connected.
- Swift run/recovery retry actions should call `retryRuntimeInstance(runtimeId:)`, not `retryDemoRuntime(runtimeId:snapshot:)`.
- Registry rule-level retry should keep routing through the run/recovery runtime lookup and then the real runtime retry command.
- Remove or quarantine app-facing Swift demo action methods if they are no longer used by the app. Demo Rust helpers may remain for deterministic tests only if needed.

## Acceptance Criteria

- [ ] Clicking `重试` from `运行与恢复` calls `retry_runtime_instance` through the Swift bridge without submitting a snapshot.
- [ ] `retry_runtime_instance` succeeds only for persisted runtime rows in `reconnecting` or `error` state.
- [ ] Successful retry persists a new provider pid record and returns a connected row with no row error.
- [ ] Retry failure preserves structured diagnostic information and does not fake a connected row.
- [ ] Invalid runtime id, missing runtime, non-retryable status, and missing pid metadata paths are covered by Rust tests.
- [ ] Swift app builds after demo retry methods are removed or quarantined from app-facing code.
- [ ] Existing real recover/override/clear actions keep passing.
- [ ] Existing visual QA still captures all four primary shell pages successfully.

## Definition Of Done

- `cargo fmt --check`
- `cargo clippy -p relaydock-core --all-targets -- -D warnings`
- `cargo test -p relaydock-core`
- `swift build`
- `git diff --check`
- `scripts/visual-qa/relaydock-window-snapshot.sh`
- Update `.trellis/spec/` if the task establishes a new retry/runtime lifecycle contract.

## Out Of Scope

- No automatic reconnect scheduler.
- No daemon, LaunchAgent, process tree supervisor, or provider log streaming.
- No Tailscale provider integration.
- No Keychain or system permission implementation.
- No JSON sidecar to FFI migration.
- No UI restyling beyond replacing demo method names and wiring.
- No broad removal of Rust demo snapshot helpers unless required to keep app-facing code honest.

## Technical Notes

- `stop_runtime_instance` and real recovery actions are the templates for store-backed command shape and error handling.
- `ProviderProcessRecord` is required for retry persistence under the JSON sidecar MVP.
- Retrying should preserve current runtime local bindings, including session-local overrides.
- `.trellis/spec/rust-core/provider-and-process.md` already records that persisted runtime state without pid metadata is invalid for later observation.
