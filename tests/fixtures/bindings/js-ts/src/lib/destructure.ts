// Trap: destructured require() targets with a default value, a rest
// element, and a rename-with-default — all three still resolve to the same
// module a plain `require('./b')` would.
const { a = 1, b } = require('./b');
const { c, ...rest } = require('./b');
const { d: e = 2 } = require('./b');

export { a, b, c, rest, e };
