using static Telemetry.Counters;
using Sink = Contoso.Metering.Telemetry.Options;
using static System.Math;

namespace Contoso.Metering.Storage;

// 'using static' names a TYPE, so Telemetry.Counters is not a namespace and
// the file is found through the namespace one segment up, 'Telemetry'
// (Telemetry/Counters.cs). An alias may name a type too, so
// Contoso.Metering.Telemetry.Options resolves through
// 'Contoso.Metering.Telemetry' (Telemetry/Options.cs). System.Math climbs to
// 'System', which this repo does not declare: external, no edge.
internal static class MeterSink
{
    public static double Round(double kwh) => Math.Round(kwh);
}
