//! Row detail formatting.
//!
//! Declared from handler.rs with `pub(crate) mod detail;`, which no pattern
//! matches. The edge into this file comes from the `use` beside it.

use crate::store::Record; /* the row type. Before the facade existed this file
 * opened the disk backend on its own:
 *
 * use crate::store::sqlite::Sqlite;
 *
 * The block comment OPENS on a line that already carried a real import: that
 * import must still resolve, and every line until the close must not.
 */

pub struct Row {
    pub id: u64,
}

pub fn first(rows: &[Record]) -> Option<Row> {
    rows.first().map(|r| Row { id: r.id })
}
