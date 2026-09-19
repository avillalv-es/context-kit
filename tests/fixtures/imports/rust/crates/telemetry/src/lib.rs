//! Counters for appsvc. A second crate root in the same workspace.

pub mod metrics;

pub use crate::metrics::Counter;

/// Where a counter is reported from.
pub struct Scope(pub &'static str);
