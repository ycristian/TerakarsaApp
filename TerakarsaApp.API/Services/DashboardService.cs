using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.API.Services;

// Kiosk (X-Dashboard-Token, tanpa JWT) -- murni read-only, tidak menulis apa pun ke
// tabel manapun selain TOUCH last_seen_at (di RequireDashboardTokenAttribute, terpisah
// dari service ini).
public class DashboardService
{
    private readonly AppDbContext _db;

    public DashboardService(AppDbContext db)
    {
        _db = db;
    }

    // SIS_Dashboard_TargetHarian mengembalikan 3 result set (header, divisi, resource) --
    // EF Core SqlQueryRaw hanya mendukung satu result set, jadi pakai SqlCommand mentah +
    // reader.NextResultAsync() (pola sama dengan WorkScheduleService.GetDefaultsAsync).
    public async Task<DashboardTargetHarianResult> GetTargetHarianAsync(DateTime planDate)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Dashboard_TargetHarian";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@PlanDate", planDate.Date));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new DashboardTargetHarianResult();

            if (await reader.ReadAsync())
            {
                result.Header = new DashboardHeaderDto
                {
                    PlanDate = reader.GetDateTime(reader.GetOrdinal("PlanDate")),
                    ServerTime = reader.GetDateTime(reader.GetOrdinal("ServerTime")),
                    TotalDivision = reader.GetInt32(reader.GetOrdinal("TotalDivision")),
                    PlannedDivision = reader.GetInt32(reader.GetOrdinal("PlannedDivision")),
                };
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Divisions.Add(new DashboardDivisionDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    DashboardMode = reader.GetString(reader.GetOrdinal("DashboardMode")),
                    HasPlan = reader.GetBoolean(reader.GetOrdinal("HasPlan")),
                    IsHoliday = reader.GetBoolean(reader.GetOrdinal("IsHoliday")),
                    HasTarget = reader.GetBoolean(reader.GetOrdinal("HasTarget")),
                    StartTime = GetNullableTimeSpan(reader, "StartTime"),
                    EndTime = GetNullableTimeSpan(reader, "EndTime"),
                    Headcount = GetNullableInt32(reader, "Headcount"),
                    TargetPerPerson = GetNullableInt32(reader, "TargetPerPerson"),
                    TargetTotal = GetNullableInt32(reader, "TargetTotal"),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                    Wip = reader.GetInt32(reader.GetOrdinal("Wip")),
                    WipBundles = reader.GetInt32(reader.GetOrdinal("WipBundles")),
                    Transit = reader.GetInt32(reader.GetOrdinal("Transit")),
                    EffectiveMinutesTotal = GetNullableInt32(reader, "EffectiveMinutesTotal"),
                    EffectiveMinutesElapsed = GetNullableInt32(reader, "EffectiveMinutesElapsed"),
                    ExpectedPercent = GetNullableDouble(reader, "ExpectedPercent"),
                    ActualPercent = GetNullableDouble(reader, "ActualPercent"),
                    DiffQty = GetNullableInt32(reader, "DiffQty"),
                    DiffPercent = GetNullableDouble(reader, "DiffPercent"),
                    RemainingQty = GetNullableInt32(reader, "RemainingQty"),
                    OutputPerPersonPerHour = GetNullableDouble(reader, "OutputPerPersonPerHour"),
                });
            }

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.Resources.Add(new DashboardResourceDto
                {
                    DivisionId = reader.GetInt32(reader.GetOrdinal("DivisionId")),
                    ResourceId = reader.GetInt32(reader.GetOrdinal("ResourceId")),
                    ResourceName = reader.GetString(reader.GetOrdinal("ResourceName")),
                    HasPlan = reader.GetBoolean(reader.GetOrdinal("HasPlan")),
                    IsHoliday = reader.GetBoolean(reader.GetOrdinal("IsHoliday")),
                    HasTarget = reader.GetBoolean(reader.GetOrdinal("HasTarget")),
                    HasTimeOverride = reader.GetBoolean(reader.GetOrdinal("HasTimeOverride")),
                    StartTime = GetNullableTimeSpan(reader, "StartTime"),
                    EndTime = GetNullableTimeSpan(reader, "EndTime"),
                    Headcount = GetNullableInt32(reader, "Headcount"),
                    TargetPerPerson = GetNullableInt32(reader, "TargetPerPerson"),
                    TargetTotal = GetNullableInt32(reader, "TargetTotal"),
                    QtyOk = reader.GetInt32(reader.GetOrdinal("QtyOk")),
                    QtyReject = reader.GetInt32(reader.GetOrdinal("QtyReject")),
                    Wip = reader.GetInt32(reader.GetOrdinal("Wip")),
                    WipBundles = reader.GetInt32(reader.GetOrdinal("WipBundles")),
                    EffectiveMinutesTotal = GetNullableInt32(reader, "EffectiveMinutesTotal"),
                    EffectiveMinutesElapsed = GetNullableInt32(reader, "EffectiveMinutesElapsed"),
                    ExpectedPercent = GetNullableDouble(reader, "ExpectedPercent"),
                    ActualPercent = GetNullableDouble(reader, "ActualPercent"),
                    DiffQty = GetNullableInt32(reader, "DiffQty"),
                    DiffPercent = GetNullableDouble(reader, "DiffPercent"),
                    RemainingQty = GetNullableInt32(reader, "RemainingQty"),
                    OutputPerPersonPerHour = GetNullableDouble(reader, "OutputPerPersonPerHour"),
                });
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // Prompt 45: modal drill-down per line -- SIS_Report_LineEmployeeProgress /
    // SIS_Report_LineActiveBundles masing-masing satu result set, pakai SqlQueryRaw (pola
    // sama dengan ReportWipService.GetBundlesAsync).
    // Prompt 51: resourceId opsional -- NULL diteruskan sbg DBNull ke SP (mode divisi).
    public async Task<List<LineEmployeeProgressDto>> GetLineEmployeeProgressAsync(int divisionId, int? resourceId, DateTime tanggal)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var tanggalParam = new SqlParameter("@Tanggal", tanggal.Date);

        return await _db.Database
            .SqlQueryRaw<LineEmployeeProgressDto>(
                "EXEC SIS_Report_LineEmployeeProgress @DivisionId = @DivisionId, @ResourceId = @ResourceId, @Tanggal = @Tanggal",
                divisionIdParam, resourceIdParam, tanggalParam)
            .ToListAsync();
    }

    public async Task<List<LineActiveBundleDto>> GetLineActiveBundlesAsync(int divisionId, int? resourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<LineActiveBundleDto>(
                "EXEC SIS_Report_LineActiveBundles @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();
    }

    // Prompt 52: tab "Transit" -- SIS_Report_LineTransitBundles, pola sama dengan
    // GetLineActiveBundlesAsync di atas.
    public async Task<List<LineTransitBundleDto>> GetLineTransitBundlesAsync(int divisionId, int? resourceId)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);

        return await _db.Database
            .SqlQueryRaw<LineTransitBundleDto>(
                "EXEC SIS_Report_LineTransitBundles @DivisionId = @DivisionId, @ResourceId = @ResourceId",
                divisionIdParam, resourceIdParam)
            .ToListAsync();
    }

    // Prompt 46: tab "Selesai" & "Reject" -- periode (hari/7hari/gajian) dikonversi ke rentang
    // [Dari, Sampai) DI SINI, bukan di client, supaya definisi periode gajian satu sumber.
    // Rumus periode gajian = salinan persis BuildPeriods() di ReportProduksi.razor (Prompt 30:
    // Sabtu 10:00 -> Sabtu berikutnya 10:00), hanya "now" diganti akhir hari dari @Tanggal
    // (tanggal aktif dashboard) supaya bisa dihitung untuk tanggal yang bukan hari ini.
    private static (DateTime Dari, DateTime Sampai) ResolveLineDetailPeriode(string? periode, DateTime tanggal)
    {
        var tgl = tanggal.Date;
        switch (periode)
        {
            case "7hari":
                return (tgl.AddDays(-6), tgl.AddDays(1));
            case "gajian":
                var refTime = tgl.AddHours(23).AddMinutes(59);
                var daysSinceSaturday = ((int)refTime.DayOfWeek - (int)DayOfWeek.Saturday + 7) % 7;
                var candidate = refTime.Date.AddDays(-daysSinceSaturday).AddHours(10);
                if (candidate > refTime) candidate = candidate.AddDays(-7);
                return (candidate, candidate.AddDays(7));
            default: // "hari"
                return (tgl, tgl.AddDays(1));
        }
    }

    public async Task<List<LineCompletedBundleDto>> GetLineCompletedBundlesAsync(int divisionId, int? resourceId, string? periode, DateTime tanggal)
    {
        var (dari, sampai) = ResolveLineDetailPeriode(periode, tanggal);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var dariParam = new SqlParameter("@DariTanggal", dari);
        var sampaiParam = new SqlParameter("@SampaiTanggal", sampai);

        return await _db.Database
            .SqlQueryRaw<LineCompletedBundleDto>(
                "EXEC SIS_Report_LineCompletedBundles @DivisionId = @DivisionId, @ResourceId = @ResourceId, @DariTanggal = @DariTanggal, @SampaiTanggal = @SampaiTanggal",
                divisionIdParam, resourceIdParam, dariParam, sampaiParam)
            .ToListAsync();
    }

    public async Task<List<LineRejectBundleDto>> GetLineRejectBundlesAsync(int divisionId, int? resourceId, string? periode, DateTime tanggal)
    {
        var (dari, sampai) = ResolveLineDetailPeriode(periode, tanggal);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var dariParam = new SqlParameter("@DariTanggal", dari);
        var sampaiParam = new SqlParameter("@SampaiTanggal", sampai);

        return await _db.Database
            .SqlQueryRaw<LineRejectBundleDto>(
                "EXEC SIS_Report_LineRejectBundles @DivisionId = @DivisionId, @ResourceId = @ResourceId, @DariTanggal = @DariTanggal, @SampaiTanggal = @SampaiTanggal",
                divisionIdParam, resourceIdParam, dariParam, sampaiParam)
            .ToListAsync();
    }

    // Prompt 51: tab "Tren" -- rentang "14hari" / "30hari" -> [Dari, Sampai] INCLUSIVE kedua
    // ujung, dihitung mundur dari tanggal aktif dashboard.
    private static (DateTime Dari, DateTime Sampai) ResolveTrendRentang(string? rentang, DateTime tanggal)
    {
        var days = rentang == "30hari" ? 30 : 14;
        var sampai = tanggal.Date;
        return (sampai.AddDays(-(days - 1)), sampai);
    }

    public async Task<List<LineTrendDailyDto>> GetLineTrendDailyAsync(int divisionId, int? resourceId, string? rentang, DateTime tanggal)
    {
        var (dari, sampai) = ResolveTrendRentang(rentang, tanggal);
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var dariParam = new SqlParameter("@DariTanggal", dari);
        var sampaiParam = new SqlParameter("@SampaiTanggal", sampai);

        return await _db.Database
            .SqlQueryRaw<LineTrendDailyDto>(
                "EXEC SIS_Report_LineTrendDaily @DivisionId = @DivisionId, @ResourceId = @ResourceId, @DariTanggal = @DariTanggal, @SampaiTanggal = @SampaiTanggal",
                divisionIdParam, resourceIdParam, dariParam, sampaiParam)
            .ToListAsync();
    }

    // Tabel rekap mingguan -- 10 periode gajian terakhir dihitung DI SP (bukan di sini), supaya
    // definisi periode gajian tetap satu sumber (lihat SIS_Report_LineTrendWeekly).
    public async Task<List<LineTrendWeeklyDto>> GetLineTrendWeeklyAsync(int divisionId, int? resourceId, DateTime tanggal)
    {
        var divisionIdParam = new SqlParameter("@DivisionId", divisionId);
        var resourceIdParam = new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value);
        var sampaiParam = new SqlParameter("@SampaiTanggal", tanggal.Date);

        return await _db.Database
            .SqlQueryRaw<LineTrendWeeklyDto>(
                "EXEC SIS_Report_LineTrendWeekly @DivisionId = @DivisionId, @ResourceId = @ResourceId, @SampaiTanggal = @SampaiTanggal",
                divisionIdParam, resourceIdParam, sampaiParam)
            .ToListAsync();
    }

    // Prompt 51: tab "Per Jam" -- SIS_Report_LineHourly mengembalikan 2 result set (jam, meta),
    // pola sama dengan GetTargetHarianAsync di atas.
    public async Task<LineHourlyResult> GetLineHourlyAsync(int divisionId, int? resourceId, DateTime tanggal)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Report_LineHourly";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@DivisionId", divisionId));
            cmd.Parameters.Add(new SqlParameter("@ResourceId", (object?)resourceId ?? DBNull.Value));
            cmd.Parameters.Add(new SqlParameter("@Tanggal", tanggal.Date));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new LineHourlyResult();

            while (await reader.ReadAsync())
            {
                result.Hours.Add(new LineHourlyDto
                {
                    Jam = reader.GetInt32(reader.GetOrdinal("Jam")),
                    IsIstirahat = reader.GetBoolean(reader.GetOrdinal("IsIstirahat")),
                    QtyTerima = GetNullableInt32(reader, "QtyTerima"),
                    QtyOk = GetNullableInt32(reader, "QtyOk"),
                });
            }

            await reader.NextResultAsync();
            if (await reader.ReadAsync())
            {
                result.Meta = new LineHourlyMetaDto
                {
                    JamMasuk = GetNullableTimeSpan(reader, "JamMasuk"),
                    TargetPulang = GetNullableTimeSpan(reader, "TargetPulang"),
                    TargetHarian = GetNullableInt32(reader, "TargetHarian"),
                    TargetPerJam = GetNullableDouble(reader, "TargetPerJam"),
                };
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    private static int? GetNullableInt32(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetInt32(ordinal);
    }

    private static double? GetNullableDouble(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetDouble(ordinal);
    }

    private static TimeSpan? GetNullableTimeSpan(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetTimeSpan(ordinal);
    }
}
