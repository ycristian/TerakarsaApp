using ClosedXML.Excel;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.API.Services;

// Prompt 75: laporan module Stok Benang -- riwayat movement, ringkasan landing,
// matriks lokasi, pemakaian per project, dan export Excel.
//
// SEMUA READ-ONLY. Tidak ada SP tulis yang dipanggil dari sini.
public class ThreadReportService
{
    private const int MaxExportRows = 10_000;

    private readonly AppDbContext _db;

    public ThreadReportService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ThreadMovementListResult> GetMovementsAsync(
        DateTime? dari, DateTime? sampai, string? movementTypes, string? reasonCode,
        int? itemId, int? locationId, int? resourceId, int? projectId, int? createdBy,
        int pageNumber, int pageSize)
    {
        var items = await QueryMovementsAsync(dari, sampai, movementTypes, reasonCode,
            itemId, locationId, resourceId, projectId, createdBy, pageNumber, pageSize);

        return new ThreadMovementListResult
        {
            Items = items,
            TotalCount = items.FirstOrDefault()?.TotalCount ?? 0
        };
    }

    private Task<List<ThreadMovementRowDto>> QueryMovementsAsync(
        DateTime? dari, DateTime? sampai, string? movementTypes, string? reasonCode,
        int? itemId, int? locationId, int? resourceId, int? projectId, int? createdBy,
        int pageNumber, int pageSize) =>
        _db.Database.SqlQueryRaw<ThreadMovementRowDto>(
                @"EXEC inv.SIS_ThreadMovement_List @Dari = @Dari, @Sampai = @Sampai,
                    @MovementTypes = @MovementTypes, @ReasonCode = @ReasonCode,
                    @ItemId = @ItemId, @LocationId = @LocationId, @ResourceId = @ResourceId,
                    @ProjectId = @ProjectId, @CreatedBy = @CreatedBy,
                    @PageNumber = @PageNumber, @PageSize = @PageSize",
                new SqlParameter("@Dari", dari ?? (object)DBNull.Value),
                new SqlParameter("@Sampai", sampai ?? (object)DBNull.Value),
                new SqlParameter("@MovementTypes", string.IsNullOrWhiteSpace(movementTypes) ? DBNull.Value : movementTypes),
                new SqlParameter("@ReasonCode", string.IsNullOrWhiteSpace(reasonCode) ? DBNull.Value : reasonCode),
                new SqlParameter("@ItemId", itemId ?? (object)DBNull.Value),
                new SqlParameter("@LocationId", locationId ?? (object)DBNull.Value),
                new SqlParameter("@ResourceId", resourceId ?? (object)DBNull.Value),
                new SqlParameter("@ProjectId", projectId ?? (object)DBNull.Value),
                new SqlParameter("@CreatedBy", createdBy ?? (object)DBNull.Value),
                new SqlParameter("@PageNumber", pageNumber),
                new SqlParameter("@PageSize", pageSize))
            .ToListAsync();

    public async Task<ThreadSummaryDto> GetSummaryAsync()
    {
        var total = (await _db.Database
            .SqlQueryRaw<ThreadStockTotalDto>("EXEC inv.SIS_ThreadStock_Summary @Bagian = 'TOTAL'")
            .ToListAsync()).FirstOrDefault() ?? new ThreadStockTotalDto();

        var hariIni = await _db.Database
            .SqlQueryRaw<ThreadTodayDto>("EXEC inv.SIS_ThreadStock_Summary @Bagian = 'HARIINI'")
            .ToListAsync();

        var perhatian = await _db.Database
            .SqlQueryRaw<ThreadLowStockDto>("EXEC inv.SIS_ThreadStock_Summary @Bagian = 'PERHATIAN'")
            .ToListAsync();

        return new ThreadSummaryDto { Total = total, HariIni = hariIni, Perhatian = perhatian };
    }

    public Task<List<ThreadLocationStockDto>> GetByLocationAsync() =>
        _db.Database.SqlQueryRaw<ThreadLocationStockDto>("EXEC inv.SIS_ThreadStock_ByLocation").ToListAsync();

    public Task<List<ThreadUsageDto>> GetUsageByProjectAsync(int? projectId, DateTime? dari, DateTime? sampai) =>
        _db.Database.SqlQueryRaw<ThreadUsageDto>(
                "EXEC inv.SIS_ThreadUsage_ByProject @ProjectId = @ProjectId, @Dari = @Dari, @Sampai = @Sampai",
                new SqlParameter("@ProjectId", projectId ?? (object)DBNull.Value),
                new SqlParameter("@Dari", dari ?? (object)DBNull.Value),
                new SqlParameter("@Sampai", sampai ?? (object)DBNull.Value))
            .ToListAsync();

    // ==================== EXPORT ====================

    // Kolom sama dengan daftar riwayat, tanpa paging, maksimal 10.000 baris.
    public async Task<byte[]> ExportMovementsAsync(
        DateTime? dari, DateTime? sampai, string? movementTypes, string? reasonCode,
        int? itemId, int? locationId, int? resourceId, int? projectId, int? createdBy)
    {
        var rows = await QueryMovementsAsync(dari, sampai, movementTypes, reasonCode,
            itemId, locationId, resourceId, projectId, createdBy, 1, MaxExportRows);

        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Riwayat Benang");

        ws.Cell(1, 1).Value = "Riwayat Stok Benang";
        ws.Cell(1, 1).Style.Font.Bold = true;
        ws.Cell(1, 1).Style.Font.FontSize = 14;

        var periode = $"{(dari?.ToString("dd/MM/yyyy") ?? "7 hari terakhir")}"
                      + (sampai.HasValue ? $" s/d {sampai.Value:dd/MM/yyyy}" : string.Empty);
        ws.Cell(2, 1).Value = $"Periode: {periode}";

        var header = new[]
        {
            "Tanggal", "Jenis", "SKU", "Warna", "Kode warna", "Merk", "Jenis benang",
            "Kode kones", "Dari", "Ke", "Kones", "Gram", "Line", "Project", "No PO",
            "Alasan", "Keterangan", "Pencatat", "Sesi opname"
        };

        const int headerRow = 4;
        for (var c = 0; c < header.Length; c++)
        {
            ws.Cell(headerRow, c + 1).Value = header[c];
            ws.Cell(headerRow, c + 1).Style.Font.Bold = true;
        }

        var r = headerRow + 1;
        foreach (var m in rows)
        {
            ws.Cell(r, 1).Value = m.CreatedAt;
            ws.Cell(r, 1).Style.DateFormat.Format = "dd/MM/yyyy HH:mm";
            ws.Cell(r, 2).Value = m.TypeLabel;
            ws.Cell(r, 3).Value = m.SkuCode;
            ws.Cell(r, 4).Value = m.ColorName;
            ws.Cell(r, 5).Value = m.ColorCode;
            ws.Cell(r, 6).Value = m.BrandName;
            ws.Cell(r, 7).Value = m.TypeName;
            ws.Cell(r, 8).Value = m.ConeCode ?? string.Empty;
            ws.Cell(r, 9).Value = m.FromCode ?? string.Empty;
            ws.Cell(r, 10).Value = m.ToCode ?? string.Empty;
            if (m.QtyWhole.HasValue) ws.Cell(r, 11).Value = m.QtyWhole.Value;
            if (m.WeightGram.HasValue) ws.Cell(r, 12).Value = m.WeightGram.Value;
            ws.Cell(r, 13).Value = m.ResourceName ?? string.Empty;
            ws.Cell(r, 14).Value = m.ProjectName ?? string.Empty;
            ws.Cell(r, 15).Value = m.NoPo ?? string.Empty;
            ws.Cell(r, 16).Value = m.ReasonName ?? m.ReasonCode ?? string.Empty;
            ws.Cell(r, 17).Value = m.Note ?? string.Empty;
            ws.Cell(r, 18).Value = m.CreatedByName ?? string.Empty;
            ws.Cell(r, 19).Value = m.OpnameSessionNo ?? string.Empty;
            r++;
        }

        ws.Columns().AdjustToContents();

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }

    public async Task<byte[]> ExportUsageAsync(int? projectId, DateTime? dari, DateTime? sampai)
    {
        var rows = await GetUsageByProjectAsync(projectId, dari, sampai);

        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Pemakaian Benang");

        ws.Cell(1, 1).Value = "Pemakaian Benang per Project";
        ws.Cell(1, 1).Style.Font.Bold = true;
        ws.Cell(1, 1).Style.Font.FontSize = 14;

        var periode = $"{(dari?.ToString("dd/MM/yyyy") ?? "30 hari terakhir")}"
                      + (sampai.HasValue ? $" s/d {sampai.Value:dd/MM/yyyy}" : string.Empty);
        ws.Cell(2, 1).Value = $"Periode: {periode}";

        var header = new[]
        {
            "Project", "No PO", "SKU", "Warna", "Kode warna", "Merk", "Jenis benang",
            "Kones whole diambil", "Gram split diambil", "Gram split kembali", "Gram split netto"
        };

        const int headerRow = 4;
        for (var c = 0; c < header.Length; c++)
        {
            ws.Cell(headerRow, c + 1).Value = header[c];
            ws.Cell(headerRow, c + 1).Style.Font.Bold = true;
        }

        var r = headerRow + 1;
        foreach (var u in rows)
        {
            ws.Cell(r, 1).Value = u.ProjectName ?? string.Empty;
            ws.Cell(r, 2).Value = u.NoPo ?? string.Empty;
            ws.Cell(r, 3).Value = u.SkuCode;
            ws.Cell(r, 4).Value = u.ColorName;
            ws.Cell(r, 5).Value = u.ColorCode;
            ws.Cell(r, 6).Value = u.BrandName;
            ws.Cell(r, 7).Value = u.TypeName;
            ws.Cell(r, 8).Value = u.WholeIssued;
            ws.Cell(r, 9).Value = u.SplitGramIssued;
            ws.Cell(r, 10).Value = u.SplitGramReturned;
            ws.Cell(r, 11).Value = u.SplitGramNet;
            r++;
        }

        ws.Columns().AdjustToContents();

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }
}
