using Microsoft.AspNetCore.Builder;
using Contoso.Metering.Core;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddSingleton<ReadingParser>();
builder.Services.AddControllers();

var app = builder.Build();
app.MapControllers();
app.Run();
