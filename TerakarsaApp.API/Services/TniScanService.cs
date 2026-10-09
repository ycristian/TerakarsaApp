using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 66: scan "Set Jadi" & halaman QR /t/{token} PDH TNI AD.
//
// SIS_Scan_SetJadi mengembalikan hasil sebagai result set (OK / SUDAH /
// TIDAK_DIKENAL), bukan exception -- jadi service ini tidak perlu try/catch
// untuk kasus bisnis, hanya untuk error tak terduga.
public class TniScanService
{
    private readonly AppDbContext _db;

    public TniScanService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<TniScanHasilDto> SetJadiAsync(string kode, int userId, int? perangkatId = null)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniScanHasilDto>(
                "EXEC tni.SIS_Scan_SetJadi @Kode = @Kode, @UserId = @UserId, @PerangkatId = @PerangkatId",
                new SqlParameter("@Kode", kode ?? string.Empty),
                new SqlParameter("@UserId", userId),
                new SqlParameter("@PerangkatId", perangkatId ?? (object)DBNull.Value))
            .ToListAsync();

        return result.FirstOrDefault() ?? new TniScanHasilDto
        {
            Hasil = "TIDAK_DIKENAL",
            Pesan = "Kode tidak dikenal."
        };
    }

    // Pop up konfirmasi scan Set Jadi: cari kartu TANPA mencatat apa pun.
    // null = kode tidak dikenal di order aktif.
    public async Task<TniPersonelDetailDto?> LookupAsync(string kode)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniPersonelDetailDto>(
                "EXEC tni.SIS_Scan_Lookup @Kode = @Kode",
                new SqlParameter("@Kode", kode ?? string.Empty))
            .ToListAsync();

        return result.FirstOrDefault();
    }

    // Halaman publik -- data minimal, tanpa NRP / No HP / ukuran badan.
    public async Task<TniPublicPersonelDto?> GetPublicByTokenAsync(string token)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniPublicPersonelDto>(
                "EXEC tni.SIS_Public_ByToken @Token = @Token",
                new SqlParameter("@Token", token ?? string.Empty))
            .ToListAsync();

        return result.FirstOrDefault();
    }

    // Untuk user login -- bentuknya sama dengan detail personel.
    public async Task<TniPersonelDetailDto?> GetDetailByTokenAsync(string token)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniPersonelDetailDto>(
                "EXEC tni.SIS_Personel_ByToken @Token = @Token",
                new SqlParameter("@Token", token ?? string.Empty))
            .ToListAsync();

        return result.FirstOrDefault();
    }
}
