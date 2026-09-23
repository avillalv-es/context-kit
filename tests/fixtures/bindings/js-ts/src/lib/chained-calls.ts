// Trap: chained/optional/bracket/non-null forms of require()/import(), plus
// a chain split across two lines. An extractor that only matches
// `require(...)`/`import(...)` when immediately followed by `.member` on
// the SAME line, or that stops scanning at the first closing `)`, misses
// several of the edges below.
const b1 = require('./b')
  .x;
const c1 = require('./b')?.x;
const d1 = require('./b')['x'];
const e1 = require('./b')!.x;

async function loadF1(): Promise<unknown> {
  const f1 = await import('./b')
    .then(m => m.x);
  return f1;
}

export { b1, c1, d1, e1, loadF1 };
