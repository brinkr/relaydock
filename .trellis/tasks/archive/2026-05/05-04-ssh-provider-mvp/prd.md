# Implement SSH Provider MVP

## Purpose

Implement the first provider path for RelayDock using system OpenSSH.

This task should make the initial runtime model useful without implementing a custom SSH protocol stack.

## Inputs

- `documents/06-provider-and-network-scenarios.md`
- `documents/08-import-export-and-ai.md`
- `documents/10-technology-stack-decision.md`
- `.trellis/spec/project/index.md`
- `.trellis/spec/rust-core/index.md`

## Requirements

- Build SSH command construction from structured rules.
- Start and stop system OpenSSH forwarding processes.
- Observe process status and map failures into structured diagnostics.
- Support reconnect/recovery hooks at the Rust core level.
- Keep provider target labels user-oriented rather than implementation-heavy.

## Non-Goals

- No SSH terminal UI.
- No SFTP/file manager.
- No custom SSH protocol implementation.
- No Tailscale provider implementation in this task.

## Acceptance Criteria

- A rule can be launched through system OpenSSH.
- Process lifecycle can be observed and stopped.
- Failures are represented as structured errors suitable for UI and logs.
