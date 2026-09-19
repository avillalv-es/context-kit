using System.Collections.Generic;
using System.Linq;

namespace Contoso.Metering.Telemetry;

// Saved with a UTF-8 BOM, which is what Visual Studio writes by default. The
// BOM bytes sit in front of 'using' on line 1, so the ^ anchor fails: that
// import is neither captured nor logged. Line 2 carries no BOM and IS logged.
// Every VS-authored .cs file in a repo loses its first using this way.
public sealed class Options
{
    public IReadOnlyList<string> Sinks { get; init; } = new List<string>();
    public IEnumerable<string> Sorted => Sinks.OrderBy(s => s);
}
