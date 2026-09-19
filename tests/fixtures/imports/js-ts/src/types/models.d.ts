// A .d.ts is a .ts: it is scanned, and its imports are edges.
import { type Formatted } from "../lib/format";

export type Model = {
  id: string;
  label: Formatted;
};
