using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Perangkat TNI (pairing, tanpa login). Satu nama petugas per perangkat (alter_75).
//
// Claim dipanggil SEBELUM perangkat punya token -- handler hanya menyisipkan
// header bila token sudah ada di localStorage, jadi request ini lolos apa adanya.
public class TniPerangkatApiService
{
    // _http = client PERANGKAT (X-Tni-Token): claim, me.
    // Jwt   = client ber-JWT: SELURUH pengelolaan perangkat, yang
    //         memang hanya boleh dilakukan admin yang login.
    private readonly HttpClient _http;
    private readonly IHttpClientFactory _factory;

    public TniPerangkatApiService(HttpClient http, IHttpClientFactory factory)
    {
        _http = http;
        _factory = factory;
    }

    private HttpClient Jwt => _factory.CreateClient("API");

    public async Task<(bool Success, string Error, TniClaimResultDto? Hasil)> ClaimAsync(string pairingCode)
    {
        var response = await _http.PostAsJsonAsync("api/tni/perangkat/claim",
            new TniClaimRequest { PairingCode = pairingCode });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error)
                ? "Kode pairing tidak valid atau sudah kedaluwarsa."
                : error.Trim('"'), null);
        }

        return (true, string.Empty, await response.Content.ReadFromJsonAsync<TniClaimResultDto>());
    }

    // null = token tidak ada / sudah dicabut -> perangkat harus pairing ulang.
    public async Task<TniPerangkatMeDto?> GetMeAsync()
    {
        var response = await _http.GetAsync("api/tni/perangkat/me");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniPerangkatMeDto>();
    }

    // ---------------- pengelolaan (butuh login; dipanggil halaman admin) ----------------

    public async Task<List<TniPerangkatDto>> GetListAsync()
    {
        var response = await Jwt.GetAsync("api/tni/perangkat");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniPerangkatDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, TniPairingCodeDto? Hasil)> GeneratePairingAsync(int id)
    {
        var response = await Jwt.PostAsync($"api/tni/perangkat/{id}/pairing", null);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuat kode." : error.Trim('"'), null);
        }

        return (true, string.Empty, await response.Content.ReadFromJsonAsync<TniPairingCodeDto>());
    }

    public async Task<(bool Success, string Error)> SimpanAsync(int? id, TniPerangkatCreateRequest request)
    {
        var response = id is null or 0
            ? await Jwt.PostAsJsonAsync("api/tni/perangkat", request)
            : await Jwt.PutAsJsonAsync($"api/tni/perangkat/{id}", request);

        return await Hasil(response, "Gagal menyimpan perangkat.");
    }

    public async Task<(bool Success, string Error)> HapusAsync(int id)
        => await Hasil(await Jwt.DeleteAsync($"api/tni/perangkat/{id}"), "Gagal menghapus perangkat.");

    public async Task<(bool Success, string Error)> UnpairAsync(int id)
        => await Hasil(await Jwt.PostAsync($"api/tni/perangkat/{id}/unpair", null), "Gagal memutus perangkat.");

    private static async Task<(bool Success, string Error)> Hasil(HttpResponseMessage r, string bawaan)
    {
        if (r.IsSuccessStatusCode) return (true, string.Empty);

        var error = await r.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? bawaan : error.Trim('"'));
    }
}
