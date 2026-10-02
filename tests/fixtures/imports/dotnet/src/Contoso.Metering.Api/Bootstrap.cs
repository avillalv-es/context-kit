using Contoso.Metering.Archived;
using Contoso.Metering.Generated;

namespace Contoso.Metering.Api;

// Both usings above name a namespace that exists only as TEXT in
// Core/Decoys.cs - one in a comment, one in a verbatim string. No file
// declares either, so both drop as external and neither draws an edge.
internal static class Bootstrap
{
}
