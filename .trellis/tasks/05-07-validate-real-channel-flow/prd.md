# Validate Real Channel Flow Before Redesigning Logs

## Goal

Use the real RelayDock bridge and SQLite-backed registry/runtime path to create and exercise a real channel flow before redesigning `日志与诊断`. The immediate objective is to expose what the app actually needs to log or diagnose during real host/rule setup, recovery, provider launch, reload, and stop flows.

## What I Already Know

- The current `日志与诊断` UI is visually over-split for a compact desktop workspace. It can read as global sidebar + internal scope list + main workspace + right inspector, which is too much structure for the current MVP window.
- The LocalPort prototype shows a simpler dark console-like diagnostics page with a compact summary/filter strip, but RelayDock should not copy React/Tailwind structure directly.
- The user wants to record the Logs/Diagnostics problem now, not redesign it immediately.
- Visual QA screenshots use `RELAYDOCK_VISUAL_QA_FIXTURE=prototype-density`, so those screenshots intentionally show fixture data.
- Normal Swift shell loading uses the bridge unless visual QA fixtures are active.
- Production bridge storage defaults to `~/Library/Application Support/RelayDock/relaydock.sqlite3`; `RELAYDOCK_STORE_PATH` can override it for QA.
- Rust production command dispatch routes `load_run_recovery_snapshot`, `load_registry_snapshot`, `save_registry_host`, `save_registry_rule`, `start_rule`, and `stop_runtime_instance` through SQLite-backed store paths outside test builds.

## Problem Record: Logs And Diagnostics

The current Logs/Diagnostics page has a known information architecture risk:

- It divides a small page into too many simultaneous panes.
- It was designed before enough real provider/runtime failures existed.
- It may be showing derived bridge/runtime summaries instead of the diagnostic events users will actually need when real channel operations fail.

Decision for this task:

- Do not redesign the Logs/Diagnostics UI yet.
- Record this as a follow-up area.
- First run realistic channel operations and collect the specific diagnostic facts that the UI must expose.

## Requirements

### Real Store And Bridge

- Verify normal bridge commands use the SQLite-backed store when visual QA fixtures are not active.
- Use `RELAYDOCK_STORE_PATH` with an isolated QA database for repeatable tests unless intentionally testing the user's default app data.
- Confirm empty storage returns empty registry and run/recovery snapshots rather than seeded demo rows.

### Real Channel Setup

- Create or import at least one SSH-backed host and forwarding rule through the same bridge contracts used by the app.
- Reload `资源登记` and `运行与恢复` from the store and confirm the saved rule projects as a recoverable runtime candidate.
- Exercise `start_rule` against a real provider path. If authentication or host reachability prevents success, capture the structured bridge error and decide what the UI needs to show.
- If `start_rule` succeeds, verify reload reconciliation and `stop_runtime_instance`.

### Diagnostic Evidence

- Record actual bridge responses, structured errors, and user-visible state transitions observed during the test.
- Identify concrete gaps in the current Logs/Diagnostics page only after those observations.
- Keep diagnostic findings separate from visual-style complaints.

## Acceptance Criteria

- [x] A Trellis note captures the current Logs/Diagnostics UI issue and the decision to defer redesign until real test evidence exists.
- [x] Bridge command tests confirm empty-store behavior for registry and run/recovery snapshots.
- [x] A real host/rule is saved into an isolated SQLite store through bridge commands.
- [x] Reloading registry and run/recovery shows persisted configuration-derived state, not fixture/demo rows.
- [x] `start_rule` is exercised and its success or structured failure is recorded.
- [x] If a runtime starts, reload and stop behavior is exercised and recorded.
- [x] Follow-up tasks are listed only for confirmed gaps discovered during real channel testing.
- [x] `swift build`, relevant Rust tests or bridge smoke commands, and `git diff --check` pass after any code changes.

## Out Of Scope

- Redesigning `日志与诊断` before real channel evidence exists.
- Replacing the SwiftUI/AppKit shell or copying LocalPort React code.
- Adding a daemon, launch agent, process supervisor, or streaming log subsystem.
- Storing secrets or private SSH material in SQLite.
- Using visual QA fixtures as proof of production data behavior.

## Technical Notes

- Key Swift shell files:
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - `apps/relaydock/Sources/Features/LogsAndDiagnostics/LogsAndDiagnosticsView.swift`
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `apps/relaydock/Sources/Features/RunAndRecovery/RunAndRecoveryView.swift`
- Key Rust/bridge files:
  - `crates/relaydock-core/src/commands.rs`
  - `crates/relaydock-core/src/storage.rs`
  - `crates/relaydock-core/src/providers.rs`
  - `crates/relaydock-core/src/bin/relaydock-bridge.rs`
- Relevant specs:
  - `.trellis/spec/project/index.md`
  - `.trellis/spec/bridge/boundary-rules.md`
  - `.trellis/spec/rust-core/storage-and-diagnostics.md`
  - `.trellis/spec/swift-shell/ui-patterns.md`
- Evidence:
  - `research/real-bridge-smoke-2026-05-07.md` records the first isolated SQLite-backed bridge smoke test.

## Current Findings

- Empty isolated production store returns empty snapshots, not demo data.
- Saving a host and rule through bridge commands persists registry configuration and projects a recoverable row in `运行与恢复`.
- Localhost SSH was not reachable in this environment (`nc -z 127.0.0.1 22` returned `1`), but `start_rule` still briefly returned a connected row before reload reconciliation moved it to a persisted recovery item.
- After reconciliation, `stop_runtime_instance` correctly returned a structured `runtime_lifecycle_failed` error because the runtime was already gone.
- A reachable `macminim4` SSH config target completed the full lifecycle: save host/rule, project recoverable row, start real OpenSSH forwarding process, reload as connected, stop persisted pid, reload as recoverable.

## Remaining Work

- Convert confirmed diagnostic gaps into a later Logs/Diagnostics information architecture task. Do not redesign `日志与诊断` from prototype visuals alone.
- Consider a provider lifecycle improvement task for short-lived OpenSSH starts that report connected before the next reload reconciles them into recovery.
