// Trap: `require("./a")` with no trailing semicolon, followed on the next
// line by a `!`-prefixed IIFE. The leading `!` starts a new statement — it
// is not `require("./a")` being called as a function.
const a2 = require("./a")
!function(){}()

module.exports = { a2 };
