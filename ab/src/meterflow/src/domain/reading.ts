import { normalizeUnit, type Unit } from "../lib/units.js";
import { halfHourBucket } from "../lib/dates.js";
import { Invalid } from "../lib/errors.js";

export interface RawReading {
  siteId: string;
  takenAt: string;
  value: number;
  unit: Unit;
}

/** Stored energy is always Wh. */
export interface Reading {
  siteId: string;
  bucket: string;
  wh: number;
}

export function toReading(raw: RawReading): Reading {
  if (!Number.isFinite(raw.value)) throw new Invalid("value must be finite");
  if (raw.value < 0) throw new Invalid("value must not be negative");
  return {
    siteId: raw.siteId,
    bucket: halfHourBucket(raw.takenAt),
    wh: normalizeUnit(raw.value, raw.unit),
  };
}

export function sumWh(readings: Reading[]): number {
  return readings.reduce((acc, r) => acc + r.wh, 0);
}
