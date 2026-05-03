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
