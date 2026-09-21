import { toKwh } from "../lib/units.js";
import { sumWh, type Reading } from "./reading.js";
import { activeTariffs, type Tariff } from "./tariff.js";
import { DomainError } from "../lib/errors.js";

export interface Charge {
  pence: number;
  kwh: number;
}

export function chargeFor(readings: Reading[], tariffs: Tariff[], onIso: string): Charge {
  const active = activeTariffs(tariffs, onIso);
  if (active.length === 0) throw new DomainError("no_tariff", "no active tariff");

  const chosen = active[0];
  const kwh = toKwh(sumWh(readings));
  return { pence: Math.round(kwh * chosen.rate), kwh };
}
