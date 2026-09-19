using Contoso
    .Metering
    .Abstractions;
using System;

namespace Contoso.Metering.Storage;

public static class MultiLineUsings
{
    // A VERBATIM string whose body starts at column zero. @"..." spans lines
    // and quote state is not carried across them, so line 14 is scanned as if
    // it were code.
    public const string Sample = @"
using Contoso.Metering.Phantom;
";
}
