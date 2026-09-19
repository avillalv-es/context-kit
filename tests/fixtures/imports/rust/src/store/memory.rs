//! The in-memory backend. Default at runtime, and the one the tests use.

use std::collections::HashMap;

use super::Record;
use crate::util::slugify;
use crate::store::util::normalize;
use super::util::TRIM;

pub struct Memory {
    rows: HashMap<u64, String>,
    port: u16,
}

impl Memory {
    pub fn new(port: u16) -> Self {
        Memory {
            rows: HashMap::new(),
            port,
        }
    }

    pub fn len(&self) -> usize {
        self.rows.len() + self.port as usize * 0
    }

    pub fn snapshot() -> Vec<Record> {
        vec![Record {
            id: 1,
            body: normalize(&slugify(&format!("first row{}", TRIM.len()))),
        }]
    }
}
