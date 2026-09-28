using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.API.Services;

// ApiKey dicocokkan oleh RequirePrintApiKeyAttribute terhadap header X-Print-Api-Key
// yang dikirim TerakarsaApp.PrintService (Windows Worker Service).
public class PrintServiceOptions
{
    public string ApiKey { get; set; } = string.Empty;

    // Ad hoc (lanjutan Prompt 48): setting per-INSTANCE API (appsettings.json/.Development.json),
    // BUKAN disimpan di DB -- sengaja begitu supaya instance API yang dijalankan lokal (mis.
    // `dotnet run`, appsettings.Development.json men-set ini true) bisa dites terhadap DB yang
    // SAMA dengan instance produksi tanpa pernah mempengaruhi instance produksi itu (kalau
    // disimpan di tabel app_settings, DB akan jadi shared state -- nyalakan dryrun utk testing
    // lokal juga akan membuat instance produksi ikut dryrun). true = SEMUA request
    // claim/report/render yang masuk ke instance API ini dilayani dari print_jobs_dryrun,
    // terlepas dari flag DryRun yang dikirim client (worker) -- di-OR-kan (lihat pemakaian di
    // bawah), jadi salah satu pihak minta dryrun sudah cukup memicu dryrun.
    public bool DryRun { get; set; }
}

public class PrintJobService
{
    private readonly AppDbContext _db;
    private readonly PrintServiceOptions _options;

    public PrintJobService(AppDbContext db, IOptions<PrintServiceOptions> options)
    {
        _db = db;
        _options = options.Value;
    }

    // Ad hoc (lanjutan Prompt 48): DryRun=true -> SIS_PrintJobDryRun_Claim (print_jobs_dryrun),
    // supaya testing tidak pernah mengklaim/mengunci baris di antrian print_jobs live. Dua
    // literal EXEC terpisah (bukan nama SP diinterpolasi) supaya tidak ada string dinamis sama
    // sekali yang masuk ke teks SQL. dryRun efektif = setting instance API (_options.DryRun)
    // ATAU flag dari client -- lihat PrintServiceOptions.DryRun.
    public async Task<List<PrintJobClaimedDto>> ClaimAsync(int batchSize, List<string> jobTypes, bool dryRun)
    {
        var effectiveDryRun = _options.DryRun || dryRun;
        var batchSizeParam = new SqlParameter("@BatchSize", batchSize);
        var jobTypesCsvParam = new SqlParameter("@JobTypesCsv", (object?)(jobTypes.Count > 0 ? string.Join(',', jobTypes) : null) ?? DBNull.Value);
        var sql = effectiveDryRun
            ? "EXEC SIS_PrintJobDryRun_Claim @BatchSize = @BatchSize, @JobTypesCsv = @JobTypesCsv"
            : "EXEC SIS_PrintJob_Claim @BatchSize = @BatchSize, @JobTypesCsv = @JobTypesCsv";

        return await _db.Database
            .SqlQueryRaw<PrintJobClaimedDto>(sql, batchSizeParam, jobTypesCsvParam)
            .ToListAsync();
    }

    // Ad hoc (lanjutan Prompt 48): DryRun=true -> SIS_PrintJobDryRun_Report (print_jobs_dryrun).
    public async Task ReportAsync(PrintJobReportRequest request)
    {
        var effectiveDryRun = _options.DryRun || request.DryRun;
        var idParam = new SqlParameter("@PrintJobId", request.PrintJobId);
        var successParam = new SqlParameter("@Success", request.Success);
        var errorMessageParam = new SqlParameter("@ErrorMessage", (object?)request.ErrorMessage ?? DBNull.Value);
        var sql = effectiveDryRun
            ? "EXEC SIS_PrintJobDryRun_Report @PrintJobId = @PrintJobId, @Success = @Success, @ErrorMessage = @ErrorMessage"
            : "EXEC SIS_PrintJob_Report @PrintJobId = @PrintJobId, @Success = @Success, @ErrorMessage = @ErrorMessage";

        await _db.Database.ExecuteSqlRawAsync(sql, idParam, successParam, errorMessageParam);
    }

    // Prompt 48: render isi cetakan (job_type render_mode = TOKEN) lewat SIS_Print_Dispatch --
    // SAAT job diklaim, bukan saat dibuat. Error dari SP (route salah pasang, job_type belum
    // punya SP render, dst) diteruskan sebagai pesan asli, sama pola dengan service lain
    // (lihat BundleService) supaya controller cukup BadRequest(error). @DryRun diteruskan apa
    // adanya ke SIS_Print_Dispatch (baca dari print_jobs_dryrun kalau true, ad hoc lanjutan
    // Prompt 48) -- effectiveDryRun sama seperti Claim/Report.
    public async Task<(bool Success, string Error, string? TokenText)> RenderAsync(int printJobId, bool dryRun)
    {
        var effectiveDryRun = _options.DryRun || dryRun;
        var idParam = new SqlParameter("@PrintJobId", printJobId);
        var dryRunParam = new SqlParameter("@DryRun", effectiveDryRun);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<PrintRenderResultRow>(
                    "EXEC SIS_Print_Dispatch @PrintJobId = @PrintJobId, @DryRun = @DryRun",
                    idParam, dryRunParam)
                .ToListAsync();

            var tokenText = result.FirstOrDefault()?.TokenText;
            return (true, string.Empty, tokenText);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    private class PrintRenderResultRow
    {
        public string? TokenText { get; set; }
    }

    // Ad hoc (2026-09-01): daftar job_type "kupon" (thermal, render_mode TOKEN) yang boleh
    // diklaim -- dipindah dari array hardcode Worker.cs KuponJobTypes ke tabel
    // print_kupon_job_types (lihat sql/adhoc_print_kupon_job_types.sql) supaya job_type struk
    // BARU tidak butuh update/republish/restart TerakarsaApp.PrintService. Dipanggil worker
    // SETIAP siklus poll (bukan sekali di startup) lewat GET api/print/kupon-job-types --
    // baris baru langsung kepakai tanpa restart.
    public async Task<List<string>> GetKuponJobTypesAsync()
    {
        return await _db.Database
            .SqlQueryRaw<string>("SELECT job_type AS Value FROM print_kupon_job_types WHERE deleted_at IS NULL")
            .ToListAsync();
    }
}
