//! Core domain and runtime model for RelayDock.
//!
//! This crate intentionally contains no SwiftUI/AppKit, FFI, SQLite, or
//! provider process code. It is the reusable domain boundary for the macOS app,
//! future bridge layer, and possible CLI/agent integrations.

pub mod commands;
pub mod domain;
pub mod ports;
pub mod providers;
pub mod runtime;
pub mod storage;

pub use commands::*;
pub use domain::*;
pub use ports::*;
pub use providers::*;
pub use runtime::*;
pub use storage::*;
