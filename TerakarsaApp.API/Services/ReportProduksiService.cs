using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Reports;
using TerakarsaApp.Shared.Resources;

namespace TerakarsaApp.API.Services;

// Prompt 30: Laporan Produksi Periode Gajian -- murni read-only (SIS_Report_Produksi* di
// sql/sp_Report_Produksi.sql), tidak menulis apa pun ke database.
public class ReportProduksiService
{
    private readonly AppDbContext _db;

    public ReportProduksiService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<ProduksiReportResultDto> GetReportAsync(int divisionId, int? resourceId, DateTime periodStart, DateTime periodEnd)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var periodStartParam = new SqlParameter("@PeriodStart", periodStart);
        var periodEndParam = new SqlParameter("@PeriodEnd", periodEnd);

        var agg = await _db.Database
            .SqlQueryRaw<ProduksiAggRowDto>(
                "EXEC SIS_Report_ProduksiAgg @DivisionId = @DivisionId, @ResourceId = @ResourceId, @PeriodStart = @PeriodStart, @PeriodEnd = @PeriodEnd",
                divisionIdParam, resourceIdParam, periodStartParam, periodEndParam)
            .ToListAsync();

        var detailDivisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var detailResourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var detailPeriodStartParam = new SqlParameter("@PeriodStart", periodStart);
        var detailPeriodEndParam = new SqlParameter("@PeriodEnd", periodEnd);

        var detail = await _db.Database
            .SqlQueryRaw<ProduksiDetailRowDto>(
                "EXEC SIS_Report_ProduksiDetail @DivisionId = @DivisionId, @ResourceId = @ResourceId, @PeriodStart = @PeriodStart, @PeriodEnd = @PeriodEnd",
                detailDivisionIdParam, detailResourceIdParam, detailPeriodStartParam, detailPeriodEndParam)
            .ToListAsync();

        var summary = new ProduksiSummaryDto
        {
            QtyDone = agg.Sum(a => a.QtyDone),
            QtyMenungguQc = agg.Sum(a => a.QtyMenungguQc),
            QtyWip = agg.Sum(a => a.QtyWip),
            QtyReject = agg.Sum(a => a.QtyReject),
            PelaksanaAktif = detail.Where(d => d.QtyDone > 0).Select(d => d.PelaksanaName).Distinct().Count()
        };

        return new ProduksiReportResultDto { Summary = summary, Agg = agg, Detail = detail };
    }

    public async Task<List<ResourceLookupDto>> GetResourcesAsync(int divisionId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);

        return await _db.Database
            .SqlQueryRaw<ResourceLookupDto>(
                "EXEC SIS_Report_ProduksiResources @DivisionId = @DivisionId",
                divisionIdParam)
            .ToListAsync();
    }
}
