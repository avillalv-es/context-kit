import { format } from "@local/format";
import { NATIVE } from "./native.cjs";
import util from "node:util";
// @lib is declared in the ROOT tsconfig.json, but the nearest config for this
// file is src/esm/tsconfig.json, which does not declare it and does not extend
// anything. Deliberately unresolvable.
import { LABELS } from "@lib";
// Deliberately wrong casing. Lookup is an exact match against the file index,
// so this must not find src/lib/constants.ts.
import { VERSION } from "../Lib/constants";

export const wrapped = (s: string): string =>
  util.format("%s", format(s).text) + NATIVE + String(LABELS) + String(VERSION);
