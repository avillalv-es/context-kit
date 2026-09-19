//! A store-local module that shares its name with the `telemetry` workspace
//! crate on purpose.
//!
//! `use telemetry::metrics::Counter;` in src/main.rs and src/handler.rs names
//! the CRATE, never this file. Any resolver that maps an import's first
//! segment onto a same-named file or directory links those two files here,
//! and both of those edges are wrong.

use crate::config::Config;
use crate::util::slugify;

// rustfmt collapses two paths that share a prefix into this shape, which
// makes it the most common `use` in real Rust. The extractor truncates at
// the first `{`, is left with a bare `crate`, finds no `crate::` prefix and
// drops the whole line as an external crate - BOTH members are lost. The two
// lines above reach the same two files, so EXPECTED.tsv does not move.
use crate::{config::Config as Cfg, util::slugify as slug};

pub struct Sink {
    label: String,
}

impl Sink {
    pub fn new(cfg: &Config) -> Self {
        Sink { label: slugify(&cfg.name) }
    }

    pub fn alt(cfg: &Cfg) -> Self {
        Sink { label: slug(&cfg.name) }
    }

    pub fn label(&self) -> &str {
        &self.label
    }
}
