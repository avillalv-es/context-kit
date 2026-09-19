//! appsvc - the fixture binary, and the crate root for the `appsvc` crate.
//!
//! Before the store was split out this file talked to the backing map itself:
//!
//!     use crate::store::memory::Memory;
//!
//! It goes through `store` now. The line above is documentation, and
//! src/store/memory.rs is a real file, so it is the sharpest false edge here.

mod config;
mod handler;
mod store;
mod util;

use std::process::ExitCode;

use serde::Deserialize;
use telemetry::metrics::Counter;

use crate::config::Config;
use crate::handler::Api;
// use crate::handler::render::html; // re-exported through handler, see ADR-014

/// A crate path inside a string literal is text, not an import.
const USAGE: &str = "set APPSVC_BACKEND=sqlite to use crate::store::sqlite::Sqlite";

// An ORDINARY Rust string literal may span lines, and the continuation line
// below begins at column 0 with the word `use`. Nothing on that line says it
// is text: quote state is tracked only within a line, so the extractor reads
// it as code and emits an edge from it. It names src/config.rs, which main.rs
// already imports for real on line 20, so EXPECTED.tsv does not move. The
// visible reproduction is recorded in false_edge_traps instead.
const MIGRATION_NOTE: &str = "
use crate::config::Config;
";

#[derive(Deserialize)]
struct Args {
    name: String,
}

fn main() -> ExitCode {
    let cfg = Config::load();
    let api = Api::new(&cfg);
    let hits = Counter::new("requests");

    eprintln!("{USAGE}");
    eprintln!("{MIGRATION_NOTE}");
    let args = Args { name: cfg.name.clone() };
    let _ = store::open(&cfg);

    if api.serve(&hits).is_err() {
        eprintln!("{} failed", args.name);
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
