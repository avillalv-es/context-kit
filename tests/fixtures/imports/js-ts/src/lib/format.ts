export type Formatted = { text: string };

// NOTE: do not import { LABELS } from "./constants" here - format must stay a
// leaf so the barrel has no cycle.
const TEMPLATE = "require('./format') is not how you load this module";

export function format(value: string): Formatted {
  return { text: value.trim() };
}

export function slug(value: string): string {
  return value.toLowerCase().replace(/\s+/g, "-");
}

export function describe(): string {
  return TEMPLATE;
}
