using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 65: Perintah Kerja & cetak kartu personel PDH TNI AD.
public class TniPerintahKerjaApiService
{
    private readonly HttpClient _http;

    public TniPerintahKerjaApiService(HttpClient http)
    {
        _http = http;
    }

    public class RawatanResponse
    {
        public List<TniRawatanDto> Rawatan { get; set; } = new();
        public int StokBebasKemeja { get; set; }
        public int StokBebasCelana { get; set; }
    }

    public async Task<RawatanResponse> GetRawatanAsync()
    {
        var response = await _http.GetAsync("api/tni/perintah-kerja/rawatan");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<RawatanResponse>() ?? new();
    }

    public async Task<List<TniSatuanSaranDto>> GetSatuanAsync(int areaId)
    {
        var response = await _http.GetAsync($"api/tni/perintah-kerja/rawatan/{areaId}/satuan");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniSatuanSaranDto>>() ?? new();
    }

    public async Task<TniSatuanDetailDto?> GetSatuanDetailAsync(int satuanId)
    {
        var response = await _http.GetAsync($"api/tni/perintah-kerja/satuan/{satuanId}");
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniSatuanDetailDto>();
    }

    public async Task<List<TniDijatahDto>> GetDijatahAsync(int satuanId)
    {
        var response = await _http.GetAsync($"api/tni/perintah-kerja/satuan/{satuanId}/dijatah");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniDijatahDto>>() ?? new();
    }

    public async Task<(bool Success, string Error, TniCetakHasilDto? Hasil)> CetakAsync(List<int> personelIds)
    {
        var response = await _http.PostAsJsonAsync("api/tni/perintah-kerja/cetak",
            new TniCetakRequest { PersonelIds = personelIds });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal mengirim ke antrian cetak." : error.Trim('"'), null);
        }

        return (true, string.Empty, await response.Content.ReadFromJsonAsync<TniCetakHasilDto>());
    }

    public async Task<(bool Success, string Error, TniLepasHasilDto? Hasil)> LepasAsync(List<int> personelIds)
    {
        var response = await _http.PostAsJsonAsync("api/tni/perintah-kerja/lepas",
            new TniCetakRequest { PersonelIds = personelIds });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal melepas kartu." : error.Trim('"'), null);
        }

        return (true, string.Empty, await response.Content.ReadFromJsonAsync<TniLepasHasilDto>());
    }
}
