import { validateRaw, validateSiteId } from "../domain/validate.js";
import { toReading, sumWh } from "../domain/reading.js";
import { toKwh } from "../lib/units.js";
import { insertReadings, readingsForSite } from "../db/readingsRepo.js";
import { requireApiKey, problem, type Req, type Res } from "./middleware.js";

export async function postReading(req: Req): Promise<Res> {
  try {
    requireApiKey(req);
    const reading = toReading(validateRaw(req.body));
    await insertReadings([reading]);
    return { status: 201, body: { bucket: reading.bucket } };
  } catch (e) {
    return problem(e);
  }
}

export async function getSummary(req: Req): Promise<Res> {
  try {
    requireApiKey(req);
    const siteId = validateSiteId(req.body.siteId);
    const rows = await readingsForSite(siteId, String(req.body.from), String(req.body.to));
    const total = sumWh(rows as never);
    return { status: 200, body: { siteId, totalKwh: toKwh(total) } };
  } catch (e) {
    return problem(e);
  }
}
