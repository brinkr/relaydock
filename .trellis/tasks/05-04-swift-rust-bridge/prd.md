# Establish Swift Rust Bridge

## Purpose

Establish the minimal boundary between Swift shell and Rust core.

The bridge should expose coarse-grained commands and structured results so Swift can remain a native shell while Rust owns domain/runtime behavior.

## Inputs

- `documents/10-technology-stack-decision.md`
- `.trellis/spec/project/index.md`
- `.trellis/spec/bridge/index.md`
- `.trellis/spec/swift-shell/index.md`
- `.trellis/spec/rust-core/index.md`

## Requirements

- Choose and document the first bridge mechanism.
- Expose initial command shapes for domain/runtime operations.
- Define structured success and error return conventions.
- Add a minimal smoke path from Swift to Rust if both projects exist.
- Keep the boundary coarse-grained and command-oriented.

## Non-Goals

- No fine-grained UI event bridge.
- No provider process implementation.
- No large SDK abstraction before the first working path proves itself.

## Acceptance Criteria

- Bridge direction and file ownership are clear.
- Errors preserve machine-readable code and diagnostic detail.
- Rust core does not know SwiftUI view structure.
