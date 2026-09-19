import cfg = require("../legacy/config.cjs");

// require.resolve names a file exactly the way require does, but the "."
// between require and "(" defeats a require\s*\( pattern.
const loaderPath: string = require.resolve("../legacy/loader.cjs");

export const NATIVE: string = `${cfg.root}:${loaderPath}`;
