using System.Net;
using System.Net.Http.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.Mobile.Services;

// Prompt 77: klien antrian cetak untuk app Android.
//
// Memakai endpoint yang SAMA dengan PrintService Windows (api/print/claim & report),
// tapi autentikasinya header X-Print-Device-Token (satu token per HP) -- bukan
// X-Print-Api-Key. Server (SIS_PrintJob_Claim @DeviceId) yang memastikan HP ini hanya
// mendapat job yang route-nya mengarah ke device ini.
public class PrintQueueClient
{
    public const string TokenHeader = "X-Print-Device-Token";
    public const string InfoHeader = "X-Print-Device-Info";

    private readonly ServerResolver _resolver;

    public PrintQueueClient(ServerResolver resolver)
    {
        _resolver = resolver;
    }

    // true = token ditolak server (device dihapus/di-nonaktifkan/di-daftar ulang di HP lain).
    public bool TokenDitolak { get; private set; }

    public async Task<List<PrintJobClaimedDto>> ClaimAsync(string token, int batchSize = 3)
    {
        try
        {
            using var http = BuatAsync(token);

            // JobTypes dikirim KOSONG: dengan @DeviceId, route di server sudah membatasi
            // job mana yang boleh diambil HP ini -- jadi job_type baru tidak perlu update app.
            var response = await http.PostAsJsonAsync("api/print/claim", new PrintJobClaimRequest
            {
                BatchSize = batchSize,
                JobTypes = new List<string>(),
                DryRun = false,
                DeviceInfo = Info()
            });

            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                TokenDitolak = true;
                return new();
            }

            if (!response.IsSuccessStatusCode) return new();

            TokenDitolak = false;
            return await response.Content.ReadFromJsonAsync<List<PrintJobClaimedDto>>() ?? new();
        }
        catch (Exception ex)
        {
            PrintLog.Tulis($"Gagal ambil antrian: {ex.Message}");
            return new();
        }
    }

    public async Task<bool> ReportAsync(string token, int printJobId, bool success, string? error)
    {
        try
        {
            using var http = BuatAsync(token);

            var response = await http.PostAsJsonAsync("api/print/report", new PrintJobReportRequest
            {
                PrintJobId = printJobId,
                Success = success,
                ErrorMessage = error,
                DryRun = false
            });

            if (response.StatusCode == HttpStatusCode.Unauthorized) TokenDitolak = true;

            return response.IsSuccessStatusCode;
        }
        catch (Exception ex)
        {
            PrintLog.Tulis($"Gagal lapor job #{printJobId}: {ex.Message}");
            return false;
        }
    }

    private HttpClient BuatAsync(string token)
    {
        var http = ServerResolver.BuatHttpClientAktif(_resolver);
        http.Timeout = TimeSpan.FromSeconds(20);
        http.DefaultRequestHeaders.Add(TokenHeader, token);
        http.DefaultRequestHeaders.Add(InfoHeader, Info());
        return http;
    }

    private static string Info()
    {
        var printer = string.IsNullOrWhiteSpace(PrintPrefs.PrinterName) ? "tanpa printer" : PrintPrefs.PrinterName;
        return $"{printer} · app {AppInfo.Current.VersionString}";
    }
}
