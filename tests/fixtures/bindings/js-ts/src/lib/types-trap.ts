// Trap: three ways "type" collides with import syntax. `type as t` imports
// the *value* named "type" (not a type-only import — there is no name after
// it for "type" to modify). `type{T}` is a type-only import with no space
// before the brace. `type` alone with nothing after it is a *default*
// import bound to the local name "type", not a type-only import of nothing.
import { type as t } from './b';
import type{T} from './b';
import type from './b';

export const usesType: T = t + String(type);
