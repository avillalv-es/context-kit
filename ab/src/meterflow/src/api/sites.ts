import { findSite } from "../db/sitesRepo.js";
import { describeSite } from "../domain/site.js";
import { validateSiteId } from "../domain/validate.js";
import { requireApiKey, problem, type Req, type Res } from "./middleware.js";

export async function getSite(req: Req): Promise<Res> {
  try {
    requireApiKey(req);
    const site = await findSite(validateSiteId(req.body.siteId));
    return { status: 200, body: { siteId: site.siteId, label: describeSite(site) } };
  } catch (e) {
    return problem(e);
  }
}
