# Provider And Process

First provider scope:

- system OpenSSH for SSH forwarding
- local Tailscale status/CLI integration when available

First stage should not implement a custom SSH protocol stack.

Rust core owns:

- command construction
- process lifecycle tracking
- status observation
- reconnect/recovery decisions
- error attribution

Swift shell owns:

- permission prompts
- user-visible confirmation flows
- system integration surfaces

Provider abstractions must describe what users care about: which target/channel a rule runs through, not provider internals.
