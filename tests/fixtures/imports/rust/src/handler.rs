//! The request handler layer.

mod render;

// `pub(crate) mod` is a real and common Rust form. The extractor's anchor is
// `^[ \t]*(pub[ \t]+)?mod`, which needs whitespace after `pub`; here `pub` is
// followed by `(`, so the line matches nothing and the declaration is lost.
// The `use crate::handler::detail::Row;` below reaches the same file, so the
// miss is invisible in EXPECTED.tsv and recorded in false_edge_traps.
pub(crate) mod detail;

use telemetry::metrics::Counter;

use crate::config::Config;
use crate::handler::detail::Row;
use crate::store::{self, Record};

/*
 * The pre-split version of this file, kept for the migration note.
 * It opened the disk backend itself:
 *
 * use crate::store::sqlite::Sqlite;
 *
 * Nothing in this file touches sqlite any more - the store facade picks
 * the backend now.
 */

pub struct Api {
    name: String,
}

impl Api {
    pub fn new(cfg: &Config) -> Self {
        Api {
            name: cfg.name.clone(),
        }
    }

    pub fn serve(&self, hits: &Counter) -> Result<(), String> {
        hits.incr();
        let rows: Vec<Record> = store::all();
        let _first: Option<Row> = detail::first(&rows);
        println!("{}", render::html(&self.name, rows.len()));
        Ok(())
    }
}
