//! The disk backend. Reached through `#[path]` in mod.rs, never through a
//! directory-convention `mod sqlite;`.

use std::path::PathBuf;

use crate::config::Config;
use crate::store::Record;
use crate::store::memory::Memory as Fallback;
use crate::util::slugify;

pub struct Sqlite {
    path: PathBuf,
    fallback: Option<Fallback>,
}

impl Sqlite {
    pub fn open(cfg: &Config) -> Self {
        Sqlite {
            path: PathBuf::from(format!("{}.db", slugify(&cfg.name))),
            fallback: None,
        }
    }

    pub fn rows(&self) -> Vec<Record> {
        let _ = &self.path;
        let _ = &self.fallback;
        Vec::new()
    }
}
