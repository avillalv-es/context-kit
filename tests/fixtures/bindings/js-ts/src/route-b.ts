// Trap: the same physical file (src/lib/b.ts) reached twice in one file,
// this time through the "@lib/*" tsconfig alias FIRST and the relative
// path second — the reverse order of route-a.ts. A resolver keyed on which
// specifier came first, rather than on the resolved path, could treat the
// second import as a fresh target instead of the same one.
import { x as viaAlias } from '@lib/b';
import { b as viaRel } from './lib/b';

export const combinedB = String(viaAlias) + viaRel;
