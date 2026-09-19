using System;

namespace Contoso.Metering.Storage;

public static class GlobPatterns
{
    // A block-comment OPENER inside a string literal. Quote state is checked
    // before comment syntax, so this must not open a block comment. The proof
    // is that the garbage capture on line 14 still reaches the drop log.
    public const string StarStar = "/*";

    public static string Read(string path)
    {
        using var handle = OpenHandle(path);
        return handle.ToString() ?? StarStar;
    }

    private static IDisposable OpenHandle(string p) => new System.IO.MemoryStream();
}
