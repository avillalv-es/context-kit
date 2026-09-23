// Trap: two declarators sharing one `const`, no semicolons anywhere (ASI).
// "load" wraps a dynamic import() in an arrow function; "cfg" is a plain
// require(). The next line's string just happens to contain the word
// "page" — it is not a further import of "./page".
const load = () => import("./page"), cfg = require("./cfg")
const title = "Settings and preferences page"

module.exports = { load, cfg, title }
