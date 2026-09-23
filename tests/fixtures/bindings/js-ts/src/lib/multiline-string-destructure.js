// Trap: a multi-line destructure whose default value is a STRING split by
// a backslash-newline continuation ('x\<newline>y' -> "xy"), and whose
// source object comes from calling f() with a string argument that itself
// contains the text "require('./evil')" — never a real import.
function f() {
  return {};
}

const {
  a = 'x\
y',
  b } = f("require('./evil')")

module.exports = { a, b };
