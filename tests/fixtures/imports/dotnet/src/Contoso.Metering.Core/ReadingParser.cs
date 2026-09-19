using System;
using System.Globalization;
using System.IO;
using Contoso.Metering.Abstractions;
using Serilog;
using Json = System.Text.Json;
// using Contoso.Metering.Core.Diagnostics;

/* Removed in ADR-021. Left in a block comment on purpose: the text below sits
   at column zero, so the "using" anchor still matches it line by line.
using Contoso.Metering.Core.Legacy;
*/

namespace Contoso.Metering.Core;

public sealed class ReadingParser : IMeterReader
{
    // A raw string literal whose CONTENT starts at column zero.
    private const string DocSnippet = """
using Contoso.Metering.Ghost;
""";

    public DateTimeOffset LastSeen { get; private set; }

    public IReadOnlyList<string> ReadRaw(string meterId)
    {
        // `using var` is a STATEMENT, not a directive. Same first token.
        using var reader = OpenReader(meterId);
        Log.Information("parsing {Meter} with {Doc}", meterId, DocSnippet);
        return new[] { reader.ReadLine() ?? string.Empty };
    }

    public MeterReading Parse(string line)
    {
        using (var scope = BeginScope(line))
        {
            var kwh = double.Parse(line, CultureInfo.InvariantCulture);
            LastSeen = DateTimeOffset.UtcNow;
            _ = scope;
            return new MeterReading("m-1", kwh, LastSeen);
        }
    }

    private static TextReader OpenReader(string id) => new StringReader(id);

    private static IDisposable BeginScope(string line) => Json.JsonDocument.Parse("{}");
}
