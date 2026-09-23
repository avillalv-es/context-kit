// Trap: require()/import() where the target is called, chained, or
// member-accessed instead of the whole result being bound directly. The
// plain form on the last line is kept for contrast.
const Foo = require('./b').Foo;
const dbg = require('./b')('app');
const p = import('./b').then(m => m.x);
const whole = require('./b');

export { Foo, dbg, p, whole };
