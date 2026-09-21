import { loadConfig } from "../lib/config.js";

export interface Row { [k: string]: unknown }

export interface Db {
  query(sql: string, params?: unknown[]): Promise<Row[]>;
}

let db: Db | undefined;

export function getDb(): Db {
  if (!db) {
    const cfg = loadConfig();
    db = {
      async query(sql: string) {
        void cfg;
        void sql;
        return [];
      },
    };
  }
  return db;
}
