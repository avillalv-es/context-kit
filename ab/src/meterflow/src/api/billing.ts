import { chargeFor } from "../domain/billing.js";
import { readingsForSite } from "../db/readingsRepo.js";
import { validateSiteId } from "../domain/validate.js";
import { requireApiKey, problem, type Req, type Res } from "./middleware.js";
import type { Tariff } from "../domain/tariff.js";

export async function getCharge(req: Req): Promise<Res> {
  try {
    requireApiKey(req);
    const siteId = validateSiteId(req.body.siteId);
    const rows = await readingsForSite(siteId, String(req.body.from), String(req.body.to));
    const tariffs = (req.body.tariffs ?? []) as Tariff[];
    const charge = chargeFor(rows as never, tariffs, String(req.body.to));
    return { status: 200, body: charge };
  } catch (e) {
    return problem(e);
  }
}
