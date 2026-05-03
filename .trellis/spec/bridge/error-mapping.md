# Error Mapping

Rust errors should preserve:

- machine-readable code
- human-readable summary
- diagnostic detail
- affected host/rule/runtime IDs when available
- suggested recovery action when known

Swift maps these errors into:

- inline row status
- sheet/dialog messages
- logs and diagnostics entries
- retry/recover affordances

Do not reduce Rust errors to unstructured strings at the bridge boundary.
