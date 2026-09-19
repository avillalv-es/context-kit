<?php

declare(strict_types=1);

require_once __DIR__ . '/../bootstrap.php';

use App\Metering\Invoice;
use App\Support\Format;
use App\Billing\Statement;
use Psr\Log\LoggerInterface;

// psr-4 maps classes to files. A function import lands on a path no file
// backs, because the helpers live inside a class file that require pulls in.
// Dropping the `function ` keyword is what makes this a clean miss instead
// of a garbage specifier.
use function App\Support\money_fmt;

/** @var LoggerInterface|null $logger */
$logger = null;

$formatter = new Format();
$invoice = new Invoice('ops', [1250, 400]);
$statement = new Statement($invoice);

// `use` here binds a closure variable. It is not an import, and the word
// after it is a parenthesis rather than a namespace.
$render = static function (array $rows) use ($formatter): string {
    return $formatter->table($rows);
};

echo $render($invoice->rows()), PHP_EOL;
echo $statement->line(), PHP_EOL;

// include, not require, and without _once. Same form, same resolution.
include __DIR__ . '/partials/footer.php';
