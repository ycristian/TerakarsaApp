using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 64: stok kemeja & celana PDH TNI AD.
public class TniStokApiService
{
    private readonly HttpClient _http;

    public TniStokApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<TniStokSaldoDto>> GetSaldoAsync(
        string jenis, string? search = null, bool hanyaAda = false)
    {
        var url = $"api/tni/stok/saldo?jenis={jenis}&hanyaAda={hanyaAda.ToString().ToLowerInvariant()}";
        if (!string.IsNullOrWhiteSpace(search)) url += $"&search={Uri.EscapeDataString(search)}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniStokSaldoDto>>() ?? new();
    }

    public async Task<TniStokRiwayatResult> GetRiwayatAsync(
        string? jenis = null, int? polaId = null, string? jenisMutasi = null,
        int pageNumber = 1, int pageSize = 50, bool hanyaManual = false)
    {
        var q = new List<string> { $"pageNumber={pageNumber}", $"pageSize={pageSize}" };
        if (hanyaManual) q.Add("hanyaManual=true");
        if (!string.IsNullOrWhiteSpace(jenis)) q.Add($"jenis={jenis}");
        if (polaId.HasValue) q.Add($"polaId={polaId.Value}");
        if (!string.IsNullOrWhiteSpace(jenisMutasi)) q.Add($"jenisMutasi={jenisMutasi}");

        var response = await _http.GetAsync($"api/tni/stok/riwayat?{string.Join("&", q)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniStokRiwayatResult>() ?? new();
    }

    public async Task<(bool Success, string Error, TniStokSetoranHasilDto? Hasil)> SetoranAsync(
        TniStokSetoranRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/tni/stok/setoran", request);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan setoran." : error.Trim('"'), null);
        }

        return (true, string.Empty, await response.Content.ReadFromJsonAsync<TniStokSetoranHasilDto>());
    }

    public async Task<TniStokRiwayatManualResult> GetRiwayatManualAsync(
        string? jenisMutasi = null, int pageNumber = 1, int pageSize = 20)
    {
        var url = $"api/tni/stok/riwayat-manual?pageNumber={pageNumber}&pageSize={pageSize}";
        if (!string.IsNullOrWhiteSpace(jenisMutasi)) url += $"&jenisMutasi={jenisMutasi}";

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<TniStokRiwayatManualResult>() ?? new();
    }

    public async Task<(bool Success, string Error)> EditSetoranAsync(int setoranId, TniStokSetoranRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/tni/stok/setoran/{setoranId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan setoran." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> HapusSetoranAsync(int setoranId)
    {
        var response = await _http.DeleteAsync($"api/tni/stok/setoran/{setoranId}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus setoran." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> EditKeluarAsync(int keluarId, TniStokKeluarRequest request)
    {
        var response = await _http.PutAsJsonAsync($"api/tni/stok/keluar/{keluarId}", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan pengeluaran." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> HapusKeluarAsync(int keluarId)
    {
        var response = await _http.DeleteAsync($"api/tni/stok/keluar/{keluarId}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus pengeluaran." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> HapusMutasiAsync(int mutasiId)
    {
        var response = await _http.DeleteAsync($"api/tni/stok/mutasi/{mutasiId}");
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menghapus." : error.Trim('"'));
    }

    public async Task<(bool Success, string Error)> KeluarAsync(TniStokKeluarRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/tni/stok/keluar", request);
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan." : error.Trim('"'));
    }
}
