# Trellis Usage

## Role

Trellis is used for spec-driven task management and agent context routing.

It does not define the application technology stack.

## Accepted Use

- Maintain implementation tasks under `.trellis/tasks/`.
- Load project, Swift shell, Rust core, and bridge specs into implementation/check contexts.
- Use Trellis research and task notes to preserve decisions across Codex sessions.

## Forbidden Drift

Do not use Trellis templates that imply a different stack, including:

- `electron-fullstack`
- `nextjs-fullstack`
- `cf-workers-fullstack`
- any React/WebView default app template

If a Trellis-generated default says `frontend` or `backend`, reinterpret it through RelayDock's explicit layers or replace it.
