// Deliberate basename collision with src/lib/constants.ts. src/hooks/useData.ts
// imports both, one line apart, so a basename-keyed matcher picks the wrong one.
export const HOOK_LIMIT = 10;
