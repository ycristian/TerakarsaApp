using ClosedXML.Excel;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 69: dashboard progres & kebutuhan size PDH TNI AD.
//
// Service ini TIDAK menghitung status maupun saldo -- semuanya sudah diturunkan
// di tni.v_personel / tni.v_stok_pola oleh kedua SP dashboard.
public class TniDashboardService
{
    private readonly AppDbContext _db;

    public TniDashboardService(AppDbContext db)
    {
        _db = db;
    }

    // SIS_Dashboard_Progres mengembalikan 2 result set -- EF Core SqlQueryRaw hanya
    // membaca yang pertama, jadi pakai SqlCommand mentah + reader.NextResultAsync()
    // (pola sama dengan TniBoxService.GetByIdAsync).
    public async Task<TniDashboardProgresDto> GetProgresAsync(int orderId)
    {
        var conn = (SqlConnection)_db.Database.GetDbConnection();
        var wasClosed = conn.State != System.Data.ConnectionState.Open;
        if (wasClosed) await conn.OpenAsync();

        try
        {
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "tni.SIS_Dashboard_Progres";
            cmd.CommandType = System.Data.CommandType.StoredProcedure;
            cmd.Parameters.Add(new SqlParameter("@OrderId", orderId));

            var result = new TniDashboardProgresDto();
            using var reader = await cmd.ExecuteReaderAsync();

            // (1) per rawatan
            while (await reader.ReadAsync())
            {
                var row = new TniProgresAreaDto { Kota = Str(reader, "Kota") };
                Isi(reader, row);
                result.Area.Add(row);
            }

            // (2) per satuan
            if (await reader.NextResultAsync())
            {
                while (await reader.ReadAsync())
                {
                    var row = new TniProgresSatuanDto
                    {
                        SatuanId = reader.GetInt32(reader.GetOrdinal("SatuanId")),
                        SatuanCode = reader.GetString(reader.GetOrdinal("SatuanCode")),
                        SatuanName = reader.GetString(reader.GetOrdinal("SatuanName"))
                    };
                    Isi(reader, row);
                    result.Satuan.Add(row);
                }
            }

            return result;
        }
        finally
        {
            if (wasClosed) await conn.CloseAsync();
        }
    }

    // Kolom progres yang sama untuk baris area maupun satuan.
    private static void Isi(SqlDataReader r, TniProgresRowDto row)
    {
        row.AreaId = r.GetInt32(r.GetOrdinal("AreaId"));
        row.AreaCode = r.GetString(r.GetOrdinal("AreaCode"));
        row.AreaName = r.GetString(r.GetOrdinal("AreaName"));
        row.Total = r.GetInt32(r.GetOrdinal("Total"));
        row.BelumCetak = r.GetInt32(r.GetOrdinal("BelumCetak"));
        row.Dicetak = r.GetInt32(r.GetOrdinal("Dicetak"));
        row.SetJadi = r.GetInt32(r.GetOrdinal("SetJadi"));
        row.MasukBox = r.GetInt32(r.GetOrdinal("MasukBox"));
        row.Terkirim = r.GetInt32(r.GetOrdinal("Terkirim"));
        row.PersenBox = r.GetDecimal(r.GetOrdinal("PersenBox"));
        row.PersenKirim = r.GetDecimal(r.GetOrdinal("PersenKirim"));
        row.BoxTerbuka = r.GetInt32(r.GetOrdinal("BoxTerbuka"));
        row.BoxTertutup = r.GetInt32(r.GetOrdinal("BoxTertutup"));
        row.BoxTerkirim = r.GetInt32(r.GetOrdinal("BoxTerkirim"));
    }

    private static string? Str(SqlDataReader r, string col)
    {
        var i = r.GetOrdinal(col);
        return r.IsDBNull(i) ? null : r.GetString(i);
    }

    public async Task<List<TniKebutuhanSizeDto>> GetKebutuhanSizeAsync(
        int orderId, int? areaId, string jenisItem, int? satuanId = null)
    {
        return await _db.Database
            .SqlQueryRaw<TniKebutuhanSizeDto>(
                @"EXEC tni.SIS_Dashboard_KebutuhanSize @OrderId = @OrderId,
                    @AreaId = @AreaId, @SatuanId = @SatuanId, @JenisItem = @JenisItem",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@AreaId", areaId ?? (object)DBNull.Value),
                new SqlParameter("@SatuanId", satuanId ?? (object)DBNull.Value),
                new SqlParameter("@JenisItem", jenisItem))
            .ToListAsync();
    }

    // ---------------- export Excel ----------------

    // Satu sheet per jenis (Kemeja & Celana) supaya satu file bisa langsung
    // diteruskan ke lantai produksi.
    public async Task<byte[]> ExportKebutuhanSizeAsync(
        int orderId, int? areaId, string areaLabel, string orderLabel, int? satuanId = null)
    {
        var kemeja = await GetKebutuhanSizeAsync(orderId, areaId, "KEMEJA", satuanId);
        var celana = await GetKebutuhanSizeAsync(orderId, areaId, "CELANA", satuanId);

        using var wb = new XLWorkbook();
        Sheet(wb, "Kemeja", kemeja, areaLabel, orderLabel);
        Sheet(wb, "Celana", celana, areaLabel, orderLabel);

        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        return ms.ToArray();
    }

    private static void Sheet(
        XLWorkbook wb, string nama, List<TniKebutuhanSizeDto> rows,
        string areaLabel, string orderLabel)
    {
        var ws = wb.Worksheets.Add(nama);

        ws.Cell(1, 1).Value = $"Kebutuhan Size {nama} — {orderLabel}";
        ws.Cell(1, 1).Style.Font.Bold = true;
        ws.Cell(1, 1).Style.Font.FontSize = 14;

        ws.Cell(2, 1).Value = $"Rawatan: {areaLabel}";
        ws.Cell(3, 1).Value = $"Dicetak: {DateTime.Now:dd/MM/yyyy HH:mm}";
        // Keterangan WAJIB: stok tidak dibagi per area.
        ws.Cell(4, 1).Value = "Catatan: Butuh dihitung untuk rawatan/satuan di atas; "
                            + "Saldo & Stok bebas adalah stok GLOBAL (stok tidak dibagi per rawatan/satuan).";
        ws.Cell(2, 1).Style.Font.Bold = true;

        const int headerRow = 6;
        var header = new[] { "Pola", "Butuh", "Saldo", "Stok bebas", "Selisih" };
        for (var c = 0; c < header.Length; c++) ws.Cell(headerRow, c + 1).Value = header[c];

        var headerRange = ws.Range(headerRow, 1, headerRow, header.Length);
        headerRange.Style.Font.Bold = true;
        headerRange.Style.Fill.BackgroundColor = XLColor.FromHtml("#F2F6FC");
        headerRange.Style.Border.BottomBorder = XLBorderStyleValues.Thin;

        var r = headerRow;
        string? grup = null;
        foreach (var x in rows)
        {
            // 2026-10-07: baris terurut per grup gender dari SP -- beri judul grup.
            if (x.GrupGender != grup)
            {
                grup = x.GrupGender;
                r++;
                ws.Cell(r, 1).Value = $"_{grup} · {TniUrutStok.Label(grup)}";
                var grpRange = ws.Range(r, 1, r, header.Length);
                grpRange.Style.Font.Bold = true;
                grpRange.Style.Fill.BackgroundColor = XLColor.FromHtml("#E8EDF3");
            }

            r++;
            ws.Cell(r, 1).Value = x.Kode;
            ws.Cell(r, 2).Value = x.Butuh;
            ws.Cell(r, 3).Value = x.Saldo;
            ws.Cell(r, 4).Value = x.StokBebas;
            ws.Cell(r, 5).Value = x.Selisih;

            // Kekurangan ditandai supaya langsung terlihat di lantai produksi.
            if (x.Selisih < 0)
            {
                ws.Cell(r, 5).Style.Font.Bold = true;
                ws.Cell(r, 5).Style.Font.FontColor = XLColor.FromHtml("#B3261E");
            }
        }

        if (rows.Count > 0)
        {
            var totalRow = r + 1;
            ws.Cell(totalRow, 1).Value = "TOTAL";
            ws.Cell(totalRow, 2).Value = rows.Sum(x => x.Butuh);
            ws.Cell(totalRow, 3).Value = rows.Sum(x => x.Saldo);
            ws.Cell(totalRow, 4).Value = rows.Sum(x => x.StokBebas);
            ws.Cell(totalRow, 5).Value = rows.Sum(x => x.Kurang) * -1;   // total kekurangan

            var totalRange = ws.Range(totalRow, 1, totalRow, header.Length);
            totalRange.Style.Font.Bold = true;
            totalRange.Style.Fill.BackgroundColor = XLColor.FromHtml("#F2F6FC");
            totalRange.Style.Border.TopBorder = XLBorderStyleValues.Thin;

            ws.Range(headerRow + 1, 2, totalRow, header.Length).Style.NumberFormat.Format = "#,##0";
        }

        ws.Column(1).Width = 18;
        for (var c = 2; c <= header.Length; c++) ws.Column(c).Width = 12;
        ws.SheetView.FreezeRows(headerRow);
    }
}
