//! Configuration loading.

use std::env;

use serde::Deserialize;

use crate::util::slugify; // the pre-split loader reached crate::store::sqlite::Sqlite here

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub name: String,
    pub port: u16,
}

impl Config {
    pub fn load() -> Self {
        let name = env::var("APPSVC_NAME").unwrap_or_else(|_| "appsvc".to_string());
        Config {
            name: slugify(&name),
            port: 8080,
        }
    }
}
