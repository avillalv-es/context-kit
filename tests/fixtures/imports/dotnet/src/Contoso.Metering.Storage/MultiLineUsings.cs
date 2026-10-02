using Contoso
    .Metering
    .Abstractions;
using System;

namespace Contoso.Metering.Storage;

public static class MultiLineUsings
{
    // A VERBATIM string whose body starts at column zero. @"..." spans lines,
    // and so does the quote state that keeps its body out of the scan: the
    // 'using' below is text. Contoso.Metering.Phantom IS declared (in
    // Core/Decoys.cs), so a using read from here would draw an edge to it.
    public const string Sample = @"
using Contoso.Metering.Phantom;
";
}
