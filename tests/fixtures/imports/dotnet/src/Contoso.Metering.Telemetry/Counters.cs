extern alias LegacyMetrics;

using System.Diagnostics.Metrics;

#if NET8_0_OR_GREATER
using System.Diagnostics.Tracing;
#else
using Contoso.Metering.Compat.Tracing;
#endif

namespace Telemetry;

// 'namespace Telemetry;' declares the root namespace that
// Api/TelemetryStartup.cs imports, so that using resolves to THIS file. The
// same declaration is what 'using static Telemetry.Counters;' in
// Storage/MeterSink.cs lands on, one segment up from the type.
public sealed class Counters
{
    public long Reads { get; set; }
}
