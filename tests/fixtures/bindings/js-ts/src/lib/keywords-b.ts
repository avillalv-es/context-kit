// Trap: continued from keywords-a.ts — "exported" is bound as a plain named
// import here, and again (differently) in keywords-c.ts via `as`.
import { exported, other } from './b';

export const summary2 = exported + other;
