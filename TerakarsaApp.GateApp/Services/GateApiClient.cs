using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.GateApp.Services;

// Prompt 70: satu-satunya jalan GateApp bicara dengan server. Header X-Gate-Api-Key dipasang
// sekali di Program/App (pola PrintApiClient di TerakarsaApp.PrintService).
public class GateApiClient
{
    private readonly HttpClient _http;

    public GateApiClient(HttpClient http)
    {
        _http = http;
    }

    public async Task<GateCardSyncResult> GetCardSyncAsync(CancellationToken ct)
    {
        var response = await _http.GetAsync("api/gate/cards", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<GateCardSyncResult>(cancellationToken: ct) ?? new();
    }

    // Satu panggilan untuk satu atau banyak tap. Server mengurutkan menurut tappedAt dan
    // mengembalikan hasil dengan urutan yang sama dengan input.
    public async Task<List<GateTapResultDto>> PostTapsAsync(string gateCode, List<GateTapRequest> taps, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/gate/taps",
            new GateTapBatchRequest { GateCode = gateCode, Taps = taps }, ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<List<GateTapResultDto>>(cancellationToken: ct) ?? new();
    }

    public async Task<GateCountsDto> GetCountsAsync(string gateCode, CancellationToken ct)
    {
        var response = await _http.GetAsync($"api/gate/counts?gateCode={Uri.EscapeDataString(gateCode)}", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<GateCountsDto>(cancellationToken: ct) ?? new();
    }

    public async Task<List<GatePendingRowDto>> GetPendingAsync(string mode, CancellationToken ct)
    {
        var response = await _http.GetAsync($"api/gate/pending?mode={Uri.EscapeDataString(mode)}", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<List<GatePendingRowDto>>(cancellationToken: ct) ?? new();
    }

    // Butuh ONLINE: UID kembar harus dicek ke server, jadi TIDAK pernah diantrekan.
    public async Task<(bool Success, string Error)> RegisterCardAsync(GateRegisterCardRequest request, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/gate/cards/register", request, ct);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        return (false, await ExtractErrorAsync(response, ct));
    }

    // Butuh ONLINE, dengan alasan yang sama (dan supaya jejak perubahan tercatat langsung).
    public async Task<(bool Success, string Error)> UpdateEmployeeAsync(GateUpdateEmployeeRequest request, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/gate/employees/update", request, ct);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        return (false, await ExtractErrorAsync(response, ct));
    }

    // Butuh ONLINE: pembatalan harus kena sesi yang SAAT INI masih OPEN, jadi tidak diantrekan.
    public async Task<(bool Success, string Error)> CancelSessionAsync(GateCancelSessionRequest request, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/gate/sessions/cancel", request, ct);
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        return (false, await ExtractErrorAsync(response, ct));
    }

    // API mengembalikan pesan RAISERROR dari SP (bahasa Indonesia) sebagai body 400 -- pesannya
    // yang ditampilkan ke satpam, bukan "Bad Request".
    private static async Task<string> ExtractErrorAsync(HttpResponseMessage response, CancellationToken ct)
    {
        var body = await response.Content.ReadAsStringAsync(ct);
        if (string.IsNullOrWhiteSpace(body)) return "Gagal menyimpan ke server.";
        try
        {
            var parsed = JsonSerializer.Deserialize<string>(body);
            if (!string.IsNullOrWhiteSpace(parsed)) return parsed;
        }
        catch (JsonException)
        {
            // body bukan JSON string biasa (mis. halaman error HTML) -- pakai apa adanya.
        }
        return body;
    }
}
