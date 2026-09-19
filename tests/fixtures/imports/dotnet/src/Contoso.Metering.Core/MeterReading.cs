using System;

namespace Contoso.Metering.Core;

public readonly record struct MeterReading(string MeterId, double Kwh, DateTimeOffset TakenAt)
{
    public override string ToString() => $"{MeterId}={Kwh}";
}
