import { routes } from "./api/routes.js";
import { loadConfig } from "./lib/config.js";
import { log } from "./lib/logger.js";

export async function main(): Promise<void> {
  loadConfig();
  log("info", "boot", { routes: Object.keys(routes).length });
}
