// Trap: string LITERALS that merely contain the text "require(" or
// "import(" must never be treated as real require()/import() calls. Both
// default values below are plain strings, split across a multi-line
// destructure — no module named "./evil" or "./evil2" is ever required or
// imported by this file.
const obj: Record<string, unknown> = {};
const {
  a = "require('./evil')",
  b = "see import('./evil2')",
} = obj;

export { a, b };
