//! Storage facade. Picks a backend and hands out `Record`s.

pub mod memory;
pub mod util;
pub mod telemetry;

// The disk backend lives beside this file but is mounted by path, because
// the integration harness compiles the same file on its own.
#[cfg(feature = "sqlite")]
#[path = "sqlite.rs"]
mod backend;

// mod sqlite;  <- the convention form, deliberately commented out. The file
// it names is real and is reached by no other declaration, so an extractor
// that stops stripping `//` invents this edge and nothing else hides it.

// A #[path] that climbs out of the fixture. The attribute is not read today,
// so `mod legacy;` below simply drops for want of a file. A #[path]-aware
// extractor must push the join through norm() and REJECT the climb: with the
// repo root rather than the fixture root as the base, this lands on a real
// file that has nothing to do with this module.
#[cfg(feature = "legacy")]
#[path = "../../../rust/src/util.rs"]
mod legacy;

use super::config::Config;
use self::memory::Memory;

pub struct Record {
    pub id: u64,
    pub body: String,
}

pub fn open(cfg: &Config) -> Memory {
    Memory::new(cfg.port)
}

pub fn all() -> Vec<Record> {
    Memory::snapshot()
}
