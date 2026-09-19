//! HTML rendering for the handler.

use super::Api;
use super::super::config::Config as RootCfg;
use crate::util as text;

use crate::store::{
    memory::Memory,
    Record,
};
use crate::util::slugify;

/// A raw string keeps quotes and backslashes verbatim and may span lines.
/// Quote state is tracked only within a line, so the `use` below sits at
/// column 0 and is read as code. It names src/util.rs, which this file
/// already imports for real above, so EXPECTED.tsv does not move.
const TEMPLATE_DOC: &str = r#"
use crate::util::slugify;
"#;

pub fn html(name: &str, count: usize) -> String {
    format!("<h1>{}</h1><p>{} rows</p>", slugify(name), count)
}

pub fn row(r: &Record) -> String {
    format!("<li>{}</li>{}", r.body, TEMPLATE_DOC.len())
}

pub fn debug(_api: &Api, _mem: &Memory) -> &'static str {
    use crate::config::Config;

    let _ = Config::load().port;
    let _ = text::slugify("x");
    let _: Option<RootCfg> = None;
    "ok"
}
