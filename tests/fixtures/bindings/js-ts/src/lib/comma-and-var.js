// Trap: require() appearing as the second operand of a comma-operator
// expression statement (no declaration keyword in sight at all), and
// require() as one of several `var` declarators split across lines.
let cfg1, cfg2, cfg3, items = []
const opts = {}

console.log("let's go"), cfg1 = require('./cfg')
items.forEach(function (x) { var y = x }), cfg2 = require('./cfg')
opts.var, cfg3 = require('./cfg')
var fs1 = require('./a'),
    cfg4 = require('./cfg');

module.exports = { cfg1, cfg2, cfg3, fs1, cfg4 };
