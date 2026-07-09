using System.Net.Http.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

public class PrintApiClient
{
    private readonly HttpClient _http;

    public PrintApiClient(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<PrintJobClaimedDto>> ClaimAsync(int batchSize, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/print/claim", new PrintJobClaimRequest { BatchSize = batchSize }, ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<List<PrintJobClaimedDto>>(cancellationToken: ct) ?? new();
    }

    public async Task ReportAsync(int printJobId, bool success, string? errorMessage, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/print/report", new PrintJobReportRequest
        {
            PrintJobId = printJobId,
            Success = success,
            ErrorMessage = errorMessage
        }, ct);
        response.EnsureSuccessStatusCode();
    }
}
