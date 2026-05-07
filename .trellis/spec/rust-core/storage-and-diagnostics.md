# Storage And Diagnostics

Use SQLite as the default local data store unless a later ADR changes it.

Rust core should own:

- configuration schema
- migrations
- import/export validation
- runtime persistence
- recovery collection persistence

Sensitive credentials should use macOS Keychain through the Swift/platform layer, not plain SQLite.

Diagnostics should be structured enough for:

- UI display
- log filtering
- future CLI/agent queries
- conflict diagnosis

## Storage Foundation

RelayDock's first storage layer lives in `relaydock-core` and uses SQLite.

### 1. Scope / Trigger

- Trigger: provider and recovery work need a durable local state boundary before process orchestration starts.
- Owner: Rust core owns SQLite schema, migrations, validation, runtime snapshots, and recovery collection persistence.
- Platform boundary: Swift/AppKit may choose the database file location and handle Keychain access, but Rust owns what ordinary SQLite may store.

### 2. Signatures

Rust entrypoints:

```rust
RelayDockStore::open(path)
RelayDockStore::in_memory()
store.save_configuration(&ConfigurationSnapshot { ... })
store.save_runtime_snapshot(&RuntimeSnapshot { ... })
store.save_recovery_collection(&RecoveryCollection { ... })
```

### 3. Contracts

- Schema version is tracked by `PRAGMA user_version` and `schema_migrations`.
- `ConfigurationSnapshot` stores saved `Host`, `Rule`, and `Preset` configuration.
- `RuntimeSnapshot` stores running instances, provider process metadata for those instances, and session-scoped `LocalPortOverride` records.
- `RecoveryCollection` stores interrupted-but-recoverable runtime items.
- Sensitive credentials must not be stored in SQLite metadata. Store references such as Keychain refs instead.
- Session-scoped local port overrides must not mutate saved `Rule.main_port` or `Rule.secondary_ports`.
- Provider process metadata must reference an existing runtime instance and must remain limited to operational fields such as provider kind, pid, command summary, target label, and observation timestamps.

### 4. Validation & Error Matrix

- Duplicate host/rule/preset/runtime IDs -> validation error.
- Rule references a missing host or provider target -> validation error.
- Rule references a provider target from another host -> validation error.
- Provider target metadata includes credential-like keys (`password`, `private_key`, `secret`, `token`, `credential`) -> validation error.
- Runtime override references a missing runtime instance -> validation error.
- Provider process metadata references a missing runtime instance -> validation error.
- Duplicate provider process metadata for one runtime instance -> validation error.
- Duplicate recovery item for `(rule_id, provider_target_id)` -> validation error.

### 5. Good/Base/Bad Cases

- Good: runtime override changes `RuntimeInstance.local_bindings` and persists as `LocalPortOverride { persisted: false }`.
- Good: runtime process metadata survives the one-command bridge sidecar so a later load/stop command can observe or terminate by pid.
- Base: configuration snapshot round-trips without runtime state.
- Bad: saving a provider target metadata field such as `password = "plain-text"`.
- Bad: treating a missing pid as connected just because a runtime instance remained in JSON storage.
- Bad: treating a runtime instance without provider process metadata as controllable by a later sidecar invocation.

### 6. Tests Required

- Migration creates schema version and migration row.
- Configuration snapshot round-trips.
- Runtime snapshot round-trips with local port override while saved rule ports stay unchanged.
- Recovery collection round-trips and supports clearing one item.
- Validation rejects credential metadata, cross-host provider targets, missing runtime override owners, missing provider process owners, duplicate provider process records, and duplicate recovery items.

### 7. Wrong vs Correct

Wrong:

```rust
rule.main_port.local_port = 3001; // from a one-time conflict workaround
store.save_configuration(&snapshot)?;
```

Correct:

```rust
let override_record = runtime.apply_local_port_override(3000, 3001, OverrideReason::AutoIncrement)?;
store.save_runtime_snapshot(&RuntimeSnapshot {
    instances: vec![runtime],
    provider_processes: vec![process_record],
    local_port_overrides: vec![override_record],
})?;
```

## Runtime Events And Health Diagnostics

### 1. Scope / Trigger

- Trigger: runtime snapshots need explainable operational history, not just current rows.
- Owner: Rust core owns event creation, persistence, retention, and projection into bridge snapshots.

### 2. Signatures

Rust data:

```rust
RuntimeSnapshot {
    instances: Vec<RuntimeInstance>,
    provider_processes: Vec<ProviderProcessRecord>,
    local_port_overrides: Vec<LocalPortOverride>,
    events: Vec<RuntimeEvent>,
}
```

Bridge projection:

```json
{
  "type": "run_recovery_snapshot",
  "events": [
    {
      "level": "warning",
      "kind": "runtime_health_warning",
      "component": "runtime.health",
      "summary": "...",
      "detail": "local_port=18317 healthy=false ..."
    }
  ]
}
```

### 3. Contracts

- `start_rule` records `ssh_start_requested` and either `ssh_start_succeeded` or `ssh_start_failed`.
- Runtime reconciliation records `runtime_health_warning` when pid metadata is alive but local listener health fails.
- Events must carry stable context when known: `host_id`, `rule_id`, `runtime_instance_id`, and `provider_target_id`.
- Persisted event history is capped; newest events are projected first.
- Swift must display these events as diagnostics and must not synthesize provider/process events that Rust did not return.

### 4. Validation & Error Matrix

- Missing `events` in old runtime snapshots -> deserialize as empty with `serde(default)`.
- Event detail may include command summaries and local bindings, but must not include secrets or raw credentials.
- Runtime health warning is not a storage error; it is a normal diagnostic event plus `Reconnecting` runtime state.

### 5. Good/Base/Bad Cases

- Good: starting an SSH rule leaves a queryable event containing the OpenSSH command summary, pid when available, and local binding summary.
- Base: old SQLite snapshots without `events` still load.
- Bad: Swift invents a fake network-switch provider event because a row is reconnecting.

### 6. Tests Required

- Rust unit test that starting a rule persists structured runtime events.
- Rust unit test that pid-alive/local-listener-unhealthy reconciliation persists `runtime_health_warning`.
- Swift build must compile bridge models that include `events`.

### 7. Wrong vs Correct

Wrong:

```swift
DiagnosticEntry(summary: "OpenSSH 已断开", detail: nil) // invented in Swift
```

Correct:

```swift
runRecoverySnapshot.events.map(DiagnosticEntry.init)
```
