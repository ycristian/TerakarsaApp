using ClosedXML.Excel;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Services;

// Prompt 59: tab "Rekap Produksi" di perangkat stasiun + output non-PO.
// JANGAN tertukar dengan RekapProduksiService (Prompt 42) -- itu rekap STRUK (blok Settlement
// di dasar tab ini); yang ini matriks output per periode gajian.
//
// SIS_Station_RekapProduksi mengembalikan 4 result set, jadi dibaca dengan SqlCommand mentah
// + reader.NextResultAsync() (pola sama dengan StationAttendanceService.GetRecapAsync).
public class StationRekapProduksiService
{
    private readonly AppDbContext _db;

    public StationRekapProduksiService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<RekapProduksiResultDto> GetAsync(int resourceId, int payrollPeriodId, string mode)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SIS_Station_RekapProduksi";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@ResourceId", resourceId));
            cmd.Parameters.Add(new SqlParameter("@PayrollPeriodId", payrollPeriodId));
            cmd.Parameters.Add(new SqlParameter("@Mode", mode));

            using var reader = await cmd.ExecuteReaderAsync();

            var result = new RekapProduksiResultDto();

            while (await reader.ReadAsync())
            {
                result.Rows.Add(new RekapProduksiRowDto
                {
                    ArticleWorkflowId = reader.GetInt32(reader.GetOrdinal("ArticleWorkflowId")),
                    ArticleId = reader.GetInt32(reader.GetOrdinal("ArticleId")),
                    ArticleName = reader.GetString(reader.GetOrdinal("ArticleName")),
                    Style = GetNullableString(reader, "Style"),
                    Color = GetNullableString(reader, "Color"),
                    StepName = reader.GetString(reader.GetOrdinal("StepName")),
                    ProjectName = reader.GetString(reader.GetOrdinal("ProjectName")),
                    NoPo = GetNullableString(reader, "NoPo"),
                    Tanggal = reader.GetDateTime(reader.GetOrdinal("Tanggal")),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    UnitPrice = reader.GetDecimal(reader.GetOrdinal("UnitPrice")),
                });
            }

            await reader.NextResultAsync();
            if (await reader.ReadAsync())
                result.UnlockedCount = reader.GetInt32(reader.GetOrdinal("UnlockedCount"));

            await reader.NextResultAsync();
            while (await reader.ReadAsync())
            {
                result.NonPoDays.Add(new RekapProduksiNonPoDayDto
                {
                    Tanggal = reader.GetDateTime(reader.GetOrdinal("Tanggal")),
                    Qty = reader.GetInt32(reader.GetOrdinal("Qty")),
                    Nilai = reader.GetDecimal(reader.GetOrdinal("Nilai")),
                });
            }

            await reader.NextResultAsync();
            if (await reader.ReadAsync())
            {
                result.Period = new RekapProduksiPeriodDto
                {
                    PayrollPeriodId = reader.GetInt32(reader.GetOrdinal("PayrollPeriodId")),
                    PeriodCode = reader.GetString(reader.GetOrdinal("PeriodCode")),
                    PeriodStart = reader.GetDateTime(reader.GetOrdinal("PeriodStart")),
                    PeriodEnd = reader.GetDateTime(reader.GetOrdinal("PeriodEnd")),
                    IsFinalized = reader.GetBoolean(reader.GetOrdinal("IsFinalized")),
                    ResourceId = reader.GetInt32(reader.GetOrdinal("ResourceId")),
                    ResourceName = reader.GetString(reader.GetOrdinal("ResourceName")),
                    DivisionName = reader.GetString(reader.GetOrdinal("DivisionName")),
                    Mode = reader.GetString(reader.GetOrdinal("Mode")),
                };
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    public async Task<List<NonPoOutputDto>> GetNonPoAsync(int resourceId, int payrollPeriodId)
    {
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var periodIdParam = new SqlParameter("@PayrollPeriodId", payrollPeriodId);

        return await _db.Database
            .SqlQueryRaw<NonPoOutputDto>(
                "EXEC SIS_NonPoOutput_List @ResourceId = @ResourceId, @PayrollPeriodId = @PayrollPeriodId",
                resourceIdParam, periodIdParam)
            .ToListAsync();
    }

    public async Task<(bool Success, string Error)> CreateNonPoAsync(NonPoOutputSaveRequest request, int resourceId, int userId) =>
        await ManageNonPoAsync("CREATE", null, request, resourceId, userId);

    public async Task<(bool Success, string Error)> UpdateNonPoAsync(int nonPoOutputId, NonPoOutputSaveRequest request, int resourceId, int userId) =>
        await ManageNonPoAsync("UPDATE", nonPoOutputId, request, resourceId, userId);

    public async Task<(bool Success, string Error)> DeleteNonPoAsync(int nonPoOutputId, int resourceId, int userId) =>
        await ManageNonPoAsync("DELETE", nonPoOutputId, null, resourceId, userId);

    // Periode gajian TIDAK dikirim dari sini -- SP yang menghitungnya dari OutputAt
    // (dbo.SIS_fn_PayrollPeriodIdAt), supaya aturan cut-off Sabtu 10:00 hanya punya satu
    // definisi. Pesan error SP diteruskan apa adanya ke client (ditampilkan di modal).
    private async Task<(bool Success, string Error)> ManageNonPoAsync(
        string action, int? nonPoOutputId, NonPoOutputSaveRequest? request, int resourceId, int userId)
    {
        var actionParam = new SqlParameter("@Action", action);
        var idParam = new SqlParameter("@NonPoOutputId", (object?)nonPoOutputId ?? DBNull.Value);
        var resourceIdParam = new SqlParameter("@ResourceId", resourceId);
        var outputAtParam = new SqlParameter("@OutputAt", (object?)request?.OutputAt ?? DBNull.Value);
        var qtyParam = new SqlParameter("@Qty", (object?)request?.Qty ?? DBNull.Value);
        var unitPriceParam = new SqlParameter("@UnitPrice", (object?)request?.UnitPrice ?? DBNull.Value);
        var remarkParam = new SqlParameter("@Remark", (object?)request?.Remark ?? DBNull.Value);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_NonPoOutput_Manage @Action = @Action, @NonPoOutputId = @NonPoOutputId, @ResourceId = @ResourceId, @OutputAt = @OutputAt, @Qty = @Qty, @UnitPrice = @UnitPrice, @Remark = @Remark, @UserId = @UserId",
                actionParam, idParam, resourceIdParam, outputAtParam, qtyParam, unitPriceParam, remarkParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // ===== Export Excel =====
    // Isinya sama dengan matriks di layar, DENGAN SATU PENGECUALIAN yang disengaja: kolom
    // Harga & Nilai SELALU ikut, tidak tergantung checkbox Price di layar (file ini dipakai
    // untuk hitung upah, jadi harga tidak boleh hilang karena lupa mencentang).
    // Urutan kolom: Artikel | Step | PO | kolom tanggal | Total Qty | Harga | Nilai.
    public async Task<(byte[] Content, string FileName)> ExportAsync(int resourceId, int payrollPeriodId, string mode)
    {
        var data = await GetAsync(resourceId, payrollPeriodId, mode);
        var isOutput = string.Equals(data.Period?.Mode ?? mode, "OUTPUT", StringComparison.OrdinalIgnoreCase);

        var periodStartDate = data.Period?.PeriodStart.Date ?? DateTime.Today;
        var periodEndDate = data.Period?.PeriodEnd.Date ?? DateTime.Today;

        // Kolom tanggal: seluruh rentang periode (Sabtu..Sabtu, inklusif kedua ujungnya --
        // periode mulai & berakhir jam 10:00 sehingga hari Sabtu di kedua ujung terpakai
        // separuh), DITAMBAH tanggal di luar rentang yang muncul di data (hanya mungkin di
        // mode Output -- lihat sp_Station_RekapProduksi.sql), diurutkan menurut tanggal.
        var dates = new SortedSet<DateTime>();
        for (var d = periodStartDate; d <= periodEndDate; d = d.AddDays(1))
            dates.Add(d);
        foreach (var r in data.Rows) dates.Add(r.Tanggal.Date);
        foreach (var np in data.NonPoDays) dates.Add(np.Tanggal.Date);

        var dateList = dates.ToList();

        // Satu baris matriks = satu step artikel; qty-nya disebar ke kolom tanggal.
        var matrix = data.Rows
            .GroupBy(r => r.ArticleWorkflowId)
            .Select(g => new
            {
                First = g.First(),
                PerDate = g.GroupBy(x => x.Tanggal.Date).ToDictionary(x => x.Key, x => x.Sum(v => v.Qty)),
                Total = g.Sum(x => x.Qty),
            })
            .OrderBy(x => x.First.ArticleName)
            .ThenBy(x => x.First.StepName)
            .ToList();

        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Report");

        var lastCol = 3 + dateList.Count + 3;   // Artikel|Step|PO + tanggal + Total Qty|Harga|Nilai

        // ----- Header di atas tabel -----
        ws.Cell(1, 1).Value = "REPORT PRODUKSI";
        ws.Cell(1, 1).Style.Font.Bold = true;
        ws.Cell(1, 1).Style.Font.FontSize = 14;
        ws.Cell(2, 1).Value = "Line";
        ws.Cell(2, 2).Value = data.Period?.ResourceName ?? "-";
        ws.Cell(3, 1).Value = "Divisi";
        ws.Cell(3, 2).Value = data.Period?.DivisionName ?? "-";
        ws.Cell(4, 1).Value = "Periode";
        ws.Cell(4, 2).Value = data.Period is null
            ? "-"
            : $"{data.Period.PeriodCode} ({FormatRange(data.Period.PeriodStart, data.Period.PeriodEnd)})";
        ws.Cell(5, 1).Value = "Mode";
        ws.Cell(5, 2).Value = isOutput ? "Output" : "Terima";
        for (var r = 2; r <= 5; r++) ws.Cell(r, 1).Style.Font.Bold = true;

        // ----- Baris header tabel -----
        const int headerRow = 7;
        ws.Cell(headerRow, 1).Value = "Artikel";
        ws.Cell(headerRow, 2).Value = "Step";
        ws.Cell(headerRow, 3).Value = "PO";
        for (var i = 0; i < dateList.Count; i++)
        {
            var date = dateList[i];
            var outside = date < periodStartDate || date > periodEndDate;
            var cell = ws.Cell(headerRow, 4 + i);
            cell.Value = FormatDateHeader(date, periodStartDate, periodEndDate, outside);
            if (outside) cell.Style.Fill.BackgroundColor = XLColor.FromHtml("#FFF1D6");
        }
        ws.Cell(headerRow, lastCol - 2).Value = "Total Qty";
        ws.Cell(headerRow, lastCol - 1).Value = "Harga";
        ws.Cell(headerRow, lastCol).Value = "Nilai";

        var headerRange = ws.Range(headerRow, 1, headerRow, lastCol);
        headerRange.Style.Font.Bold = true;
        headerRange.Style.Alignment.WrapText = true;
        headerRange.Style.Border.BottomBorder = XLBorderStyleValues.Thin;

        // ----- Baris data -----
        var row = headerRow + 1;
        var firstDataRow = row;

        foreach (var item in matrix)
        {
            ws.Cell(row, 1).Value = item.First.ArticleName;
            ws.Cell(row, 2).Value = item.First.StepName;
            ws.Cell(row, 3).Value = item.First.NoPo ?? string.Empty;

            for (var i = 0; i < dateList.Count; i++)
            {
                if (item.PerDate.TryGetValue(dateList[i], out var qty) && qty != 0)
                    ws.Cell(row, 4 + i).Value = qty;
            }

            // Total Qty & Nilai sebagai FORMULA, bukan angka mati -- supaya pembaca Excel
            // bisa menyunting/menyaring kolom tanggal dan totalnya ikut benar.
            var firstDateCol = ws.Cell(row, 4).Address.ColumnLetter;
            var lastDateCol = ws.Cell(row, 3 + dateList.Count).Address.ColumnLetter;
            ws.Cell(row, lastCol - 2).FormulaA1 = $"SUM({firstDateCol}{row}:{lastDateCol}{row})";
            ws.Cell(row, lastCol - 1).Value = item.First.UnitPrice;
            ws.Cell(row, lastCol).FormulaA1 =
                $"{ws.Cell(row, lastCol - 2).Address.ColumnLetter}{row}*{ws.Cell(row, lastCol - 1).Address.ColumnLetter}{row}";

            row++;
        }

        var lastDataRow = row - 1;

        // ----- Baris Total PO (dasar upah) -----
        var totalRow = row;
        ws.Cell(totalRow, 1).Value = "Total PO";
        ws.Cell(totalRow, 2).Value = "dasar upah";
        if (matrix.Count > 0)
        {
            for (var c = 4; c <= lastCol; c++)
            {
                if (c == lastCol - 1) continue;   // kolom Harga tidak dijumlahkan
                var col = ws.Cell(totalRow, c).Address.ColumnLetter;
                ws.Cell(totalRow, c).FormulaA1 = $"SUM({col}{firstDataRow}:{col}{lastDataRow})";
            }
        }
        var totalRange = ws.Range(totalRow, 1, totalRow, lastCol);
        totalRange.Style.Font.Bold = true;
        totalRange.Style.Fill.BackgroundColor = XLColor.FromHtml("#F2F6FC");
        totalRange.Style.Border.TopBorder = XLBorderStyleValues.Thin;
        row++;

        // ----- Baris "Di luar PO" (mode Output saja), paling bawah -----
        if (isOutput)
        {
            var nonPoRow = row;
            ws.Cell(nonPoRow, 1).Value = "Di luar PO";
            ws.Cell(nonPoRow, 2).Value = "masuk upah, harga diisi PIC";

            var nonPoByDate = data.NonPoDays.GroupBy(x => x.Tanggal.Date)
                .ToDictionary(x => x.Key, x => (Qty: x.Sum(v => v.Qty), Nilai: x.Sum(v => v.Nilai)));

            for (var i = 0; i < dateList.Count; i++)
            {
                if (nonPoByDate.TryGetValue(dateList[i], out var v) && v.Qty != 0)
                    ws.Cell(nonPoRow, 4 + i).Value = v.Qty;
            }

            var firstDateCol = ws.Cell(nonPoRow, 4).Address.ColumnLetter;
            var lastDateCol = ws.Cell(nonPoRow, 3 + dateList.Count).Address.ColumnLetter;
            ws.Cell(nonPoRow, lastCol - 2).FormulaA1 = $"SUM({firstDateCol}{nonPoRow}:{lastDateCol}{nonPoRow})";
            // Harga dikosongkan: tiap catatan non-PO punya harganya sendiri, tidak ada satu
            // harga yang mewakili barisnya. Nilai = jumlah nilai semua catatan.
            ws.Cell(nonPoRow, lastCol).Value = data.NonPoDays.Sum(x => x.Nilai);

            ws.Range(nonPoRow, 1, nonPoRow, lastCol).Style.Fill.BackgroundColor = XLColor.FromHtml("#F6F8FB");
            row++;
        }

        // ----- Format angka & lebar kolom -----
        var lastRow = row - 1;
        ws.Range(headerRow + 1, 4, lastRow, lastCol - 2).Style.NumberFormat.Format = "#,##0";
        ws.Range(headerRow + 1, lastCol - 1, lastRow, lastCol).Style.NumberFormat.Format = "#,##0.##";
        ws.Column(1).Width = 28;
        ws.Column(2).Width = 18;
        ws.Column(3).Width = 18;
        for (var i = 0; i < dateList.Count; i++) ws.Column(4 + i).Width = 11;
        ws.Column(lastCol - 2).Width = 11;
        ws.Column(lastCol - 1).Width = 12;
        ws.Column(lastCol).Width = 15;
        ws.SheetView.FreezeRows(headerRow);
        ws.SheetView.FreezeColumns(3);

        using var ms = new MemoryStream();
        wb.SaveAs(ms);

        var fileName = $"Report_{Sanitize(data.Period?.ResourceName ?? "Line")}_{Sanitize(data.Period?.PeriodCode ?? "periode")}_{(isOutput ? "Output" : "Terima")}.xlsx";
        return (ms.ToArray(), fileName);
    }

    // "Sab 26 Sep 10:00 - Sab 3 Okt 10:00" -- sama dengan label pemilih periode di layar.
    private static string FormatRange(DateTime start, DateTime end) =>
        $"{FormatIndo(start)} - {FormatIndo(end)}";

    private static readonly string[] DayNames = { "Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab" };
    private static readonly string[] MonthNames = { "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des" };

    private static string FormatIndo(DateTime value) =>
        $"{DayNames[(int)value.DayOfWeek]} {value.Day} {MonthNames[value.Month - 1]} {value:HH:mm}";

    // Sabtu pertama/terakhir diberi catatan jam cut-off, persis seperti header di layar.
    private static string FormatDateHeader(DateTime date, DateTime periodStart, DateTime periodEnd, bool outside)
    {
        var label = $"{DayNames[(int)date.DayOfWeek]} {date.Day}/{date.Month}";
        if (outside) return label + "\nluar periode";
        if (date == periodStart) return label + "\nmulai 10:00";
        if (date == periodEnd) return label + "\ns/d 10:00";
        return label;
    }

    private static string Sanitize(string value)
    {
        var cleaned = new string(value.Select(c => char.IsLetterOrDigit(c) ? c : '-').ToArray());
        return cleaned.Trim('-');
    }

    private static string? GetNullableString(SqlDataReader reader, string column)
    {
        var ordinal = reader.GetOrdinal(column);
        return reader.IsDBNull(ordinal) ? null : reader.GetString(ordinal);
    }
}
