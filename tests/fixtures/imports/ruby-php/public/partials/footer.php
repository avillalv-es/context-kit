<?php

declare(strict_types=1);

use App\Support\Format;

// Theme partials are generated into this directory at build time and the
// name is a variable, so the capture stops at the first quoted chunk and
// yields a fragment that names no file. A fragment must drop, not be matched
// loosely against whatever it happens to resemble.
$theme = $theme ?? 'plain';
require_once __DIR__ . '/' . $theme . '.php';

// The shared chrome lives outside the project. Three levels up from
// public/partials/ is above the root, so this drops instead of clamping.
require_once __DIR__ . '/../../../shared/theme.php';

echo Format::money($total ?? 0), PHP_EOL;
