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
- `load_run_recovery_snapshot` returns runtime-facing host groups and rows. Rows must use domain states (`connected`, `reconnecting`, `error`, `recoverable`) rather than view names or LocalPort component props.
- `load_registry_snapshot` returns configuration-facing hosts, provider targets, presets, and rules. Runtime state may appear only as a compact summary field on rules; Swift owns which host is selected and how details are laid out.
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
- Rust unit tests for `load_run_recovery_snapshot` and `load_registry_snapshot` must assert row/rule counts and key state variants so UI density regressions are visible.
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

Correct registry snapshot request:

```json
{"command": "load_registry_snapshot"}
```

## Registry Editing Persistence Extension

### 1. Scope / Trigger

- Trigger: `资源登记` stops being a placeholder-only workspace and must save host/rule edits through the bridge into Rust-owned SQLite storage.
- Scope: first editing slice covers `新建资源分组`, `主机设置`, `新增规则`, `编辑映射`, and `编辑规则`.
- Boundary: Swift owns sheet presentation and field editing; Rust owns validation, persistence, and projection back into `registry_snapshot`.

### 2. Signatures

Rust commands:

```json
{"command":"load_registry_snapshot"}
{"command":"save_registry_host","host":{"id":"host-mac-studio","name":"Mac Studio - Office","address":"10.0.4.5","port":22,"user":"admin","tags":["office"],"os_hint":"macos","status":"unknown","provider_targets":[{"id":"target-ssh-office","host_id":"host-mac-studio","provider_kind":"ssh","label":"SSH · 办公室","target_address":"10.0.4.5","target_port":22}]}}
{"command":"save_registry_rule","rule":{"id":"rule-relay-admin","host_id":"host-mac-studio","provider_target_id":"target-ssh-office","name":"Relay Admin","alias":"admin.office.localhost","kind":"web","tags":["admin","office"],"remote_host":"127.0.0.1","main_port":{"local_port":3000,"remote_port":3000},"secondary_ports":[],"notes":null}}
```

Swift entrypoints:

```swift
loadRegistrySnapshot()
saveRegistryHost(_ host: RegistryHostDraft)
saveRegistryRule(_ rule: RegistryRuleDraft)
```

### 3. Contracts

- `load_registry_snapshot` must read the SQLite-backed `ConfigurationSnapshot` and project it into `RegistrySnapshotResult`.
- Empty storage returns an empty `RegistrySnapshotResult`; Swift must show the empty state until the user creates the first host through `新建资源分组`.
- `save_registry_host` may create the first saved configuration snapshot; it must not depend on a seeded demo registry.
- `save_registry_rule` must update or append a rule, then return the full next `registry_snapshot` for immediate UI refresh.
- Provider-target drafts in this slice are intentionally narrow: `provider_kind`, `label`, `target_address`, and optional `target_port`. Do not send `auth_ref`, secrets, or Keychain material through this form contract.
- Production bridge storage path defaults to `~/Library/Application Support/RelayDock/relaydock.sqlite3`.
- `RELAYDOCK_STORE_PATH` may override the SQLite path for QA or tooling.

### 4. Validation & Error Matrix

- Missing host/rule required fields -> `registry_validation_failed`.
- Rule references a host/provider-target mismatch -> `registry_validation_failed`.
- Provider-target draft includes unsupported credential-like fields -> `registry_validation_failed`.
- SQLite open/create/save/load failure -> `storage_failed`.
- Empty storage on `load_registry_snapshot` -> success with empty arrays, not a bridge error.

### 5. Good/Base/Bad Cases

- Good: user creates the first host from an empty registry, saves it, and the returned snapshot selects that host immediately.
- Base: user edits a rule and receives the same host list with the updated rule summary after one bridge round-trip.
- Bad: Swift seeds demo hosts into SQLite or keeps a separate Swift-only registry state machine to fake persistence.

### 6. Tests Required

- Rust unit test that `load_registry_snapshot` returns empty state for empty storage.
- Rust unit test that `save_registry_host` bootstraps the first saved configuration and returns the new selected host.
- Rust unit test that `save_registry_rule` updates stored configuration and projects the new rule summary.
- Rust unit test that invalid host/rule drafts map to `registry_validation_failed`.
- Swift build must compile bridge models, executor, view model, and registry editor sheets together.

### 7. Wrong vs Correct

Wrong:

```json
{"command":"save_registry_host","host":{"name":"Mac Studio - Office","provider_targets":[{"label":"SSH · 办公室","auth_ref":"keychain:ssh-office"}]}}
```

Correct:

```json
{"command":"save_registry_host","host":{"name":"Mac Studio - Office","provider_targets":[{"provider_kind":"ssh","label":"SSH · 办公室","target_address":"10.0.4.5","target_port":22}]}}
```

## Demo Runtime Action Extension

### 1. Scope / Trigger

- Trigger: Run/Recovery UI needs row-level `retry` and temporary local-port recovery without teaching Swift the runtime transition rules.
- Scope: deterministic demo bridge only. Real provider/persistence work must replace these with durable runtime commands later.

### 2. Signatures

Rust commands:

```json
{"command":"retry_demo_runtime","runtime_id":"runtime-rule-rabbitmq","snapshot":{...}}
{"command":"apply_demo_local_port_override","rule_id":"rule-postgres-main","local_port":15432,"snapshot":{...}}
```

Swift entrypoints:

```swift
retryDemoRuntime(runtimeId:snapshot:)
applyDemoLocalPortOverride(ruleId:localPort:snapshot:)
```

### 3. Contracts

- Swift submits the last Rust-produced `RunRecoverySnapshotResult`.
- Rust returns a full next `run_recovery_snapshot`.
- `retry_demo_runtime` may transition only `reconnecting` or `error` runtime rows to `connected`.
- `apply_demo_local_port_override` may transition only `recoverable` rows to `connected`.
- Temporary local-port override updates the returned runtime row only; registry rules must remain unchanged.

### 4. Validation & Error Matrix

- Missing retryable runtime -> `invalid_demo_action` with `affected_runtime_id`.
- Missing recoverable rule -> `invalid_demo_action` with `affected_rule_id`.
- `local_port == 0` -> `invalid_demo_action`.

### 5. Good/Base/Bad Cases

- Good: retrying an `error` row clears row error, returns `connected`, and keeps only `stop` as the action.
- Base: recovering with local port `15432` returns `15432 -> 5432` on the runtime row.
- Bad: Swift mutates `RegistryRule.portSummary` to represent a temporary runtime override.

### 6. Tests Required

- Rust unit test for retrying an error/reconnecting runtime.
- Rust unit test that local-port override recovers the runtime row without mutating `load_registry_snapshot`.
- Swift build must compile bridge models and executor.

### 7. Wrong vs Correct

Wrong:

```swift
row.state = .connected
row.portSummary = "15432 -> 5432"
```

Correct:

```swift
try executor.applyDemoLocalPortOverride(ruleId: ruleId, localPort: 15432, snapshot: snapshot)
```
