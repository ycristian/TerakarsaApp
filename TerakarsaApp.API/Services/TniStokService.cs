using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 64: stok kemeja & celana PDH TNI AD.
// Service tidak menghitung saldo apa pun -- semua angka dari tni.v_stok_pola
// lewat SP. TERPAKAI & BONGKAR tidak punya method di sini: keduanya hanya lahir
// otomatis dari scan Set Jadi (Prompt 66) dan persetujuan pembatalan (Prompt 68).
public class TniStokService
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly AppDbContext _db;

    public TniStokService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<TniStokSaldoDto>> GetSaldoAsync(
        int orderId, string jenisItem, string? search, bool hanyaAda)
    {
        return await _db.Database
            .SqlQueryRaw<TniStokSaldoDto>(
                "EXEC tni.SIS_Stok_Saldo @OrderId = @OrderId, @JenisItem = @JenisItem, @Search = @Search, @HanyaAda = @HanyaAda",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@JenisItem", jenisItem),
                new SqlParameter("@Search", string.IsNullOrWhiteSpace(search) ? DBNull.Value : search),
                new SqlParameter("@HanyaAda", hanyaAda))
            .ToListAsync();
    }

    public async Task<TniStokRiwayatResult> GetRiwayatAsync(
        int orderId, string? jenisItem, int? polaId, string? jenisMutasi,
        DateTime? dari, DateTime? sampai, int pageNumber, int pageSize, bool hanyaManual = false)
    {
        var items = await _db.Database
            .SqlQueryRaw<TniStokMutasiDto>(
                @"EXEC tni.SIS_Stok_Riwayat @OrderId = @OrderId, @JenisItem = @JenisItem,
                    @PolaId = @PolaId, @JenisMutasi = @JenisMutasi, @Dari = @Dari,
                    @Sampai = @Sampai, @PageNumber = @PageNumber, @PageSize = @PageSize,
                    @HanyaManual = @HanyaManual",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@JenisItem", string.IsNullOrWhiteSpace(jenisItem) ? DBNull.Value : jenisItem),
                new SqlParameter("@PolaId", polaId ?? (object)DBNull.Value),
                new SqlParameter("@JenisMutasi", string.IsNullOrWhiteSpace(jenisMutasi) ? DBNull.Value : jenisMutasi),
                new SqlParameter("@Dari", dari ?? (object)DBNull.Value),
                new SqlParameter("@Sampai", sampai ?? (object)DBNull.Value),
                new SqlParameter("@PageNumber", pageNumber),
                new SqlParameter("@PageSize", pageSize),
                new SqlParameter("@HanyaManual", hanyaManual))
            .ToListAsync();

        return new TniStokRiwayatResult
        {
            Items = items,
            TotalCount = items.FirstOrDefault()?.TotalCount ?? 0
        };
    }

    public async Task<(bool Success, string Error, TniStokSetoranHasilDto? Hasil)> SetoranAsync(
        int orderId, TniStokSetoranRequest request, int userId, int? perangkatId = null)
    {
        var json = JsonSerializer.Serialize(request.Items, JsonOpts);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniStokSetoranHasilDto>(
                    @"EXEC tni.SIS_Stok_Manage @Action = 'SETORAN', @OrderId = @OrderId, @Tanggal = @Tanggal,
                        @Items = @Items, @Supplier = @Supplier, @UserId = @UserId, @PerangkatId = @PerangkatId",
                    new SqlParameter("@OrderId", orderId),
                    new SqlParameter("@Tanggal", request.Tanggal.HasValue
                        ? request.Tanggal.Value.Date : (object)DBNull.Value),
                    new SqlParameter("@Items", json),
                    new SqlParameter("@Supplier", string.IsNullOrWhiteSpace(request.Supplier)
                        ? DBNull.Value : request.Supplier.Trim()),
                    new SqlParameter("@UserId", userId),
                    new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // Tab Riwayat (2026-10-07): setoran per header + RUSAK/KOREKSI, paging per entri.
    public async Task<TniStokRiwayatManualResult> GetRiwayatManualAsync(
        int orderId, string? jenisMutasi, int pageNumber, int pageSize)
    {
        var items = await _db.Database
            .SqlQueryRaw<TniStokRiwayatManualRow>(
                @"EXEC tni.SIS_Stok_RiwayatManual @OrderId = @OrderId, @JenisMutasi = @JenisMutasi,
                    @PageNumber = @PageNumber, @PageSize = @PageSize",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@JenisMutasi", string.IsNullOrWhiteSpace(jenisMutasi) ? DBNull.Value : jenisMutasi),
                new SqlParameter("@PageNumber", pageNumber),
                new SqlParameter("@PageSize", pageSize))
            .ToListAsync();

        return new TniStokRiwayatManualResult
        {
            Items = items,
            TotalEntri = items.FirstOrDefault()?.TotalEntri ?? 0
        };
    }

    // Edit master (tanggal, supplier) + isi LENGKAP satu setoran.
    public async Task<(bool Success, string Error)> EditSetoranAsync(
        int orderId, int setoranId, TniStokSetoranRequest request, int userId, int? perangkatId = null)
    {
        var json = JsonSerializer.Serialize(request.Items, JsonOpts);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Stok_Manage @Action = 'SETORAN_EDIT', @OrderId = @OrderId,
                    @SetoranId = @SetoranId, @Tanggal = @Tanggal, @Supplier = @Supplier,
                    @Items = @Items, @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@SetoranId", setoranId),
                new SqlParameter("@Tanggal", request.Tanggal.HasValue
                    ? request.Tanggal.Value.Date : (object)DBNull.Value),
                new SqlParameter("@Supplier", string.IsNullOrWhiteSpace(request.Supplier)
                    ? DBNull.Value : request.Supplier.Trim()),
                new SqlParameter("@Items", json),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Hapus (soft) satu setoran beserta seluruh isinya.
    public async Task<(bool Success, string Error)> HapusSetoranAsync(int orderId, int setoranId, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Stok_Manage @Action = 'SETORAN_HAPUS', @OrderId = @OrderId,
                    @SetoranId = @SetoranId, @UserId = @UserId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@SetoranId", setoranId),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Hapus (soft) mutasi MANUAL -- SP menolak TERPAKAI & BONGKAR.
    public async Task<(bool Success, string Error)> HapusAsync(int orderId, int mutasiId, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Stok_Manage @Action = 'DELETE', @OrderId = @OrderId,
                    @MutasiId = @MutasiId, @UserId = @UserId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@MutasiId", mutasiId),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // 2026-10-07 (alter_77): satu pengeluaran banyak pola. keluarId null = baru
    // (KELUAR), terisi = edit master + isi lengkap (KELUAR_EDIT).
    public async Task<(bool Success, string Error)> KeluarAsync(
        int orderId, TniStokKeluarRequest request, int userId, int? perangkatId = null, int? keluarId = null)
    {
        var json = JsonSerializer.Serialize(request.Items, JsonOpts);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Stok_Manage @Action = @Action, @OrderId = @OrderId, @KeluarId = @KeluarId,
                    @Tanggal = @Tanggal, @JenisMutasi = @JenisMutasi, @Arah = @Arah, @Items = @Items,
                    @Alasan = @Alasan, @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Action", keluarId.HasValue ? "KELUAR_EDIT" : "KELUAR"),
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@KeluarId", keluarId ?? (object)DBNull.Value),
                new SqlParameter("@Tanggal", request.Tanggal.HasValue
                    ? request.Tanggal.Value.Date : (object)DBNull.Value),
                new SqlParameter("@JenisMutasi", request.JenisMutasi ?? string.Empty),
                new SqlParameter("@Arah", request.Arah),
                new SqlParameter("@Items", json),
                new SqlParameter("@Alasan", (object?)request.Alasan ?? DBNull.Value),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // Hapus (soft) satu pengeluaran beserta seluruh isinya.
    public async Task<(bool Success, string Error)> HapusKeluarAsync(int orderId, int keluarId, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Stok_Manage @Action = 'KELUAR_HAPUS', @OrderId = @OrderId,
                    @KeluarId = @KeluarId, @UserId = @UserId",
                new SqlParameter("@OrderId", orderId),
                new SqlParameter("@KeluarId", keluarId),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}
