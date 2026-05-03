# Swift Shell Guidelines

## Overview

The Swift shell owns the macOS-native application surface.

Use SwiftUI for primary declarative views and AppKit where SwiftUI cannot express required desktop behavior precisely.

## Pre-Development Checklist

- Read `documents/05-ui-information-architecture.md`.
- Read `documents/11-localport-prototype-reference.md` when changing layout or interaction density.
- Confirm the change belongs in UI/platform integration, not Rust core.
- Keep UI Chinese-first.

## Quality Check

- The UI feels like a native macOS tool, not a web admin dashboard.
- ViewModels do not accumulate domain state machines that belong in Rust core.
- Destructive actions are separated and named explicitly.
- Status text, row density, and toolbar actions match the product baseline.

## Guides

- [Directory Structure](./directory-structure.md)
- [UI Patterns](./ui-patterns.md)
- [State And ViewModel Boundaries](./state-and-viewmodel-boundaries.md)
- [Quality Guidelines](./quality-guidelines.md)
