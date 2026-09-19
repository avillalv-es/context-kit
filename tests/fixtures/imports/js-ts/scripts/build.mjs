#!/usr/bin/env node
// Build helper. Run with: node scripts/build.mjs
// Node >= 22.18 strips TypeScript types natively, so a .ts specifier is fine.
import { mkdir, writeFile } from "node:fs/promises";
import pkg from "../package.json" with { type: "json" };
import { VERSION } from "../src/lib/constants.ts";
import { shared } from "../../shared/tooling.mjs";

// Each glob below contains a slash-star sequence inside a string literal, and
// nothing later in this file ever closes it. A block-comment stripper that does
// not know about strings opens a comment on the next line and silently eats
// every specifier below it - two real edges, with no syntax error to notice.
const SOURCES = ["src/*.ts", "scripts/*.mjs"];

const { wrapped } = await import("../src/esm/wrapper.mjs");
const { DUAL } = await import('../src/lib/dual.js');

const banner = `// generated - do not edit
// import { format } from "../src/lib/format.ts"
const legacy = require("../src/legacy/loader.cjs");
`;

await mkdir(new URL("../dist/", import.meta.url), { recursive: true });
await writeFile(
  new URL("../dist/banner.js", import.meta.url),
  `${banner}export const META = ${JSON.stringify({
    VERSION,
    SOURCES,
    name: pkg.name,
    wrapped: typeof wrapped,
    DUAL,
    shared: typeof shared,
  })};\n`,
);
