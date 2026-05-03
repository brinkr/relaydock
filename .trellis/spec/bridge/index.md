# Swift/Rust Bridge Guidelines

## Overview

The bridge is the boundary between the native Swift shell and Rust core.

It should be coarse-grained, stable, and easy to test.

## Pre-Development Checklist

- Confirm the behavior belongs across the boundary rather than wholly in Swift or Rust.
- Read `documents/10-technology-stack-decision.md`.
- Check the relevant `swift-shell` and `rust-core` spec files.

## Quality Check

- Calls are command-like, not UI-event-like.
- Return values are structured snapshots or command results.
- Errors map cleanly to user-facing messages and diagnostic logs.
- The bridge does not force Rust to know SwiftUI view structure.

## Guides

- [Boundary Rules](./boundary-rules.md)
- [Error Mapping](./error-mapping.md)
