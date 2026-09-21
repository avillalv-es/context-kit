import { getDb } from "./client.js";
import type { Reading } from "../domain/reading.js";

export async function insertReadings(rows: Reading[]): Promise<number> {
  const db = getDb();
  await db.query(
    "INSERT INTO readings (site_id, bucket, wh) VALUES ($1, $2, $3)",
    rows.flatMap((r) => [r.siteId, r.bucket, r.wh]),
  );
  return rows.length;
}

export async function readingsForSite(siteId: string, fromIso: string, toIso: string) {
  const db = getDb();
  return db.query(
    "SELECT site_id, bucket, wh FROM readings WHERE site_id = $1 AND bucket >= $2 AND bucket < $3",
    [siteId, fromIso, toIso],
  );
}
