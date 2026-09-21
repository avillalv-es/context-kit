export interface Site {
  siteId: string;
  name: string;
  capacityKva: number;
  createdAt: string;
}

export function describeSite(s: Site): string {
  return `${s.name} (${s.siteId})`;
}
