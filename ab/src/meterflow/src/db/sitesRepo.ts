import { getDb } from "./client.js";
import { NotFound } from "../lib/errors.js";
import type { Site } from "../domain/site.js";

export async function findSite(siteId: string): Promise<Site> {
  const db = getDb();
  const rows = await db.query("SELECT * FROM sites WHERE site_id = $1", [siteId]);
  if (rows.length === 0) throw new NotFound(`site ${siteId}`);
  return rows[0] as unknown as Site;
}
