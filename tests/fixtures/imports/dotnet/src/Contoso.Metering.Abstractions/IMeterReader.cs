using System;
using System.Collections.Generic;

namespace Contoso.Metering.Abstractions;

/// <summary>Reads raw meter samples. Implemented in Contoso.Metering.Core.</summary>
public interface IMeterReader
{
    IReadOnlyList<string> ReadRaw(string meterId);

    DateTimeOffset LastSeen { get; }
}
