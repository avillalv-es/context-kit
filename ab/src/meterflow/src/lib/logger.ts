type Level = "debug" | "info" | "warn" | "error";

const REDACT = ["mpan", "meterSerial", "customerRef"];

export function log(level: Level, event: string, fields: Record<string, unknown> = {}): void {
  const safe: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) {
    safe[k] = REDACT.includes(k) ? "[redacted]" : v;
  }
  process.stdout.write(JSON.stringify({ level, event, ...safe }) + "\n");
}
