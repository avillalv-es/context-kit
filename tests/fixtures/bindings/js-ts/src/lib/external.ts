// Trap: bare specifiers for packages that are not in this tree at all.
// These import edges should resolve to nothing, unlike every "./..." and
// "@lib/..." specifier elsewhere in this folder.
import { z } from 'left-pad-imaginary';
import leftover from 'not-a-real-package/subpath';
const dynamic = require('also-not-real');

export { z, leftover, dynamic };
