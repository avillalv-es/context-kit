import { test } from "node:test";
import assert from "node:assert/strict";
import { toReading, sumWh } from "../src/domain/reading.js";

test("toReading stores Wh", () => {
  const r = toReading({ siteId: "1234567890123", takenAt: "2026-01-01T00:07:00Z", value: 3, unit: "kWh" });
  assert.equal(r.wh, 3000);
  assert.equal(r.bucket, "2026-01-01T00:00:00.000Z");
});

test("sumWh adds", () => {
  assert.equal(sumWh([{ siteId: "a", bucket: "b", wh: 5 }, { siteId: "a", bucket: "c", wh: 7 }]), 12);
});
