using System;

namespace Contoso.Metering.Storage;

/// <summary>
/// A storage-side counter sink. Its FILE is named Telemetry.cs; its
/// NAMESPACE is Contoso.Metering.Storage. Nothing here belongs to the root
/// namespace 'Telemetry' that Api/TelemetryStartup.cs imports - the two are
/// linked only by a basename coincidence, and this file draws no edge from it.
/// </summary>
public sealed class Telemetry
{
    public static DateTimeOffset Started { get; } = DateTimeOffset.UtcNow;
}
