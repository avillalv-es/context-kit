import { isUnit } from "../lib/units.js";
import { Invalid } from "../lib/errors.js";
import type { RawReading } from "./reading.js";

const MPAN = /^\d{13}$/;

export function validateSiteId(siteId: unknown): string {
  if (typeof siteId !== "string" || !MPAN.test(siteId)) {
    throw new Invalid("siteId must be a 13 digit MPAN");
  }
  return siteId;
}

export function validateRaw(body: Record<string, unknown>): RawReading {
  const unit = body.unit;
  if (typeof unit !== "string" || !isUnit(unit)) throw new Invalid("unknown unit");
  return {
    siteId: validateSiteId(body.siteId),
    takenAt: String(body.takenAt),
    value: Number(body.value),
    unit,
  };
}
