<?php

declare(strict_types=1);

/*
 * Legacy boot file. Before composer, loading was done by hand here:
 *
   require_once 'src/Metering/Invoice.php';
 *
 * That is history - autoload covers every PSR-4 class now - but it is still
 * a require line sitting at the start of a line inside a block comment.
 */

// Composer's autoloader is generated into vendor/, which is not committed,
// so this path exists at run time and never in the repo.
require_once __DIR__ . '/vendor/autoload.php';

# The formatter predates the App\ namespace and is still loaded by path,
# resolved from the project root rather than from this file's directory.
require_once 'src/Support/Format.php';

# require_once 'src/Metering/Invoice.php';

// Two files here are called Format.php: src/Support/Format.php and
// billing/Format.php. This line names neither directory. A require is a
// path, not a name - it resolves as a path or it drops, and it never falls
// back to a basename match that would pick one of the two at random.
require_once 'Format.php';

// The same mistake with a name that is UNIQUE in the tree. Ambiguity is not
// what makes the line above unsafe; being a name rather than a path is.
// src/Support/Roundable.php is the only Roundable.php here, and this line
// must still drop - a require resolves against the including file's
// directory and the project root, and nowhere else.
require_once 'Roundable.php';

// The shared legacy shim is checked out beside the project, not inside it.
// The path climbs above the root, so it drops rather than being clamped.
require_once __DIR__ . '/../outside/legacy.php';

// A nowdoc. Its body is data. The require line inside it starts flush left
// with its keyword outside every quote on that line, and the file it names
// really exists, so only heredoc state that persists across lines keeps it
// out of the graph.
$bootHelp = <<<'HELP'
Autoload off? The hand-rolled boot used to do this:
require_once 'billing/Format.php';
and then include the front controller.
HELP;

date_default_timezone_set('UTC');
