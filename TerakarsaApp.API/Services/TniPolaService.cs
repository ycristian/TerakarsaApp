using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 61: master pola PDH TNI AD (ukuran JADI pakaian, bukan ukuran badan).
// Satu set method untuk kedua jenis pola, dibedakan jenisItem (KEMEJA/CELANA).
// SELURUH validasi bisnis ada di tni.SIS_Pola_Manage -- service hanya meneruskan
// parameter dan menerjemahkan SqlException jadi pesan untuk UI.
public class TniPolaService
{
    private readonly AppDbContext _db;

    public TniPolaService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<List<TniPolaDto>> GetListAsync(string jenisItem, string? search, bool hanyaAktif)
    {
        var jenisParam = new SqlParameter("@JenisItem", jenisItem);
        var searchParam = new SqlParameter("@Search", string.IsNullOrWhiteSpace(search) ? DBNull.Value : search);
        var hanyaAktifParam = new SqlParameter("@HanyaAktif", hanyaAktif);

        return await _db.Database
            .SqlQueryRaw<TniPolaDto>(
                "EXEC tni.SIS_Pola_List @JenisItem = @JenisItem, @Search = @Search, @HanyaAktif = @HanyaAktif",
                jenisParam, searchParam, hanyaAktifParam)
            .ToListAsync();
    }

    public async Task<TniPolaDto?> GetByIdAsync(string jenisItem, int id)
    {
        var jenisParam = new SqlParameter("@JenisItem", jenisItem);
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<TniPolaDto>(
                "EXEC tni.SIS_Pola_GetById @JenisItem = @JenisItem, @Id = @Id",
                jenisParam, idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error)> SaveAsync(TniPolaSaveRequest request, int userId)
    {
        var action = request.PolaId.HasValue ? "UPDATE" : "CREATE";

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Pola_Manage
                    @Action = @Action, @JenisItem = @JenisItem, @Id = @Id,
                    @Kode = @Kode, @KodeAlt = @KodeAlt, @TargetGender = @TargetGender,
                    @LingkarDadaAcuan = @LingkarDadaAcuan, @SizeAngka = @SizeAngka,
                    @LingkarKerah = @LingkarKerah, @LebarBahu = @LebarBahu,
                    @LingkarDada = @LingkarDada, @LingkarPerut = @LingkarPerut,
                    @LingkarPinggul = @LingkarPinggul, @PanjangBaju = @PanjangBaju,
                    @LingkarLengan = @LingkarLengan, @LingkarKerungLengan = @LingkarKerungLengan,
                    @PanjangLengan = @PanjangLengan, @LingkarManset = @LingkarManset,
                    @LingkarPinggang = @LingkarPinggang, @LingkarSelangkang = @LingkarSelangkang,
                    @LingkarPaha = @LingkarPaha, @LingkarLutut = @LingkarLutut,
                    @LingkarKaki = @LingkarKaki, @PanjangCelana = @PanjangCelana,
                    @UserId = @UserId",
                new SqlParameter("@Action", action),
                new SqlParameter("@JenisItem", request.JenisItem),
                new SqlParameter("@Id", request.PolaId ?? (object)DBNull.Value),
                new SqlParameter("@Kode", request.Kode ?? string.Empty),
                new SqlParameter("@KodeAlt", (object?)request.KodeAlt ?? DBNull.Value),
                new SqlParameter("@TargetGender", request.TargetGender ?? string.Empty),
                Dec("@LingkarDadaAcuan", request.LingkarDadaAcuan),
                new SqlParameter("@SizeAngka", request.SizeAngka ?? (object)DBNull.Value),
                Dec("@LingkarKerah", request.LingkarKerah),
                Dec("@LebarBahu", request.LebarBahu),
                Dec("@LingkarDada", request.LingkarDada),
                Dec("@LingkarPerut", request.LingkarPerut),
                Dec("@LingkarPinggul", request.LingkarPinggul),
                Dec("@PanjangBaju", request.PanjangBaju),
                Dec("@LingkarLengan", request.LingkarLengan),
                Dec("@LingkarKerungLengan", request.LingkarKerungLengan),
                Dec("@PanjangLengan", request.PanjangLengan),
                Dec("@LingkarManset", request.LingkarManset),
                Dec("@LingkarPinggang", request.LingkarPinggang),
                Dec("@LingkarSelangkang", request.LingkarSelangkang),
                Dec("@LingkarPaha", request.LingkarPaha),
                Dec("@LingkarLutut", request.LingkarLutut),
                Dec("@LingkarKaki", request.LingkarKaki),
                Dec("@PanjangCelana", request.PanjangCelana),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> SetAktifAsync(string jenisItem, int id, bool isActive, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC tni.SIS_Pola_Manage @Action = @Action, @JenisItem = @JenisItem, @Id = @Id, @IsActive = @IsActive, @UserId = @UserId",
                new SqlParameter("@Action", "SET_AKTIF"),
                new SqlParameter("@JenisItem", jenisItem),
                new SqlParameter("@Id", id),
                new SqlParameter("@IsActive", isActive),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error)> DeleteAsync(string jenisItem, int id, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC tni.SIS_Pola_Manage @Action = @Action, @JenisItem = @JenisItem, @Id = @Id, @UserId = @UserId",
                new SqlParameter("@Action", "DELETE"),
                new SqlParameter("@JenisItem", jenisItem),
                new SqlParameter("@Id", id),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // decimal(5,1) harus dikirim eksplisit; kalau tidak, Decimal.Zero/serialisasi
    // default bisa membulatkan nilai seperti 38.5 jadi 38.
    private static SqlParameter Dec(string name, decimal? value) =>
        new(name, System.Data.SqlDbType.Decimal)
        {
            Precision = 5,
            Scale = 1,
            Value = value.HasValue ? value.Value : DBNull.Value
        };
}
