<?php

declare(strict_types=1);

namespace App\Billing;

// Same basename as src/Support/Format.php, different directory, different
// namespace, different job, and reached through a different psr-4 prefix.
// Nothing but the full path separates the two.
trait Format
{
    public function currency(): string
    {
        return 'USD';
    }
}
