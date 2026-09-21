export interface Config {
  databaseUrl: string;
  ingestBatchSize: number;
  rollupIntervalMs: number;
}

export function loadConfig(env = process.env): Config {
  const databaseUrl = env.DATABASE_URL;
  if (!databaseUrl) throw new Error("DATABASE_URL is required");
  return {
    databaseUrl,
    ingestBatchSize: Number(env.INGEST_BATCH_SIZE ?? 500),
    rollupIntervalMs: Number(env.ROLLUP_INTERVAL_MS ?? 300_000),
  };
}
