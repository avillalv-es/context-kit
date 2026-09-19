using Telemetry;
using Options;
using Microsoft.Extensions.DependencyInjection;

namespace Contoso.Metering.Api;

// 'Telemetry' is an EXTERNAL root namespace. The extractor cannot know that,
// finds exactly one file named Telemetry.cs anywhere in the tree, and emits an
// INFERRED edge to src/Contoso.Metering.Storage/Telemetry.cs - a file in a
// project this one has no ProjectReference to.
//
// 'Options' matches TWO files named Options.cs, so it drops as ambiguous.
// The difference between line 1 and line 2 is luck, not correctness.
internal static class TelemetryStartup
{
    public static IServiceCollection AddMetering(IServiceCollection s) => s;
}
