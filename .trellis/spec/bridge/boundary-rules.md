# Boundary Rules

Recommended command shape:

- `parse_ssh_command`
- `scan_ports`
- `start_rule`
- `stop_runtime_instance`
- `recover_item`
- `apply_local_port_override`
- `clear_recovery_item`

Avoid sending high-frequency UI events across the boundary.

Prefer:

- Swift sends a clear command with stable IDs and inputs
- Rust returns a structured result
- Swift renders the result and manages presentation state

Do not design the bridge around LocalPort's React component props.

## First Transport: JSON Sidecar Command

### 1. Scope / Trigger

- Trigger: Swift shell needs the first compiled bridge to Rust core before FFI packaging is stable.
- Transport: Swift launches a configurable `relaydock-bridge` sidecar process and sends one JSON command on stdin.
- Ownership: Rust owns command execution and response envelopes; Swift owns process launch, decoding, and UI presentation.

### 2. Signatures

Rust command envelope:

```json
{
  "command": "check_port_claim",
  "claim": {
    "port": 8088,
    "protocol": "Tcp",
    "owner_type": "RelayDockRuntime",
    "owner_ref": "runtime-1"
  },
  "known_usages": []
}
```

Swift entrypoint:

```swift
RelayDockBridgeExecutor(executableURL: bridgeURL)
    .checkPortClaim(CheckPortClaimCommand(...))
```

### 3. Contracts

- Commands must be coarse-grained and tagged by `command`.
- Results must be tagged by `type`.
- Responses must use one envelope shape:
  - success: `ok: true`, `result: <typed result>`
  - failure: `ok: false`, `error: <typed bridge error>`
- The current JSON sidecar is one command per process and does not hold runtime
  memory between invocations. Demo runtime action commands may submit the last
  Rust-produced snapshot as command input and must return a full next snapshot;
  Swift may store and re-submit that snapshot, but must not invent the runtime
  transition itself.
- `suggested_port` is present only when the requested port conflicts and Rust can suggest another port.
- Rust core must not import Swift, SwiftUI, or AppKit.
- Swift bridge models must stay outside SwiftUI views.

### 4. Validation & Error Matrix

- Empty stdin or missing `command` -> `invalid_command`.
- Malformed JSON -> `invalid_command` with parser detail.
- Sidecar startup failure in Swift -> `process_failed` with executable-path recovery guidance.
- Response JSON decode failure in Swift -> `response_decode_failed` with decoder detail.

### 5. Good/Base/Bad Cases

- Good: one Swift command maps to one Rust domain operation and one typed result.
- Base: `check_port_claim` returns `available: true` with no conflict and no suggestion.
- Bad: Swift sends UI row selection events or React-style component props across the bridge.

### 6. Tests Required

- Rust unit test for each command's success result.
- Rust unit test for structured error envelope serialization.
- Sidecar smoke test for success JSON and malformed-command JSON.
- Swift build must compile bridge models and executor.

### 7. Wrong vs Correct

Wrong:

```json
{"event": "rowClicked", "portText": "8088"}
```

Correct:

```json
{"command": "check_port_claim", "claim": {"port": 8088, "protocol": "Tcp", "owner_type": "RelayDockRuntime", "owner_ref": null}, "known_usages": []}
```
