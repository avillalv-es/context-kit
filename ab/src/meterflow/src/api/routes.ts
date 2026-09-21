import { postReading, getSummary } from "./readings.js";
import { getSite } from "./sites.js";
import { getCharge } from "./billing.js";
import type { Req, Res } from "./middleware.js";

export const routes: Record<string, (r: Req) => Promise<Res>> = {
  "POST /v1/readings": postReading,
  "GET /v1/readings/summary": getSummary,
  "GET /v1/sites": getSite,
  "GET /v1/billing/charge": getCharge,
};
