using Telemetry;
using Options;
using Microsoft.Extensions.DependencyInjection;

namespace Contoso.Metering.Api;

// 'Telemetry' is a root namespace DECLARED in this repo, by
// Contoso.Metering.Telemetry/Counters.cs ('namespace Telemetry;'). The using
// resolves there and only there. Storage/Telemetry.cs shares the BASENAME but
// declares Contoso.Metering.Storage, and a file name is not a namespace, so it
// must draw no edge. (It used to draw one, by suffix-matching the name; the
// edge was a coincidence and pointed into a project this one never references.)
//
// 'Options' is declared as a namespace nowhere. Two FILES are named
// Options.cs, but that is no more a namespace than Telemetry.cs was, so the
// using drops as external instead of picking, or refusing to pick, a file.
internal static class TelemetryStartup
{
    public static IServiceCollection AddMetering(IServiceCollection s) => s;
}
