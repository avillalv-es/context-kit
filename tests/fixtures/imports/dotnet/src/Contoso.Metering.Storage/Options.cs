namespace Contoso.Metering.Storage;

// One of TWO files named Options.cs in this fixture. The other is
// src/Contoso.Metering.Telemetry/Options.cs. A basename match cannot tell
// them apart, so 'using Options;' must DROP as ambiguous, never pick one.
public sealed class Options
{
    public string ConnectionString { get; init; } = string.Empty;
}
