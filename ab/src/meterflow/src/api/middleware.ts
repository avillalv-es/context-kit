import { DomainError } from "../lib/errors.js";
import { log } from "../lib/logger.js";

export interface Req { path: string; body: Record<string, unknown>; headers: Record<string, string> }
export interface Res { status: number; body: unknown }

export function requireApiKey(req: Req): void {
  if (!req.headers["x-api-key"]) {
    throw new DomainError("unauthorized", "missing api key", 401);
  }
}

export function problem(e: unknown): Res {
  if (e instanceof DomainError) {
    return { status: e.status, body: { type: `about:blank#${e.code}`, title: e.message, status: e.status } };
  }
  log("error", "unhandled", { message: String(e) });
  return { status: 500, body: { type: "about:blank#internal", title: "internal error", status: 500 } };
}
