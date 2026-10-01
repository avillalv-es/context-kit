namespace Contoso.Metering.Storage;

// One of TWO files named Options.cs in this fixture. The other is
// src/Contoso.Metering.Telemetry/Options.cs. Neither declares a namespace
// called 'Options' (this one declares Contoso.Metering.Storage), so
// 'using Options;' in Api/TelemetryStartup.cs drops as external and picks
// neither.
public sealed class Options
{
    public string ConnectionString { get; init; } = string.Empty;
}
