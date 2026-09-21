import { test } from "node:test";
import assert from "node:assert/strict";
import { chargeFor } from "../src/domain/billing.js";

test("chargeFor uses an active tariff", () => {
  const c = chargeFor(
    [{ siteId: "a", bucket: "2026-01-01T00:00:00Z", wh: 10_000 }],
    [{ kind: "fixed", rate: 30, validFrom: "2025-01-01T00:00:00Z" }],
    "2026-01-01T00:00:00Z",
  );
  assert.equal(c.kwh, 10);
  assert.equal(c.pence, 300);
});
