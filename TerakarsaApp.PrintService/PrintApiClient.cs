using System.Net.Http.Json;
using System.Text.Json;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.PrintService;

public class PrintApiClient
{
    private readonly HttpClient _http;

    public PrintApiClient(HttpClient http)
    {
        _http = http;
    }

    // Ad hoc (2026-09-01): daftar job_type "kupon" (thermal, render_mode TOKEN) yang boleh
    // diklaim -- dipindah dari array hardcode Worker.cs KuponJobTypes ke tabel
    // print_kupon_job_types (API). Dipanggil SETIAP siklus poll (bukan cache startup) supaya
    // job_type struk baru langsung kepakai tanpa restart service.
    public async Task<List<string>> GetKuponJobTypesAsync(CancellationToken ct)
    {
        var response = await _http.GetAsync("api/print/kupon-job-types", ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<List<string>>(cancellationToken: ct) ?? new();
    }

    // dryRun sama dengan PrintWorkerOptions.DryRun (ad hoc lanjutan Prompt 48) -- kalau true,
    // API mengklaim dari print_jobs_dryrun (SIS_PrintJobDryRun_Claim), bukan antrian live.
    public async Task<List<PrintJobClaimedDto>> ClaimAsync(int batchSize, List<string> jobTypes, bool dryRun, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/print/claim", new PrintJobClaimRequest { BatchSize = batchSize, JobTypes = jobTypes, DryRun = dryRun }, ct);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<List<PrintJobClaimedDto>>(cancellationToken: ct) ?? new();
    }

    // dryRun WAJIB sama dengan yang dipakai saat ClaimAsync job ini (lihat PrintJobReportRequest.DryRun).
    public async Task ReportAsync(int printJobId, bool success, string? errorMessage, bool dryRun, CancellationToken ct)
    {
        var response = await _http.PostAsJsonAsync("api/print/report", new PrintJobReportRequest
        {
            PrintJobId = printJobId,
            Success = success,
            ErrorMessage = errorMessage,
            DryRun = dryRun
        }, ct);
        response.EnsureSuccessStatusCode();
    }

    // Prompt 48: render isi cetakan (job_type render_mode = TOKEN) SAAT job diklaim lewat
    // GET api/print/render/{id} (SIS_Print_Dispatch). Error dari SP (route salah pasang, job
    // type belum punya SP render, dst) dikembalikan API sebagai 400 + pesan asli -- diteruskan
    // sebagai exception supaya dilaporkan lewat api/print/report sama seperti kegagalan cetak.
    // dryRun WAJIB sama dengan ClaimAsync job ini.
    public async Task<string> RenderAsync(int printJobId, bool dryRun, CancellationToken ct)
    {
        var response = await _http.GetAsync($"api/print/render/{printJobId}?dryRun={(dryRun ? "true" : "false")}", ct);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(ct);
            throw new InvalidOperationException(ExtractErrorMessage(body));
        }

        var result = await response.Content.ReadFromJsonAsync<PrintRenderResponse>(cancellationToken: ct);
        return result?.TokenText ?? string.Empty;
    }

    private static string ExtractErrorMessage(string body)
    {
        if (string.IsNullOrWhiteSpace(body)) return "Gagal render (tanpa pesan).";
        try
        {
            var parsed = JsonSerializer.Deserialize<string>(body);
            if (!string.IsNullOrWhiteSpace(parsed)) return parsed;
        }
        catch (JsonException)
        {
            // body bukan JSON string biasa (mis. HTML error page) -- pakai apa adanya di bawah.
        }
        return body;
    }
}
