using Microsoft.Extensions.Options;
using TerakarsaApp.PrintService;

var builder = Host.CreateApplicationBuilder(args);

// Bisa jalan sebagai Windows Service maupun console biasa (dotnet run / .exe langsung).
builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "TmosPrintService";
});

builder.Services.Configure<PrintWorkerOptions>(builder.Configuration.GetSection("PrintService"));

builder.Services.AddHttpClient<PrintApiClient>((sp, client) =>
{
    var options = sp.GetRequiredService<IOptions<PrintWorkerOptions>>().Value;
    if (!string.IsNullOrWhiteSpace(options.ApiBaseUrl))
        client.BaseAddress = new Uri(options.ApiBaseUrl);
    client.DefaultRequestHeaders.Add("X-Print-Api-Key", options.ApiKey);
});

builder.Services.AddSingleton<DailyFileLogger>();
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
