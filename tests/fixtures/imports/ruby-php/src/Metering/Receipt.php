<?php

declare(strict_types=1);

namespace App\Metering;

/*
 * Before the Billing split this class imported the statement directly. The
 * line below is history. It is flush against the left margin rather than
 * indented behind a star, so a reader that does not carry block-comment
 * state from line to line sees a real import at column zero:
use App\Billing\Statement;
 */

final class Receipt
{
    public function __construct(private string $account)
    {
    }

    /**
     * Help text. The nowdoc body is data: the use line and the require line
     * inside it both name files that really exist, and both sit outside
     * every quote on their own line.
     */
    public function help(): string
    {
        return <<<'TXT'
            Autoload off? Add these two by hand:
            use App\Support\Format;
            require_once 'billing/Statement.php';
            TXT;
    }

    public function account(): string
    {
        return $this->account;
    }
}
