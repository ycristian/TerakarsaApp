using System.Net.Http.Json;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 68: pengajuan & persetujuan pembatalan scan PDH TNI AD.
//
// Endpoint putusan (list/setujui/tolak) butuh module TNI_PDH_APPROVE -- user
// tanpa module itu akan dapat 403, dan method di sini mengembalikan daftar
// kosong / Ok = false, bukan exception.
public class TniPembatalanApiService
{
    // _http  = client PERANGKAT (X-Tni-Token) -- untuk ajukan & riwayat personel.
    // _jwt   = client ber-JWT  -- HANYA untuk endpoint PUTUSAN, yang tetap
    //          mewajibkan login + module TNI_PDH_APPROVE.
    private readonly HttpClient _http;
    private readonly IHttpClientFactory _factory;

    public TniPembatalanApiService(HttpClient http, IHttpClientFactory factory)
    {
        _http = http;
        _factory = factory;
    }

    private HttpClient Jwt => _factory.CreateClient("API");

    public async Task<List<TniPembatalanDto>> GetListAsync(
        string? status = null, int pageNumber = 1, int pageSize = 30)
    {
        var q = new List<string> { $"pageNumber={pageNumber}", $"pageSize={pageSize}" };
        if (!string.IsNullOrWhiteSpace(status)) q.Add($"status={status}");

        var response = await Jwt.GetAsync("api/tni/pembatalan?" + string.Join("&", q));
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniPembatalanDto>>() ?? new();
    }

    public async Task<List<TniPembatalanDto>> GetByPersonelAsync(int personelId)
    {
        var response = await _http.GetAsync($"api/tni/pembatalan/personel/{personelId}");
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<TniPembatalanDto>>() ?? new();
    }

    public async Task<TniPembatalanAksiHasil> AjukanAsync(int personelId, string jenis, string alasan)
        => await Kirim("api/tni/pembatalan/ajukan",
            new TniPembatalanAjukanRequest { PersonelId = personelId, Jenis = jenis, Alasan = alasan });

    public async Task<TniPembatalanAksiHasil> SetujuiAsync(int id, string? catatan)
        => await KirimJwt($"api/tni/pembatalan/{id}/setujui",
            new TniPembatalanPutusanRequest { Catatan = catatan });

    public async Task<TniPembatalanAksiHasil> TolakAsync(int id, string catatan)
        => await KirimJwt($"api/tni/pembatalan/{id}/tolak",
            new TniPembatalanPutusanRequest { Catatan = catatan });

    private async Task<TniPembatalanAksiHasil> Kirim<T>(string url, T body)
        => await Kirim(_http, url, body);

    private async Task<TniPembatalanAksiHasil> KirimJwt<T>(string url, T body)
        => await Kirim(Jwt, url, body);

    private static async Task<TniPembatalanAksiHasil> Kirim<T>(HttpClient client, string url, T body)
    {
        var response = await client.PostAsJsonAsync(url, body);

        if (!response.IsSuccessStatusCode)
        {
            var error = await response.Content.ReadAsStringAsync();

            return new TniPembatalanAksiHasil
            {
                Ok = false,
                Pesan = response.StatusCode == System.Net.HttpStatusCode.Forbidden
                    ? "Anda tidak punya akses untuk memutus pembatalan."
                    : string.IsNullOrWhiteSpace(error) ? "Gagal memproses." : error.Trim('"')
            };
        }

        return await response.Content.ReadFromJsonAsync<TniPembatalanAksiHasil>()
               ?? new TniPembatalanAksiHasil { Ok = false, Pesan = "Jawaban server tidak terbaca." };
    }
}
