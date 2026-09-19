//! Counter primitives.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::Scope;

pub struct Counter {
    name: &'static str,
    hits: AtomicU64,
}

impl Counter {
    pub fn new(name: &'static str) -> Self {
        Counter {
            name,
            hits: AtomicU64::new(0),
        }
    }

    pub fn incr(&self) {
        self.hits.fetch_add(1, Ordering::Relaxed);
    }

    pub fn scope(&self) -> Scope {
        Scope(self.name)
    }
}
