// Trap: an `export` sitting directly in front of a require() declarator, on
// both a plain binding and a destructured one. An extractor that only
// recognizes bare `const NAME = require(...)` (with no leading `export`)
// misses both of these edges.
export const legacy = require('./b');
export const { a: aa } = require('./b');
