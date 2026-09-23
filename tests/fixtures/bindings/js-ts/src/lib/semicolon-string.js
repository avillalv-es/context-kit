// Trap: a string literal containing "import('./evil')" shares a line with
// a REAL require() of a different target ("./a"), joined by a semicolon.
// The line after that is an unrelated call, not part of either statement.
function foo() {}

const help = "usage: import('./evil')"; const a = require('./a')
foo()

module.exports = { help, a };
