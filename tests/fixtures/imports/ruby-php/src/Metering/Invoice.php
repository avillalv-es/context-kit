<?php

declare(strict_types=1);

namespace App\Metering;

use App\Support\Format;

final class Invoice
{
    /**
     * Raised when the boot file has not run. The require line in the message
     * below is text: it names a real file, so a reader that does not track
     * string state invents Invoice -> bootstrap.php from it.
     */
    private const NOT_BOOTED = "require_once 'bootstrap.php' before building an invoice";

    /** @param list<int> $cents */
    public function __construct(
        private string $account,
        private array $cents,
    ) {
        if (!\function_exists('date_default_timezone_set')) {
            throw new \RuntimeException(self::NOT_BOOTED);
        }
    }

    /** @return list<array{string}> */
    public function rows(): array
    {
        return \array_map(
            static fn (int $c): array => [Format::money($c)],
            $this->cents
        );
    }

    public function account(): string
    {
        return $this->account;
    }
}
