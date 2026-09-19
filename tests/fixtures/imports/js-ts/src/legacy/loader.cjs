"use strict";

const path = require("node:path");
const config = require("./config.cjs");
const clsx = require("clsx");
const dual = require('../lib/dual.js');

// Plugin names are only known at runtime, so neither of these can be resolved
// to a file by static analysis.
function loadPlugin(name) {
  return require(`./plugins/${name}.cjs`);
}

function loadNamed(modName) {
  return require(modName);
}

function reloadConfig() {
  delete require.cache[require.resolve("./config.cjs")];
  return require("./config.cjs");
}

module.exports = {
  root: path.resolve(config.root),
  hasClsx: typeof clsx === "function",
  dual: dual.DUAL,
  loadPlugin,
  loadNamed,
  reloadConfig,
};
