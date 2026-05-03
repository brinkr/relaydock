# Bootstrap Task: Adapt Trellis To RelayDock

RelayDock has been initialized with Trellis in from-scratch mode. The default
Trellis scaffold is intentionally adapted to this project's real architecture
instead of keeping generic frontend/backend web-app conventions.

## Status

- [x] Initialize Trellis with Codex support
- [x] Replace generic frontend/backend specs with RelayDock layers
- [x] Record SwiftUI/AppKit shell constraints
- [x] Record Rust core constraints
- [x] Record Swift/Rust bridge constraints
- [x] Record project-level Trellis usage constraints

## RelayDock Spec Layers

- `.trellis/spec/project/`
- `.trellis/spec/swift-shell/`
- `.trellis/spec/rust-core/`
- `.trellis/spec/bridge/`
- `.trellis/spec/guides/`

## Source Documents

These product documents remain the source of truth:

- `documents/01-product-baseline.md`
- `documents/03-domain-model.md`
- `documents/04-runtime-state-machine.md`
- `documents/05-ui-information-architecture.md`
- `documents/07-port-management-foundation.md`
- `documents/10-technology-stack-decision.md`
- `documents/11-localport-prototype-reference.md`

## Completion

Archive this task after committing the Trellis initialization.
