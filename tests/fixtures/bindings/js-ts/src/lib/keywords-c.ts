// Trap: the same originating export ("a") imported twice under two
// different local names in one file — once renamed to "exported", once
// renamed to "reimport". Neither local name collides with the other, but a
// resolver keyed on the *local* name alone could mistake this for two
// different source exports.
import { a as exported } from './b';
import { a as reimport } from './b';

export const summary3 = exported + reimport;
