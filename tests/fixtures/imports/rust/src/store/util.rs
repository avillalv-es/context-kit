//! String helpers for the store layer.
//!
//! Its basename collides with src/util.rs on purpose: two files named util.rs
//! in different directories, both reached from src/store/memory.rs, so any
//! resolver that matches on basename alone links the wrong pair - and this
//! file's own import of the other one would collapse into a self-edge.

use crate::util::*;
/* the facade row type */ use crate::store::Record;

// `pub(crate) use` is a real Rust form the `^[ \t]*(pub[ \t]+)?use` anchor
// does not match: after `pub` comes `(`, not whitespace. The file it names
// is already reached by the line above, so the miss leaves EXPECTED.tsv
// alone and is recorded in false_edge_traps instead.
pub(crate) use crate::store::open;

// `include!` splices another file in textually - a genuine file-level
// dependency with no `use` or `mod` anchor on the line. Nothing else points
// at src/store/rows_generated.rs, so its absence is what gets asserted.
include!("rows_generated.rs");

pub const TRIM: &str = " \t";

pub fn normalize(input: &str) -> String {
    slugify(input.trim_matches(|c| TRIM.contains(c)))
}

pub fn label(r: &Record) -> String {
    format!("{}/{}", r.id, GENERATED_ROWS)
}
