using Xunit;
using Newtonsoft.Json;
using Contoso.Metering.Core;

namespace Contoso.Metering.Core.Tests;

public class ReadingParserTests
{
    [Fact]
    public void ParsesInvariantDecimal()
    {
        var parser = new ReadingParser();
        var reading = parser.Parse("12.5");

        Assert.Equal(12.5, reading.Kwh);
        Assert.NotNull(JsonConvert.SerializeObject(reading));
    }
}
