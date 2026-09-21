/** All timestamps are UTC ISO-8601. Local time never enters the system. */
export function toUtcIso(d: Date): string {
  return d.toISOString();
}

export function halfHourBucket(iso: string): string {
  const d = new Date(iso);
  d.setUTCSeconds(0, 0);
  d.setUTCMinutes(d.getUTCMinutes() < 30 ? 0 : 30);
  return d.toISOString();
}

export function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(b) - Date.parse(a)) / 86_400_000);
}
