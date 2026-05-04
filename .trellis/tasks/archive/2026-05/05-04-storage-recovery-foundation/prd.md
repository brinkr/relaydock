# Implement Storage And Recovery Foundation

## Purpose

Design and implement the local persistence foundation for RelayDock configuration, runtime snapshots, and recovery collection.

## Inputs

- `documents/03-domain-model.md`
- `documents/04-runtime-state-machine.md`
- `documents/07-port-management-foundation.md`
- `documents/10-technology-stack-decision.md`
- `.trellis/spec/project/index.md`
- `.trellis/spec/rust-core/index.md`

## Requirements

- Establish SQLite-backed storage structure for persisted configuration.
- Define runtime snapshot and recovery collection persistence.
- Keep sensitive credentials out of ordinary SQLite.
- Support future import/export validation.
- Preserve the distinction between saved rule configuration and session-only local port overrides.

## Non-Goals

- No full settings UI.
- No cloud sync.
- No account system.
- No provider runtime execution.

## Acceptance Criteria

- Storage schema and migration ownership are clear.
- Recovery items can be represented and persisted.
- Temporary local port overrides do not silently mutate saved rules.
