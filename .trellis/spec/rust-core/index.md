# Rust Core Guidelines

## Overview

Rust core owns RelayDock's domain model, runtime state machine, provider orchestration abstractions, persistence rules, and reusable automation surface.

Rust does not draw UI and does not know SwiftUI view structure.

## Pre-Development Checklist

- Read `documents/03-domain-model.md`.
- Read `documents/04-runtime-state-machine.md`.
- Read `documents/07-port-management-foundation.md` before port work.
- Confirm the new API is coarse-grained enough for Swift/Rust crossing.

## Quality Check

- Domain behavior is testable without launching the macOS app.
- Errors are structured and diagnosable.
- Runtime state changes are explicit and persistable where required.
- No UI wording or layout decisions leak into Rust.

## Guides

- [Directory Structure](./directory-structure.md)
- [Domain And State](./domain-and-state.md)
- [Provider And Process](./provider-and-process.md)
- [Storage And Diagnostics](./storage-and-diagnostics.md)
- [Quality Guidelines](./quality-guidelines.md)
