# Implement Runnable End-To-End Flow

## Goal

Make RelayDock stop being a static shell by implementing the first runnable vertical slice from Swift UI action to Swift bridge to Rust core and back into visible Run/Recovery state.

This task exists because the project now has Rust core domain, storage, provider, and JSON bridge pieces, but the app still does not let the user exercise a real flow. The priority is to make one workflow observable and testable end to end, not to finish every provider feature.

## What I Already Know

- The user explicitly said the workflow is not wired through and functionality is still far from enough.
- The current Run/Recovery view is static mock UI.
- `RelayDockShellViewModel` only owns sidebar selection and a fixed status summary.
- Swift bridge currently supports only `check_port_claim`.
- Rust core already has:
  - domain model (`Host`, `ProviderTarget`, `Rule`, `RuntimeInstance`, `RecoveryItem`)
  - storage foundation (`RelayDockStore`, snapshots, recovery collection)
  - OpenSSH provider launch planning and process abstraction
  - JSON sidecar command transport
- A full real OpenSSH launch can depend on host-specific credentials and reachable targets, so it should not be the first UI-visible success criterion.

## Requirements

- Replace the static Run/Recovery mock data with ViewModel-owned runtime rows sourced from a bridge call.
- Add bridge commands that return a structured demo runtime snapshot and support actions:
  - load run/recovery snapshot
  - start/recover a demo rule
  - stop a running demo runtime
  - clear a recovery item
- Keep Swift UI state as presentation state only; domain transitions should be produced by Rust bridge commands.
- Surface structured bridge/provider errors into visible row/status text instead of silently failing.
- Keep the visual shell native and compact; no dashboard/landing page detour.
- Provide deterministic tests/smoke paths that do not require a real SSH server.

## Acceptance Criteria

- [x] Launching the app shows Run/Recovery rows loaded through bridge-backed state rather than hardcoded static rows inside `RunAndRecoveryView`.
- [x] Clicking `恢复` changes a recoverable demo row into a running row through a Rust bridge command.
- [x] Clicking `停止` changes a running demo row into a recoverable row through a Rust bridge command.
- [x] Clicking `清除` removes a recoverable row through a Rust bridge command.
- [x] Status bar summary updates from the same ViewModel state.
- [x] Rust bridge sidecar smoke can exercise load/start/stop/clear commands without a real SSH server.
- [x] `swift build`, `cargo test`, `cargo clippy --all-targets -- -D warnings`, `git diff --check`, and visual QA pass.

## Out Of Scope

- Real SSH credentials, Keychain integration, or actually connecting to the user's machines.
- Long-running background supervision of real OpenSSH processes.
- Registry editing UI.
- Importing pasted SSH commands.
- Tailscale provider.
- Packaging the sidecar into a signed app bundle.

## Technical Notes

- The first vertical slice should prefer deterministic demo runtime commands over real SSH process launch so UI state can be verified on every machine.
- The Rust command layer should stay coarse-grained and command-oriented.
- Swift models may add Run/Recovery display DTOs that mirror Rust command results, but SwiftUI views should not invent provider/runtime state machines.
- The existing visual QA script should continue to be used after UI changes.

## Verification Notes

- Visual QA screenshot: `artifacts/visual-qa/relaydock-window-20260505-013201.png`.
- Manual Computer Use interaction verified `恢复` -> `停止` -> `清除` against the temporary visual QA app.
