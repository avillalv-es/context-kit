// Trap: a require() call sitting as a DEFAULT VALUE inside a destructuring
// pattern ("b = require('./b')"), split across multiple lines. Only the
// "b" property has a require() default; "a" is a plain destructured
// binding with no default and no import at all.
const obj: Record<string, unknown> = {};
const {
  a,
  b = require('./b'),
} = obj;

export { a, b };
