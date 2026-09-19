#!/usr/bin/env node
// Build helper. Run with: node scripts/build.mjs
// Node >= 22.18 strips TypeScript types natively, so a .ts specifier is fine.
import { mkdir, writeFile } from "node:fs/promises";
import { VERSION } from "../src/lib/constants.ts";

const banner = `// generated - do not edit
// import { format } from "../src/lib/format.ts"
`;

await mkdir(new URL("../dist/", import.meta.url), { recursive: true });
await writeFile(
  new URL("../dist/banner.js", import.meta.url),
  `${banner}export const VERSION = ${JSON.stringify(VERSION)};\n`,
);
