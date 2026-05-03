# Domain And State

Primary domain concepts:

- `Host`
- `ProviderTarget`
- `Rule` / `Service`
- `Preset`
- `RuntimeInstance`
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

`LocalPortOverride` is session-scoped by default and must not silently mutate the saved rule configuration.

State transitions should be explicit enough for logs, diagnostics, and later automation.
