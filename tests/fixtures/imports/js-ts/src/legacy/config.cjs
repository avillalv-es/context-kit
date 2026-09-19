"use strict";

// This file used to do: const helpers = require("../lib/format");
// It is pure data now.
const DOC = `
  Legacy loader usage:
    const config = require("../lib/constants.ts");
    import { VERSION } from "../lib/index";
`;

module.exports = {
  root: ".",
  doc: DOC,
  note: "import and require strings live in data too",
  retired: ["./config.cjs", "react"],
};
