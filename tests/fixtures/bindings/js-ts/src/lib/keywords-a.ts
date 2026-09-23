// Trap: import/export specifiers whose local identifiers are themselves
// built from the keywords "import"/"export" ("importMap", "importer",
// "exportData", ...). An extractor that scans for the bare words "import"
// or "export" as delimiters, instead of matching whole tokens, misreads
// these identifiers as more syntax.
import importMap from './b';
import { important, other } from './b';
export { importer } from './b';
import { exportData } from './b';

export const summary = importMap('x') + important + other + exportData;
