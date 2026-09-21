export type TariffKind = "fixed" | "timeOfUse" | "capacity";

export interface Tariff {
  kind: TariffKind;
  /** Pence per kWh, except capacity which is pence per kVA per day. */
  rate: number;
  validFrom: string;
  validTo?: string;
}

export function activeTariffs(all: Tariff[], onIso: string): Tariff[] {
  const t = Date.parse(onIso);
  return all.filter(
    (x) => Date.parse(x.validFrom) <= t && (!x.validTo || Date.parse(x.validTo) > t),
  );
}
