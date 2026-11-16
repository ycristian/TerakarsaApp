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

    // Filter size prioritas perangkat (pola_id -> qty di dekat, null = semua stok bebas)
    // -> "?kemeja=12:20,15&celana=3:10" (kosong bila tidak ada).
    private static string SizeQuery(IReadOnlyDictionary<int, int?>? kemeja, IReadOnlyDictionary<int, int?>? celana)
    {
        static string Csv(IReadOnlyDictionary<int, int?> d) =>
            string.Join(",", d.Select(x => x.Value is int q ? $"{x.Key}:{q}" : x.Key.ToString()));

        var q = new List<string>();
        if (kemeja?.Count > 0) q.Add("kemeja=" + Csv(kemeja));
        if (celana?.Count > 0) q.Add("celana=" + Csv(celana));
        return q.Count == 0 ? string.Empty : "?" + string.Join("&", q);
    }

    public async Task<RawatanResponse> GetRawatanAsync(IReadOnlyDictionary<int, int?>? kemeja = null, IReadOnlyDictionary<int, int?>? celana = null)
    {
        var response = await _http.GetAsync("api/tni/perintah-kerja/rawatan" + SizeQuery(kemeja, celana));
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<RawatanResponse>() ?? new();
    }

    public async Task<List<TniSatuanSaranDto>> GetSatuanAsync(int areaId, IReadOnlyDictionary<int, int?>? kemeja = null, IReadOnlyDictionary<int, int?>? celana = null)
    {
        var response = await _http.GetAsync($"api/tni/perintah-kerja/rawatan/{areaId}/satuan" + SizeQuery(kemeja, celana));
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniSatuanSaranDto>>() ?? new();
    }

    public async Task<TniSatuanDetailDto?> GetSatuanDetailAsync(int satuanId, IReadOnlyDictionary<int, int?>? kemeja = null, IReadOnlyDictionary<int, int?>? celana = null)
    {
        var response = await _http.GetAsync($"api/tni/perintah-kerja/satuan/{satuanId}" + SizeQuery(kemeja, celana));
        if (!response.IsSuccessStatusCode) return null;
        return await response.Content.ReadFromJsonAsync<TniSatuanDetailDto>();
    }

    // Kekurangan gabungan beberapa satuan (kebutuhan dijumlah dulu, baru dikurangi stok bebas sekali).
    public async Task<List<TniKekuranganDto>> GetKekuranganGabunganAsync(int areaId, IEnumerable<int> satuanIds)
    {
        var response = await _http.GetAsync(
            $"api/tni/perintah-kerja/rawatan/{areaId}/kekurangan?satuanIds={string.Join(",", satuanIds)}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniKekuranganDto>>() ?? new();
    }

    public async Task<List<TniDijatahDto>> GetDijatahAsync(int satuanId)
    {
        var response = await _http.GetAsync($"api/tni/perintah-kerja/satuan/{satuanId}/dijatah");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniDijatahDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> SetPrioritasAsync(int satuanId, bool prioritas)
    {
        var response = await _http.PostAsJsonAsync($"api/tni/perintah-kerja/satuan/{satuanId}/prioritas",
            new TniSatuanPrioritasRequest { Prioritas = prioritas });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan prioritas." : error.Trim('"'));
        }

        return (true, string.Empty);
    }

    public async Task<(bool Success, string Error)> SetKunciStokAsync(int satuanId, bool kunci)
    {
        var response = await _http.PostAsJsonAsync($"api/tni/perintah-kerja/satuan/{satuanId}/kunci-stok",
            new TniSatuanKunciStokRequest { Kunci = kunci });

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();
            return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan kunci stok." : error.Trim('"'));
        }

        return (true, string.Empty);
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
