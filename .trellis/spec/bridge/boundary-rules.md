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
- `load_run_recovery_snapshot` must read SQLite-backed resource registry configuration for the first production slice. Until durable runtime/recovery persistence exists, saved rules project as `recoverable` candidates; empty storage returns an empty snapshot rather than seeded demo rows.
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
{"command":"parse_ssh_command","command_text":"ssh -L 3000:127.0.0.1:3000 admin@sanjose"}
{"command":"save_registry_host","host":{"id":"host-mac-studio","name":"Mac Studio - Office","address":"10.0.4.5","port":22,"user":"admin","tags":["office"],"os_hint":"macos","status":"unknown","provider_targets":[{"id":"target-ssh-office","kind":"ssh","label":"SSH · 办公室","target_address":"10.0.4.5","target_port":22}]}}
{"command":"save_registry_rule","rule":{"id":"rule-relay-admin","host_id":"host-mac-studio","provider_target_id":"target-ssh-office","service_name":"Relay Admin","alias":"admin.office.localhost","kind":"web","tags":["admin","office"],"remote_host":"127.0.0.1","main_local_port":3000,"main_remote_host":"127.0.0.1","main_remote_port":3000,"secondary_ports":[],"notes":null}}
```

Swift entrypoints:

```swift
loadRegistrySnapshot()
parseSshCommand(_ commandText: String)
saveRegistryHost(_ host: RegistryHostDraft)
saveRegistryRule(_ rule: RegistryRuleDraft)
```

### 3. Contracts

- `load_registry_snapshot` must read the SQLite-backed `ConfigurationSnapshot` and project it into `RegistrySnapshotResult`.
- `parse_ssh_command` must parse pasted OpenSSH local-forward input in Rust and return structured hints, rule drafts, and diagnostics. Swift must not parse SSH command syntax itself.
- `parse_ssh_command` may accept raw command text as transient command input only; the raw pasted string must not be saved as runtime/provider source of truth.
- `parse_ssh_command` should support common `-L` forms plus OpenSSH `LocalForward` provided through `-o`.
- Empty storage returns an empty `RegistrySnapshotResult`; Swift must show the empty state until the user creates the first host through `新建资源分组`.
- `save_registry_host` may create the first saved configuration snapshot; it must not depend on a seeded demo registry.
- `save_registry_rule` must update or append a rule, then return the full next `registry_snapshot` for immediate UI refresh.
- Provider-target drafts in this slice are intentionally narrow: `kind`, `label`, `target_address`, and optional `target_port`. Do not send `auth_ref`, secrets, or Keychain material through this form contract.
- Production bridge storage path defaults to `~/Library/Application Support/RelayDock/relaydock.sqlite3`.
- `RELAYDOCK_STORE_PATH` may override the SQLite path for QA or tooling.

### 4. Validation & Error Matrix

- Missing host/rule required fields -> `registry_validation_failed`.
- Empty or malformed SSH command -> success result with `ssh_command_parse` diagnostics, not a storage mutation.
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
- Rust unit test that `parse_ssh_command` returns one rule draft per supported `-L` / `LocalForward` and reports malformed forwards as diagnostics.
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
{"command":"save_registry_host","host":{"name":"Mac Studio - Office","provider_targets":[{"kind":"ssh","label":"SSH · 办公室","target_address":"10.0.4.5","target_port":22}]}}
```

## Registry Provider Target Connectivity Test

### 1. Scope / Trigger

- Trigger: `新建资源分组` and `主机设置` need a save-before-test action so users can check whether the configured provider target is reachable before committing it.
- Scope: first slice tests TCP reachability to `target_address:target_port` only.
- Boundary: Swift owns the form draft, target selection, and inline result display. Rust core owns DNS resolution, TCP connect timeout, latency measurement, and structured diagnostics.

### 2. Signatures

Rust command:

```json
{"command":"test_provider_target_connectivity","target_address":"10.0.4.5","target_port":22,"timeout_millis":3000}
```

Swift entrypoint:

```swift
testProviderTargetConnectivity(targetAddress:targetPort:)
```

### 3. Contracts

- The command is transient and must not mutate registry storage, runtime snapshots, or recovery collections.
- `target_address` is required after trimming.
- `target_port` must be a non-zero TCP port.
- `timeout_millis` defaults to `3000` and may be clamped by Rust to a safe range.
- A successful result means the TCP endpoint accepted a connection. It must not be described as SSH authentication success or remote application health.
- Swift must not implement its own socket check for this feature.
- Registry host editor forms must not expose manual `online/offline` selection. The saved host status may be derived from the most recent connectivity result only when it still matches the current target address and port; if the target changed after the last test, save `unknown` rather than preserving stale status.

### 4. Validation & Error Matrix

- Empty target address or zero port -> success envelope with `reachable: false` and diagnostic `invalid_target`.
- DNS resolution failure -> success envelope with `reachable: false` and diagnostic `dns_resolution_failed`.
- TCP connection failure or timeout -> success envelope with `reachable: false` and diagnostic `connect_failed`.
- Malformed command JSON -> bridge-level `invalid_command`.

### 5. Good/Base/Bad Cases

- Good: user enters `111.230.202.80:22`, clicks `测试连接`, and sees a reachable result plus latency when TCP connect succeeds.
- Base: target is offline and returns a structured failure diagnostic without blocking save forever.
- Bad: Swift lets users manually choose `在线 / 离线` in the registry form.
- Bad: Swift preserves an old reachable status after the address or port has changed without a fresh test.

### 6. Tests Required

- Rust unit test for invalid target returning structured diagnostic.
- Rust unit test for DNS resolution failure returning structured diagnostic.
- Rust bridge command round-trip asserting result type `provider_target_connectivity`.
- Swift build must compile bridge models, executor, view model, and registry editor sheet together.

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

## Real Runtime Retry Command

### 1. Scope / Trigger

- Trigger: run/recovery `重试` must be a Rust-owned runtime lifecycle action, not a Swift-submitted snapshot mutation.
- Scope: persisted `RuntimeInstance` rows that are already in `reconnecting` or `error`.
- Owner: Swift sends only a stable runtime ID; Rust loads configuration/runtime storage, launches the provider, persists runtime/process metadata, and returns a full `run_recovery_snapshot`.

### 2. Signatures

Rust command:

```json
{"command":"retry_runtime_instance","runtime_id":"runtime-rule-react"}
```

Swift entrypoint:

```swift
retryRuntimeInstance(runtimeId: String)
```

### 3. Contracts

- Request fields:
  - `runtime_id`: required non-empty persisted runtime instance ID.
- Request must not include a `snapshot`; app code must not send `RunRecoverySnapshotResult` back to Rust for real retry.
- Rust must reuse the runtime instance's current `local_bindings`, including any session-local override already persisted in runtime state.
- On successful provider observation with a pid, Rust persists:
  - connected `RuntimeInstance` with cleared `last_error`
  - fresh `ProviderProcessRecord` for the runtime
  - existing session-local override records unchanged
- Response is a full `run_recovery_snapshot` with `last_action` describing the retry.

### 4. Validation & Error Matrix

- Missing or empty `runtime_id` -> `runtime_lifecycle_failed`.
- Runtime ID not found in persisted runtime state -> `runtime_lifecycle_failed` with `affected_runtime_id`.
- Runtime status other than `reconnecting` or `error` -> `runtime_lifecycle_failed`; do not launch provider.
- Rule/host/provider target cannot be resolved from current configuration -> structured validation/provider error; do not fake a connected row.
- Provider diagnostic during launch/observation -> return a snapshot with `last_action.ok = false`, preserve diagnostic detail, keep row non-connected, and clear stale pid metadata.
- Provider reports running without pid -> `runtime_lifecycle_failed`; do not mark connected and do not keep stale pid metadata.

### 5. Good/Base/Bad Cases

- Good: retrying an `error` runtime with a manual local-port override relaunches OpenSSH using the overridden local port, persists the new pid, and returns a connected row.
- Base: retrying a `reconnecting` runtime without an old pid record may succeed if the new provider launch exposes pid metadata.
- Bad: Swift submits a stored `RunRecoverySnapshotResult` to decide retry transitions.
- Bad: retry launch fails but a stale `ProviderProcessRecord` remains and later makes reconciliation treat the row as connected.

### 6. Tests Required

- JSON decode test proving `retry_runtime_instance` accepts `runtime_id` only and rejects `snapshot`.
- Success test asserting launch command uses current runtime bindings, row returns `connected`, old error clears, and pid metadata updates.
- Invalid input tests for empty runtime ID, missing runtime, and non-retryable status.
- No-pid test asserting `runtime_lifecycle_failed` and no connected row.
- Provider diagnostic test asserting structured failure status, row stays non-connected, and stale pid metadata is removed.

### 7. Wrong vs Correct

Wrong:

```json
{"command":"retry_runtime_instance","runtime_id":"runtime-rule-react","snapshot":{...}}
```

Correct:

```json
{"command":"retry_runtime_instance","runtime_id":"runtime-rule-react"}
```

## Run/Recovery Registry Projection Extension

### 1. Scope / Trigger

- Trigger: `资源登记` can persist hosts and rules, so `运行与恢复` must stop depending on hardcoded demo rows for production bridge loads.
- Scope: configuration projection only. Rust reads SQLite-backed `ConfigurationSnapshot` and returns runtime-facing host groups and rows.
- Boundary: this slice does not launch provider processes or persist runtime/recovery collections.

### 2. Signatures

Rust command:

```json
{"command":"load_run_recovery_snapshot"}
```

Swift entrypoint:

```swift
loadRunRecoverySnapshot()
```

### 3. Contracts

- Production `load_run_recovery_snapshot` must read the same local SQLite store as `load_registry_snapshot`.
- Empty storage returns `hosts: []`, summary counts of `0`, and the empty-state message; it must not seed demo hosts.
- Saved rules project as `recoverable` rows until durable runtime and recovery persistence is introduced.
- Projected rows use stable identifiers derived from the saved `rule_id`:
  - `id = recovery-{rule_id}`
  - `runtime_id = null`
  - `recovery_id = recovery-{rule_id}`
- Provider label, alias, host endpoint, and port summary must be derived from saved domain configuration.
- Runtime rows may include `entry_url` derived by Rust from `LocalAlias` plus the effective local port. Do not show a bare `.localhost` hostname as the only launchable entry when the service listens on a non-default port; `ssh-18317.localhost` without `:18317` goes to port 80 and is expected to fail without a reverse proxy.
- `health_summary` belongs on the host/provider summary level. Do not duplicate the same SSH-target latency/health result on every row unless a row has a distinct binding-level failure.
- `events` in `run_recovery_snapshot` are the source of truth for runtime/provider diagnostics; Swift may filter and render them, not invent them.
- Swift must render the structured snapshot and keep only UI-local state such as expansion and sheet drafts.

### 4. Validation & Error Matrix

- SQLite open/load failure -> `storage_failed`.
- Invalid saved configuration -> `registry_validation_failed`.
- Missing provider label on a valid rule -> fallback label `未命名链路`.
- Missing event history -> `events: []`.
- No alias or no local port -> `entry_url: null`.
- Host with no rules -> omitted from the run/recovery snapshot.

### 5. Good/Base/Bad Cases

- Good: user imports an SSH command in `资源登记`, saves two rules, reloads `运行与恢复`, and sees two recoverable rows under that host with full local entry URLs such as `http://ssh-18317.localhost:18317/`.
- Base: empty first launch shows `没有运行或待恢复项目`.
- Bad: production bridge load returns hardcoded `Mac mini (M2) - 家` demo rows when storage is empty.
- Bad: Swift formats `http://{alias}/` for a non-default port row and implies that `.localhost` should carry port routing.

### 6. Tests Required

- Rust unit test for empty storage returning an empty run/recovery snapshot.
- Rust unit test for saved registry rules projecting as recoverable rows with alias, provider label, port summary, and recoverable actions.
- Rust unit test for projected `entry_url` including the effective local port.
- Rust bridge command round-trip must still assert typed `run_recovery_snapshot` output.
- Swift build must compile bridge models and run/recovery view model when optional `events`, `health_summary`, and `entry_url` fields are present.

### 7. Wrong vs Correct

Wrong:

```rust
pub fn load_run_recovery_snapshot() -> RunRecoverySnapshotResult {
    demo_run_recovery_snapshot()
}
```

Correct:

```rust
let store = open_registry_store()?;
let configuration = store.load_configuration()?.unwrap_or_default();
Ok(run_recovery_snapshot_from_configuration(&configuration))
```

## Start Rule OpenSSH Bridge Extension

### 1. Scope / Trigger

- Trigger: `运行与恢复` now displays saved registry rules as recoverable candidates, so the `恢复` action needs its first real provider-backed command.
- Scope: `start_rule` starts one saved SSH rule through Rust core and returns a full `run_recovery_snapshot`.
- Boundary: the current JSON sidecar is one command per process. This command may start OpenSSH and persist the observed runtime instance, but it does not provide a durable process supervisor or reusable child handle for later stop/observe commands.

### 2. Signatures

Rust command:

```json
{"command":"start_rule","rule_id":"rule-react"}
```

Swift entrypoints:

```swift
startRule(ruleId:)
RelayDockBridgeExecutor.startRule(ruleId:)
```

### 3. Contracts

- Rust reads SQLite-backed `ConfigurationSnapshot` and finds `Host`, `Rule`, and `ProviderTarget` by `rule_id`.
- Rust must launch from structured rule fields and provider target fields; imported raw SSH command text must not be used as source of truth.
- Only SSH provider targets are supported in this slice.
- On launch success, Rust immediately observes provider status once, upserts the resulting `RuntimeInstance` into `RuntimeSnapshot`, and returns a full `run_recovery_snapshot`.
- `load_run_recovery_snapshot` must merge persisted runtime instances with saved configuration projection. Runtime rows take precedence over recoverable config rows for the same rule.
- Swift must call `start_rule` for the `恢复` action and render the returned snapshot; Swift must not construct SSH commands or mutate runtime rows locally.

### 4. Validation & Error Matrix

- Missing `rule_id` / unknown rule -> `registry_validation_failed`.
- Rule references missing host/provider target -> `registry_validation_failed`.
- Non-SSH provider target -> `unsupported_provider_target`.
- Provider target mismatch -> `invalid_provider_target`.
- OpenSSH spawn/status failure or immediate provider exit -> `provider_process_failed`.
- SQLite runtime save/load failure -> `storage_failed`.

### 5. Good/Base/Bad Cases

- Good: saved SSH rule starts through system OpenSSH, runtime snapshot stores `runtime-{rule_id}`, and run/recovery reload shows a connected row.
- Base: non-SSH target returns a structured bridge error and does not fake a connected row.
- Bad: Swift handles `恢复` by changing `row.state = .connected` without a bridge round trip.

### 6. Tests Required

- Rust unit test using a mock provider launcher verifies command construction, immediate observation, persisted runtime snapshot, and connected row projection.
- Rust unit test for missing rule -> `registry_validation_failed`.
- Rust unit test for non-SSH target -> `unsupported_provider_target`.
- Rust unit test that a subsequent `load_run_recovery_snapshot` projects saved runtime instances.
- Swift build must compile new bridge command/model/executor/view model path.

### 7. Wrong vs Correct

Wrong:

```swift
viewModel.runRecoverySnapshot?.hosts[0].rows[0].state = .connected
```

Correct:

```swift
applySnapshot(try bridgeExecutor.startRule(ruleId: ruleId))
```

## PID-Backed Runtime Lifecycle Extension

### 1. Scope / Trigger

- Trigger: `start_rule` can launch a real OpenSSH process, so `运行与恢复` needs the first non-demo stop and reload observation path.
- Scope: `start_rule` records provider pid metadata, `load_run_recovery_snapshot` reconciles persisted runtime state once per bridge call, and `stop_runtime_instance` stops one runtime by persisted pid.
- Boundary: this is still a JSON sidecar MVP. It is not a daemon, launch agent, process tree supervisor, reconnect scheduler, or log streamer.

### 2. Signatures

Rust commands:

```json
{"command":"load_run_recovery_snapshot"}
{"command":"start_rule","rule_id":"rule-react"}
{"command":"stop_runtime_instance","runtime_id":"runtime-rule-react"}
```

Swift entrypoints:

```swift
loadRunRecoverySnapshot()
startRule(ruleId:)
stopRuntimeInstance(runtimeId:)
RelayDockBridgeExecutor.stopRuntimeInstance(runtimeId:)
```

### 3. Contracts

- `RuntimeSnapshot` must persist provider process metadata for a started runtime when the provider exposes a pid.
- Persisted process metadata is operational state only: runtime id, provider kind, pid, command summary, target label, and observation timestamps. It must not contain secrets or imported raw SSH command source of truth.
- `load_run_recovery_snapshot` must reconcile runtime instances against provider process metadata before returning rows:
  - pid still observed as running -> keep the runtime row connected and refresh telemetry where available;
  - pid no longer observed -> remove the runtime instance/process record, upsert a `RecoveryItem`, and return a recoverable row.
  - runtime instance without provider process metadata -> treat as stale sidecar-era state, remove it, upsert recovery, and return a recoverable row.
- `stop_runtime_instance` must terminate the persisted provider pid, remove the runtime instance and process metadata, upsert the recovery collection, and return a full `run_recovery_snapshot`.
- Swift must route row and host/page stop actions through `stop_runtime_instance`; Swift must not submit the demo snapshot stop action for real runtime rows.
- Recovery rows remain recoverable by `start_rule`; stopping does not delete the saved registry rule.

### 4. Validation & Error Matrix

- Missing or unknown `runtime_id` -> `runtime_lifecycle_failed`.
- Runtime exists but has no persisted pid metadata -> `runtime_lifecycle_failed`.
- Pid observation or termination failure -> `provider_process_failed`.
- Runtime/recovery persistence failure -> `storage_failed`.

### 5. Good/Base/Bad Cases

- Good: start a saved SSH rule, reload after the sidecar exits, observe the pid still running, then stop it and see the row return to `recoverable`.
- Base: if the pid vanished between app launches, reload moves the row to recovery instead of showing a stale connected runtime.
- Bad: keeping a Rust `Child` handle in the one-command sidecar and assuming a later bridge invocation can reuse it.

### 6. Tests Required

- Rust unit test that `start_rule` persists provider process metadata when the mock provider exposes a pid.
- Rust unit test that `load_run_recovery_snapshot` reconciles a missing pid into a recoverable row.
- Rust unit test that `stop_runtime_instance` uses a mock pid controller, removes runtime/process metadata, and upserts recovery.
- Swift build must compile bridge models, executor, shell view model, and run/recovery stop wiring.
