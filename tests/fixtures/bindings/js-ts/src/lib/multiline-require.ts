// Trap: a destructured require() split across several lines, with a rename
// ("b: c") on the property right before the closing brace.
const {
  a,
  b: c
} = require('./b')

export { a, c };
