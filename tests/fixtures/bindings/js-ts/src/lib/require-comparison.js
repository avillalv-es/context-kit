// Trap: `require('./cfg')` is not being bound directly — it's the left
// operand of a `!==` comparison that continues on the NEXT line. The
// require() call here never becomes the value of "ok" on its own; "ok" is
// a boolean.
const ok = require('./cfg')
  !== undefined;

module.exports = { ok };
