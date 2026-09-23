// Trap: the same physical file (src/lib/b.ts) reached twice in one file
// through two different specifiers — a relative path and the "@lib/*"
// tsconfig alias. A resolver keyed on specifier text rather than resolved
// path double-counts this as two distinct targets.
import { b } from './lib/b';
import { b2 } from '@lib/b';

export const combined = b + b2;
