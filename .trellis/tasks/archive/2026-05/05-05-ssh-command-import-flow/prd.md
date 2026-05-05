# Implement SSH command import flow

## Goal

Turn `资源登记` 的 `导入 SSH` entry point from a placeholder into a real native import workflow. The user should be able to paste an existing `ssh -L ...` command for the selected host, let Rust parse the command into structured rule drafts, review/edit those drafts in SwiftUI, and save them into the existing storage-backed registry configuration.

## What I already know

- RelayDock 的正式技术选型仍是 `SwiftUI + AppKit shell + Rust core`.
- `资源登记` 已经有 storage-backed host/rule editing flow.
- `导入 SSH` 仍是 `RegistryPlaceholderSheet`.
- Product docs say first import should allow one-line SSH commands, parse every `-L`, and initially split each forwarded port into an independent service draft.
- Swift shell spec says SSH command parsing must not live in Swift/ViewModel.
- Rust provider spec says pasted SSH strings must not become the source of truth for runtime; import should produce structured `Rule` / port mapping data.
- Current provider target editing slice already creates an SSH target for a host without storing secrets.

## Assumptions (temporary)

- The first import slice should target the currently selected `RegistryHost`.
- The import command should parse local forwards only (`-L` / `LocalForward`) and ignore actual credential material.
- Imported rules should default to the selected host's first SSH provider target when one exists.
- Import should not launch SSH, validate network reachability, or probe credentials.

## Open Questions

None.

## User Decisions

- Use option 1 for the MVP: parse one pasted command into a batch preview, let the user make lightweight edits in that preview, then save all generated rule drafts at once.
- Do not route each parsed forward through a separate rule editor in this slice.

## Requirements

- Replace the `导入 SSH` placeholder sheet with a functional SwiftUI-native sheet.
- Add a coarse-grained Rust bridge command such as `parse_ssh_command`.
- Rust parses pasted SSH commands into structured import results:
  - host/login hints when derivable
  - provider target hint when derivable
  - one rule draft candidate per `-L` forward
  - validation diagnostics for unsupported or malformed forwards
- Support common OpenSSH local-forward forms:
  - `-L 3000:127.0.0.1:3000`
  - `-L3000:localhost:3000`
  - `-L 127.0.0.1:3000:127.0.0.1:3000`
  - multiple `-L` entries in one command
- Swift sheet should show parse errors inline and keep the pasted command editable.
- Swift sheet should show a batch preview of generated rule drafts and let the user lightly edit rule name, alias, remote host, local port, remote port, kind, and tags before saving.
- The first slice should save all previewed rule drafts together from the import sheet.
- Saving imported rules must use the existing storage-backed `save_registry_rule` path so persistence and reload behavior stays shared.
- The parser and bridge response must not store raw pasted command strings as the runtime source of truth.
- User-facing copy remains Chinese-first.

## Acceptance Criteria

- [ ] `导入 SSH` opens a real import sheet, not the placeholder.
- [ ] Pasting a command with multiple `-L` forwards produces multiple rule draft rows.
- [ ] The import preview supports batch save of all generated rule drafts.
- [ ] The first slice saves imported rules into the selected host and they remain visible after `重新检查`.
- [ ] Rust unit tests cover supported `-L` forms, multiple forwards, and malformed input.
- [ ] Bridge errors or parser diagnostics appear in the sheet rather than failing silently.
- [ ] `swift build`, `cargo test -p relaydock-core`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, and `git diff --check` pass.
- [ ] Visual QA captures `资源登记` after importing at least one rule through the new sheet.

## Definition of Done

- Tests added/updated for parser and command behavior.
- Native import sheet compiles and saves through existing registry persistence.
- Bridge/spec docs updated if command contracts change.
- Visual QA rerun after the import flow lands.

## Out of Scope

- Real SSH credential validation or Keychain integration.
- Running or testing the imported SSH command.
- SSH config file parsing beyond the pasted command.
- Remote command execution, `-R`, `-D`, agent forwarding, terminal sessions.
- AI-generated service names/icons beyond deterministic local defaults.
- Merging several forwards into one service with secondary ports.
- Per-forward full-screen or separate-sheet rule editing.

## Technical Notes

- Likely Swift files:
  - `apps/relaydock/Sources/Features/Registry/RegistryView.swift`
  - `apps/relaydock/Sources/Shell/RelayDockShellViewModel.swift`
  - bridge model / executor files under `apps/relaydock/Sources/Bridge/`
- Likely Rust files:
  - `crates/relaydock-core/src/commands.rs`
  - possibly a new parser module under `crates/relaydock-core/src/`
- Specs/docs read:
  - `documents/08-import-export-and-ai.md`
  - `documents/06-provider-and-network-scenarios.md`
  - `.trellis/spec/swift-shell/state-and-viewmodel-boundaries.md`
  - `.trellis/spec/rust-core/provider-and-process.md`
  - `.trellis/spec/bridge/boundary-rules.md`
