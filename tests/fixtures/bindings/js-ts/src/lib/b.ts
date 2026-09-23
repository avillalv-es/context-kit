// Stub import target: every relative "./b" specifier in this folder, plus
// the "./lib/b" and "@lib/b" specifiers used from src/route-a.ts and
// src/Report.vue, all resolve to this one file. The names below only need
// to exist for the trap files to import — they don't need to cohere as a
// real API.
export const important = "important";
export const other = "other";
export const importer = "importer";
export const exportData = "exportData";
export const exported = "exported";
export const a = "a";
export const b = "b";
export const b2 = "b2";
export const c = "c";
export const d = "d";
export const Foo = "Foo";
export const x = "x";
export const type = "type";
export type T = string;

export default function importMap(arg: string): string {
  return `${arg}:${arg}`;
}
