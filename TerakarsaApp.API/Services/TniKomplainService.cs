using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Komplain ukuran PDH TNI AD dari halaman QR /t/{token} (2026-10-06).
// Validasi (no telp & komentar wajib) ditegakkan di tni.SIS_Komplain_Manage.
public class TniKomplainService
{
    private readonly AppDbContext _db;

    public TniKomplainService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<(bool Success, string Error)> CreateAsync(
        string token, TniKomplainRequest request, int userId, int? perangkatId = null)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC tni.SIS_Komplain_Manage @Action = 'CREATE', @Token = @Token,
                    @NoTelp = @NoTelp, @Komentar = @Komentar, @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Token", token ?? string.Empty),
                new SqlParameter("@NoTelp", request.NoTelp ?? string.Empty),
                new SqlParameter("@Komentar", System.Data.SqlDbType.NVarChar, 2000) { Value = request.Komentar ?? string.Empty },
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", (object?)perangkatId ?? DBNull.Value));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<List<TniKomplainDto>> GetByPersonelAsync(int personelId)
        => await _db.Database
            .SqlQueryRaw<TniKomplainDto>(
                "EXEC tni.SIS_Komplain_ByPersonel @PersonelId = @PersonelId",
                new SqlParameter("@PersonelId", personelId))
            .ToListAsync();
}
