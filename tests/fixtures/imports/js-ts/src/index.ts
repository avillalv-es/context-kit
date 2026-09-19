// Entry point. Wires the app together.
import React from "react";
import { App } from "./app";
import { VERSION } from "@app/lib/constants";

export * from "./lib";
// import { boot } from "./legacy/loader.cjs"; // retired in v2, kept for reference

export function main(): void {
  console.log("import the app and go", VERSION, typeof React, typeof App);
}
