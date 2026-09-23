// Trap: a re-export barrel whose require() call sits on the line after the
// statement starts, not on the same line as `module.exports =`.
module.exports =
  require('./lib/b');
