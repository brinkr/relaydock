# Rust Core Quality Guidelines

- Keep APIs coarse-grained across the Swift/Rust boundary.
- Return structured results and structured errors.
- Avoid UI-specific strings in core logic.
- Prefer deterministic unit tests for parsing, state transitions, and port conflict decisions.
- Keep provider process code isolated from pure domain logic.
- Preserve future CLI/agent reuse when designing public core APIs.
