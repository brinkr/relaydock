# Define Rust Core Domain And State Interfaces

## Purpose

Define the first Rust core boundary for RelayDock's domain model and runtime state machine.

This task should turn the product/domain documents into concrete Rust-facing interfaces without starting UI work.

## Inputs

- `documents/03-domain-model.md`
- `documents/04-runtime-state-machine.md`
- `documents/07-port-management-foundation.md`
- `documents/10-technology-stack-decision.md`
- `.trellis/spec/project/index.md`
- `.trellis/spec/rust-core/index.md`

## Requirements

- Create the initial Rust core crate structure.
- Define domain types for Host, ProviderTarget, Rule/Service, Preset, RuntimeInstance, RecoveryItem, LocalPortBinding, LocalPortOverride, PortUsage, and PortClaim.
- Define runtime state transitions for start, stop, reconnecting, failed, recoverable, recovered, and cleared states.
- Represent temporary local port overrides as session-scoped by default.
- Add unit tests for parsing-independent domain/state behavior.
- Keep the API reusable for future CLI/agent integrations.

## Non-Goals

- No SwiftUI/AppKit implementation.
- No SSH process orchestration yet.
- No SQLite implementation yet.
- No FFI bridge yet.

## Acceptance Criteria

- Rust domain/state code compiles and has focused unit tests.
- State transitions are explicit and documented in code or tests.
- The implementation does not contain UI layout or Swift-specific concepts.
