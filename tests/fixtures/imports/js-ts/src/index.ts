/// <reference path="./types/globals.d.ts" />
/// <reference types="node" />
// Entry point. Wires the app together.
import React from "react";
import { App } from "./app";
import { VERSION } from "@app/lib/constants";
import { UTIL_NAME } from "./util";
import { helper } from "./util/index";
import "./polyfill";

export * from "./lib";
export * as detail from "./features/detail/view";
export type { Model } from "./types/models";
// import { boot } from "./legacy/loader.cjs"; // retired in v2, kept for reference

export function main(): void {
  console.log("import the app and go", VERSION, typeof React, typeof App, UTIL_NAME, helper);
}
