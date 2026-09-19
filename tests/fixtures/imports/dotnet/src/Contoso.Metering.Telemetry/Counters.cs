extern alias LegacyMetrics;

using System.Diagnostics.Metrics;

#if NET8_0_OR_GREATER
using System.Diagnostics.Tracing;
#else
using Contoso.Metering.Compat.Tracing;
#endif

namespace Telemetry;

// 'namespace Telemetry;' declares the root namespace that
// Api/TelemetryStartup.cs imports. The extractor never reads a namespace
// DECLARATION, so its INFERRED edge for 'using Telemetry;' lands on
// Storage/Telemetry.cs instead of here.
public sealed class Counters
{
    public long Reads { get; set; }
}
