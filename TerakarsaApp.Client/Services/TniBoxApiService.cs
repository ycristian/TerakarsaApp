using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 67: box & scan "Masuk Box" PDH TNI AD.
public class TniBoxApiService
{
    private readonly HttpClient _http;

    public TniBoxApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<List<TniBoxListItemDto>> GetListAsync(
        int? areaId = null, int? satuanId = null, string? status = null, bool? gabungan = null,
        string? cari = null)
    {
        var q = new List<string>();
        if (!string.IsNullOrWhiteSpace(cari)) q.Add($"cari={Uri.EscapeDataString(cari.Trim())}");
        if (areaId.HasValue) q.Add($"areaId={areaId.Value}");
        if (satuanId.HasValue) q.Add($"satuanId={satuanId.Value}");
        if (!string.IsNullOrWhiteSpace(status)) q.Add($"status={status}");
        if (gabungan.HasValue) q.Add($"gabungan={gabungan.Value.ToString().ToLowerInvariant()}");

        var url = "api/tni/box" + (q.Count > 0 ? "?" + string.Join("&", q) : string.Empty);

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniBoxListItemDto>>() ?? new();
    }

    public async Task<List<TniBoxListItemDto>> GetTerbukaAsync(int? areaId = null, int? satuanId = null)
    {
        var q = new List<string>();
        if (areaId.HasValue) q.Add($"areaId={areaId.Value}");
        if (satuanId.HasValue) q.Add($"satuanId={satuanId.Value}");

        var url = "api/tni/box/terbuka" + (q.Count > 0 ? "?" + string.Join("&", q) : string.Empty);

        var response = await _http.GetAsync(url);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniBoxListItemDto>>() ?? new();
    }

    public async Task<TniBoxDetailDto?> GetByIdAsync(int id)
    {
        var response = await _http.GetAsync($"api/tni/box/{id}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniBoxDetailDto>();
    }

    public async Task<(bool Success, string Error, TniBoxCreateHasilDto? Hasil)> CreateAsync(
        TniBoxCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/tni/box", request);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal membuka box." : error.Trim('"'), null);
        }

        return (true, string.Empty, await response.Content.ReadFromJsonAsync<TniBoxCreateHasilDto>());
    }

    public async Task<(bool Success, string Error)> TutupAsync(int id)
        => await Result(await _http.PostAsync($"api/tni/box/{id}/tutup", null));

    public async Task<(bool Success, string Error)> KirimAsync(int id)
        => await Result(await _http.PostAsync($"api/tni/box/{id}/kirim", null));

    public async Task<(bool Success, string Error)> BatalKirimAsync(int id, string alasan)
        => await Result(await _http.PostAsync(
                $"api/tni/box/{id}/batal-kirim?alasan={Uri.EscapeDataString(alasan ?? string.Empty)}", null));

    public async Task<(bool Success, string Error)> BatalTutupAsync(int id, string alasan)
        => await Result(await _http.PostAsync(
                $"api/tni/box/{id}/batal-tutup?alasan={Uri.EscapeDataString(alasan ?? string.Empty)}", null));

    public async Task<(bool Success, string Error)> HapusAsync(int id, string? alasan)
        => await Result(await _http.DeleteAsync(
                $"api/tni/box/{id}?alasan={Uri.EscapeDataString(alasan ?? string.Empty)}"));

    // PDF diambil sebagai bytes DENGAN auth, lalu disimpan lewat helper JS
    // downloadFileFromBytes (fileDownload.js) -- tidak bisa pakai <a href> biasa
    // karena endpoint-nya butuh header Authorization.
    public async Task<(bool Success, string Error, byte[]? Bytes, string FileName)> GetPdfAsync(int id)
    {
        var response = await _http.GetAsync($"api/tni/box/{id}/pdf");

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengunduh PDF." : error.Trim('"'), null, string.Empty);
        }

        var bytes = await response.Content.ReadAsByteArrayAsync();
        var name = response.Content.Headers.ContentDisposition?.FileNameStar
                   ?? response.Content.Headers.ContentDisposition?.FileName
                   ?? $"box-{id}.pdf";

        return (true, string.Empty, bytes, name.Trim('"'));
    }

    // paksa = sudah dikonfirmasi beda satuan/rawatan (jawaban KONFIRMASI sebelumnya)
    public async Task<TniScanHasilDto> MasukBoxAsync(string kode, int boxId, bool paksa = false)
    {
        var response = await _http.PostAsJsonAsync("api/tni/scan/masuk-box",
            new TniMasukBoxRequest { Kode = kode, BoxId = boxId, Paksa = paksa });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return new TniScanHasilDto
            {
                Hasil = "DITOLAK",
                Pesan = string.IsNullOrWhiteSpace(error) ? "Gagal menghubungi server." : error.Trim('"')
            };
        }

        return await response.Content.ReadFromJsonAsync<TniScanHasilDto>()
               ?? new TniScanHasilDto { Hasil = "DITOLAK", Pesan = "Jawaban server tidak terbaca." };
    }

    private static async Task<(bool Success, string Error)> Result(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return (true, string.Empty);

        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal memproses." : error.Trim('"'));
    }
}
