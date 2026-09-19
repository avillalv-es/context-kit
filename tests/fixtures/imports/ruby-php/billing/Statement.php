<?php

declare(strict_types=1);

namespace App\Billing;

// An aliased import. Strip the alias or the specifier reads
// "App\Support\FormatasFmt" once whitespace is removed, and the edge to the
// real file is lost. Note also which Format this is: billing/Format.php sits
// in this very directory under the same basename.
use App\Support\Format as Fmt;

// Group use: one statement, two imports. Expanding the braces is the only
// way to see the second one. Taken literally the specifier names a file
// called "{Invoice,Receipt}", which is nothing at all.
use App\Metering\{Invoice, Receipt};

// A trait declared in this same file. `use` inside a class body composes a
// trait - it is not an import and it names no other file. src/Support/Roundable.php
// is a different trait, in a different namespace, that this class never
// touches; it is the only Roundable.php in the tree, so a name-based
// fallback resolves to it happily and is wrong every time.
trait Roundable
{
    private function round2(int $cents): int
    {
        return (int) \round($cents / 100) * 100;
    }
}

final class Statement
{
    use Roundable;

    // Composes App\Billing\Format from billing/Format.php - the unqualified
    // name resolves inside this namespace, and the import above bound the
    // OTHER Format to Fmt. Two files share this basename, so a name-based
    // fallback has to pick, and picking is how the graph starts lying.
    use Format;

    public function __construct(private Invoice $invoice)
    {
    }

    public function line(): string
    {
        return Fmt::money($this->round2(10000)) . ' ' . $this->invoice->account() . ' ' . $this->currency();
    }

    public function receipt(): Receipt
    {
        return new Receipt($this->invoice->account());
    }
}
