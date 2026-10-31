using System.Net.Http.Json;
using System.Text.Json;
using TerakarsaApp.Shared.Divisions;
using TerakarsaApp.Shared.Payroll;

namespace TerakarsaApp.Client.Services;

// Prompt 83: client untuk module PAYROLL_REKAP (api/payroll-rekap) -- isi satu periode
// gajian (baris LOG + MANUAL), koreksi harga per lock item, finalisasi/unfinalisasi periode.
//
// UnitPrice NULL itu BERARTI "belum diisi" -- jangan pernah menukarnya dengan 0 di sini,
// karena 0 adalah harga yang sah (step Bundling).
public class PayrollRekapApiService
{
    private readonly HttpClient _http;

    public PayrollRekapApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<PayrollRekapPeriodDto>> GetPeriodsAsync()
    {
        var response = await _http.GetAsync("api/payroll-rekap/periods");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<PayrollRekapPeriodDto>>() ?? new();
    }

    public async Task<List<DivisionDto>> GetDivisionsAsync()
    {
        var response = await _http.GetAsync("api/payroll-rekap/divisions");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<DivisionDto>>() ?? new();
    }

    public async Task<PayrollRekapResultDto> GetAsync(
        int payrollPeriodId, int? divisionId, int? resourceId, bool onlyMissingPrice)
    {
        var query = $"api/payroll-rekap/{payrollPeriodId}?onlyMissingPrice={(onlyMissingPrice ? "true" : "false")}";
        if (divisionId.HasValue) query += $"&divisionId={divisionId.Value}";
        if (resourceId.HasValue) query += $"&resourceId={resourceId.Value}";

        var response = await _http.GetAsync(query);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<PayrollRekapResultDto>() ?? new();
    }

    // unitPrice null = kosongkan harga lagi; nilai MINUS diperbolehkan.
    public async Task<(bool Success, string Error)> UpdatePriceAsync(int lockItemId, decimal? unitPrice)
    {
        var response = await _http.PutAsJsonAsync($"api/payroll-rekap/items/{lockItemId}/price",
            new LockItemPriceRequest { UnitPrice = unitPrice });

        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan harga." : error.Trim('"'));
    }

    // Ditolak selama masih ada harga kosong. Badan error-nya { error, missingRows } --
    // daftar baris bermasalah dari SP ikut dikembalikan supaya bisa ditampilkan.
    public async Task<(bool Success, string Error, List<PayrollMissingPriceRowDto> MissingRows)> FinalizeAsync(
        int payrollPeriodId)
    {
        var response = await _http.PostAsync($"api/payroll-rekap/{payrollPeriodId}/finalize", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty, new());

        var body = await response.Content.ReadAsStringAsync();
        var error = "Gagal memfinalisasi periode.";
        var rows = new List<PayrollMissingPriceRowDto>();

        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("error", out var errorProp))
            {
                var text = errorProp.GetString();
                if (!string.IsNullOrWhiteSpace(text)) error = text;
            }
            if (doc.RootElement.TryGetProperty("missingRows", out var rowsProp))
            {
                rows = rowsProp.Deserialize<List<PayrollMissingPriceRowDto>>(
                    new JsonSerializerOptions(JsonSerializerDefaults.Web)) ?? new();
            }
        }
        catch (JsonException)
        {
            // Bukan JSON (mis. error di luar SP) -- pakai badan apa adanya.
            if (!string.IsNullOrWhiteSpace(body)) error = body.Trim('"');
        }

        return (false, error, rows);
    }

    public async Task<(bool Success, string Error)> UnfinalizeAsync(int payrollPeriodId)
    {
        var response = await _http.PostAsync($"api/payroll-rekap/{payrollPeriodId}/unfinalize", null);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuka periode." : error.Trim('"'));
    }
}
