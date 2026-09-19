<?php

declare(strict_types=1);

namespace App\Support;

// The other Roundable. billing/Statement.php declares a trait of this name
// inside its own file and never touches this one. The basename is unique in
// the tree, which is exactly what makes a unique-suffix fallback dangerous
// here: unique is not the same as correct.
trait Roundable
{
    public function roundUp(int $cents): int
    {
        return (int) (\ceil($cents / 50) * 50);
    }
}
