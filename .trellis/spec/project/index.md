# RelayDock Project Guidelines

## Overview

RelayDock is a macOS-first local desktop workbench for tunnels, port forwarding, runtime recovery, and local port conflict diagnosis.

The product baseline lives in:

- `documents/01-product-baseline.md`
- `documents/10-technology-stack-decision.md`
- `documents/11-localport-prototype-reference.md`

## Pre-Development Checklist

Before changing code or specs:

- Confirm the change respects `SwiftUI + AppKit shell + Rust core`.
- Read the relevant product document under `documents/`.
- Keep Chinese user-facing copy and product documents in Chinese.
- Do not introduce a WebView, Electron, Tauri, React, Go, or dashboard-style architecture unless a later ADR explicitly changes the decision.
- Do not copy React/Tailwind component structure from LocalPort. Use it only as a visual and interaction-density reference.

## Quality Check

- The change has a clear boundary between product spec, Swift shell, Rust core, and bridge concerns.
- Commit messages use the repository's document-style convention: subject plus body explaining reason, purpose, scope/boundary, and tradeoffs.
- The working tree does not include unrelated generated files or prototype code.

## Guides

- [Product Constraints](./product-constraints.md)
- [Commit Guidelines](./commit-guidelines.md)
- [Trellis Usage](./trellis-usage.md)
