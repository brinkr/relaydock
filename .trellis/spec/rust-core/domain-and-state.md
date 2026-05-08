# Domain And State

Primary domain concepts:

- `Host`
- `ProviderTarget`
- `Rule` / `Service`
- `Preset`
- `RuntimeInstance`
- `ProviderProcessRecord`
- `RecoveryItem`
- `LocalPortBinding`
- `LocalPortOverride`
- `PortUsage` / `PortClaim`
- `LocalAlias`

Runtime state must distinguish:

- configured rules
- currently running instances
- interrupted but recoverable instances
- temporary local port overrides

`Rule.access_mode` is the execution boundary:

- `Forwarded` requires a provider target and is the only mode that may create `RuntimeInstance`, `RecoveryItem`, `LocalPortBinding`, or `LocalPortOverride` records for tunnel lifecycle.
- `Direct` represents an already reachable remote/Tailscale/MagicDNS application. It may omit provider target and must not be projected into run/recovery tunnel rows.
- `Local` represents an already running local service. It may omit provider target and may feed future local port diagnostics, but it must not enter provider start/stop/recovery flows.

Old rule snapshots without `access_mode` deserialize as `Forwarded` for compatibility. Do not use `main_port.local_port` as a local port claim for `Direct`; it should stay `0`, while `main_port.remote_port` is the application port.

`ProviderProcessRecord` is runtime-owned operational metadata that links one `RuntimeInstance` to a provider pid for the JSON sidecar MVP. It must be treated as observable process state, not user configuration.

`LocalPortOverride` is session-scoped by default and must not silently mutate the saved rule configuration.

State transitions should be explicit enough for logs, diagnostics, and later automation.
