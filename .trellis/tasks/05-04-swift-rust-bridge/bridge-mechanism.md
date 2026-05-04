# Swift/Rust Bridge Mechanism

## First Mechanism

The first RelayDock Swift/Rust bridge is a JSON sidecar command process.

Swift owns the macOS shell and calls a configurable `relaydock-bridge` executable
with one coarse command encoded as JSON. Rust core executes the command and writes
one JSON response envelope to stdout:

- `ok: true` plus a structured command result
- `ok: false` plus a structured bridge error

The first command is `check_port_claim`. It wraps the existing Rust `ports`
conflict primitives and returns:

- requested `PortClaim`
- `available`
- optional `PortConflict`
- optional `suggested_port`

## Why Sidecar First

Static or dynamic FFI would force ABI, linking, packaging, and Swift module
decisions before the command contracts have proven themselves. A JSON sidecar is
slower than direct FFI, but it is reliable for the first bridge slice because it:

- compiles independently with `cargo test` and `swift build`
- keeps Rust free of SwiftUI/AppKit knowledge
- keeps Swift free of Rust ABI/linker details
- preserves machine-readable error codes and diagnostic detail
- can become a CLI or automation surface later

## Future FFI Replacement

FFI can replace the process boundary after command envelopes stabilize. The FFI
layer should preserve the same coarse command/result/error semantics so Swift UI
state does not depend on Rust internals or low-level transport details.
