import { toReading } from "../domain/reading.js";
import { validateRaw } from "../domain/validate.js";
import { insertReadings } from "../db/readingsRepo.js";
import { loadConfig } from "../lib/config.js";
import { log } from "../lib/logger.js";

export async function ingestBatch(raw: Record<string, unknown>[]): Promise<number> {
  const cfg = loadConfig();
  const batch = raw.slice(0, cfg.ingestBatchSize).map((r) => toReading(validateRaw(r)));
  const n = await insertReadings(batch);
  log("info", "ingest.batch", { count: n });
  return n;
}
