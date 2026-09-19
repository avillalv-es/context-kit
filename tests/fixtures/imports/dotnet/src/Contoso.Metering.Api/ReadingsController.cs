using Microsoft.AspNetCore.Mvc;
using Contoso.Metering.Abstractions;
using Contoso.Metering.Core;

namespace Contoso.Metering.Api.Controllers
{
    [ApiController]
    [Route("readings")]
    public sealed class ReadingsController : ControllerBase
    {
        private readonly IMeterReader _reader;

        public ReadingsController(IMeterReader reader) => _reader = reader;

        [HttpGet("{meterId}")]
        public ActionResult<MeterReading> Get(string meterId)
        {
            var raw = _reader.ReadRaw(meterId);
            return new MeterReading(meterId, raw.Count, System.DateTimeOffset.UtcNow);
        }
    }
}
