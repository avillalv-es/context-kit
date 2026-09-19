<?php

declare(strict_types=1);

namespace App\Support;

// Before autoloading, this file pulled the invoice class in by hand:
// require_once __DIR__ . '/../Metering/Invoice.php';
// and then imported it:
// use App\Metering\Invoice;
// Both are comments now. Format has no dependencies of its own and must end
// the scan with zero outgoing edges.

final class Format
{
    public static function money(int $cents): string
    {
        return \sprintf('$%0.2f', $cents / 100);
    }

    public function table(array $rows): string
    {
        return \implode("\n", \array_map(
            static fn (array $row): string => \implode("\t", $row),
            $rows
        ));
    }
}
