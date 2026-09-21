import { readingsForSite } from "../db/readingsRepo.js";
import { sumWh, type Reading } from "../domain/reading.js";
import { daysBetween } from "../lib/dates.js";
import { log } from "../lib/logger.js";

export async function rollupSite(siteId: string, fromIso: string, toIso: string): Promise<number> {
  const rows = (await readingsForSite(siteId, fromIso, toIso)) as unknown as Reading[];
  const total = sumWh(rows);
  log("info", "rollup.done", { siteId, days: daysBetween(fromIso, toIso), wh: total });
  return total;
}
