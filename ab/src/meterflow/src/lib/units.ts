export type Unit = "Wh" | "kWh" | "MWh";

const TO_WH: Record<Unit, number> = { Wh: 1, kWh: 1_000, MWh: 1_000_000 };

/** Canonical storage unit is Wh. Everything entering the system passes here. */
export function normalizeUnit(value: number, unit: Unit): number {
  const factor = TO_WH[unit];
  if (factor === undefined) throw new Error(`unknown unit: ${unit}`);
  return value * factor;
}

/** Boundary conversion for presentation. Never call this inside the domain. */
export function toKwh(wh: number): number {
  return wh / 1_000;
}

export function isUnit(v: string): v is Unit {
  return v === "Wh" || v === "kWh" || v === "MWh";
}
