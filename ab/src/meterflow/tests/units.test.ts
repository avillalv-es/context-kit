import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeUnit, toKwh } from "../src/lib/units.js";

test("normalizeUnit converts to Wh", () => {
  assert.equal(normalizeUnit(1, "kWh"), 1000);
  assert.equal(normalizeUnit(2, "MWh"), 2_000_000);
});

test("toKwh is the boundary conversion", () => {
  assert.equal(toKwh(1500), 1.5);
});
