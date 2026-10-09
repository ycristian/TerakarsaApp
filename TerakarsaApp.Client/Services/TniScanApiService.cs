using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 66: scan "Set Jadi" + ambil data personel lewat qr_token (user login).
// Varian publiknya (tanpa login) ada di TniPublicApiService.
public class TniScanApiService
{
    private readonly HttpClient _http;

    public TniScanApiService(HttpClient http)
    {
        _http = http;
    }

    public async Task<TniScanHasilDto> SetJadiAsync(string kode)
    {
        var response = await _http.PostAsJsonAsync("api/tni/scan/set-jadi", new TniScanRequest { Kode = kode });

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

    // Pop up konfirmasi Set Jadi. Ok=false + Detail=null -> kode tidak dikenal;
    // Ok=false + Error -> gagal menghubungi server.
    public async Task<(bool Ok, TniPersonelDetailDto? Detail, string Error)> LookupAsync(string kode)
    {
        var response = await _http.PostAsJsonAsync("api/tni/scan/lookup", new TniScanRequest { Kode = kode });

        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            return (false, null, string.Empty);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, null, string.IsNullOrWhiteSpace(error) ? "Gagal menghubungi server." : error.Trim('"'));
        }

        return (true, await response.Content.ReadFromJsonAsync<TniPersonelDetailDto>(), string.Empty);
    }

    // Daftar komplain satu personel -- perangkat terdaftar saja (berisi no telp).
    public async Task<List<TniKomplainDto>> GetKomplainAsync(int personelId)
    {
        var response = await _http.GetAsync($"api/tni/komplain/personel/{personelId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniKomplainDto>>() ?? new();
    }

    public async Task<TniPersonelDetailDto?> GetByTokenAsync(string token)
    {
        var response = await _http.GetAsync($"api/tni/personel/by-token/{Uri.EscapeDataString(token)}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniPersonelDetailDto>();
    }
}
