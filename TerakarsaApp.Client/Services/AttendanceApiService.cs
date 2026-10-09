using System.Net.Http.Json;
using TerakarsaApp.Shared.Attendance;

namespace TerakarsaApp.Client.Services;

// Prompt 70: halaman /attendance (module HR_ATTENDANCE) -- kartu karyawan, rekap absensi,
// koreksi anomali. Endpoint perangkat gate (api/gate/*) TIDAK dipanggil dari sini: itu punya
// aplikasi gate sendiri dengan header X-Gate-Api-Key.
public class AttendanceApiService
{
    private readonly HttpClient _http;

    public AttendanceApiService(HttpClient http)
    {
        _http = http;
    }

    // ---------- Kartu karyawan ----------

    public async Task<List<EmployeeCardDto>> GetCardsAsync(EmployeeCardListRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/cards/list", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<EmployeeCardDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CreateCardAsync(EmployeeCardCreateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/cards", request);
        return await ToResultAsync(response);
    }

    public async Task<(bool Success, string Error)> UpdateCardAsync(EmployeeCardUpdateRequest request)
    {
        var response = await _http.PutAsJsonAsync("api/attendance/cards", request);
        return await ToResultAsync(response);
    }

    // Jalur normal kartu hilang/diganti -- terpisah dari Hapus, riwayat tetap utuh.
    public async Task<(bool Success, string Error)> DeactivateCardAsync(EmployeeCardDeactivateRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/cards/deactivate", request);
        return await ToResultAsync(response);
    }

    // Hanya untuk salah input.
    public async Task<(bool Success, string Error)> DeleteCardAsync(int id)
    {
        var response = await _http.DeleteAsync($"api/attendance/cards/{id}");
        return await ToResultAsync(response);
    }

    // ---------- Rekap & koreksi ----------

    public async Task<List<AttendanceSessionDto>> GetReportAsync(AttendanceReportRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/report", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<AttendanceSessionDto>>() ?? new();
    }

    public async Task<List<AttendanceSessionDto>> GetAnomaliAsync(AttendanceAnomaliRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/anomali", request);
        if (!response.IsSuccessStatusCode) return new();
        return await response.Content.ReadFromJsonAsync<List<AttendanceSessionDto>>() ?? new();
    }

    public async Task<(bool Success, string Error)> CorrectAsync(AttendanceCorrectRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/correct", request);
        return await ToResultAsync(response);
    }

    public async Task<(bool Success, string Error)> CreateManualAsync(AttendanceManualRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/manual", request);
        return await ToResultAsync(response);
    }

    public async Task<(bool Success, string Error)> AckAsync(AttendanceAckRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/ack", request);
        return await ToResultAsync(response);
    }

    public async Task<(bool Success, string Error)> DeleteSessionAsync(AttendanceDeleteRequest request)
    {
        var response = await _http.PostAsJsonAsync("api/attendance/delete", request);
        return await ToResultAsync(response);
    }

    // Pesan RAISERROR dari SP (bahasa Indonesia) diteruskan API sebagai body 400 -- itu yang
    // ditampilkan, termasuk "Kartu xxx sudah aktif untuk <nama>".
    private static async Task<(bool Success, string Error)> ToResultAsync(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return (true, string.Empty);
        var error = await response.Content.ReadAsStringAsync();
        return (false, string.IsNullOrWhiteSpace(error) ? "Gagal menyimpan data." : error.Trim('"'));
    }
}
