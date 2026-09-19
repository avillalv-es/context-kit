// This file has no imports at all. Every quoted path below is plain data in a
// migration table, and several of them name real files relative to src/config/.
export const MIGRATIONS = [
  { from: "../lib/format", to: "../lib/index" },
  { from: "./settings", to: "../util" },
  { from:"../lib/constants", to:"../polyfill" },
];

export const settings = { retries: 2 };
