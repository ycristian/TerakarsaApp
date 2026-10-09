using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Opsi modul PDH TNI AD.
//   SystemUserId -- user `tni_system`, pengisi created_by semua mutasi dari
//                   perangkat (api/tni/* tidak punya JWT).
//   QrBaseUrl    -- alamat publik untuk isi QR kartu.
public class TniOptions
{
    public int SystemUserId { get; set; }
    public string QrBaseUrl { get; set; } = string.Empty;
}

// Perangkat (pairing, tanpa login). Satu nama petugas per perangkat (alter_75).
public class TniPerangkatService
{
    private readonly AppDbContext _db;

    public TniPerangkatService(AppDbContext db)
    {
        _db = db;
    }

    // ---------------- perangkat: dipakai filter otorisasi ----------------

    public async Task<TniPerangkatMeDto?> GetByTokenAsync(string token)
    {
        var result = await _db.Database
            .SqlQueryRaw<TniPerangkatMeDto>(
                "EXEC tni.SIS_Perangkat_GetByToken @Token = @Token",
                new SqlParameter("@Token", token))
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<List<TniPerangkatDto>> GetListAsync()
        => await _db.Database.SqlQueryRaw<TniPerangkatDto>("EXEC tni.SIS_Perangkat_List").ToListAsync();

    public async Task<(bool Success, string Error, int? Id)> CreateAsync(
        TniPerangkatCreateRequest request, int userId)
    {
        try
        {
            var result = await _db.Database
                .SqlQueryRaw<int>(
                    @"EXEC tni.SIS_Perangkat_Manage @Action = 'CREATE',
                        @PerangkatCode = @Code, @PerangkatName = @Name, @NamaPetugas = @NamaPetugas,
                        @Keterangan = @Ket, @IsActive = @Aktif, @Menu = @Menu, @UserId = @UserId",
                    new SqlParameter("@Code", request.PerangkatCode ?? string.Empty),
                    new SqlParameter("@Name", request.PerangkatName ?? string.Empty),
                    new SqlParameter("@NamaPetugas", request.NamaPetugas ?? string.Empty),
                    new SqlParameter("@Ket", (object?)request.Keterangan ?? DBNull.Value),
                    new SqlParameter("@Aktif", request.IsActive),
                    MenuParam(request.Menu),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(
        int id, TniPerangkatCreateRequest request, int userId)
        => await ExecAsync(
            @"EXEC tni.SIS_Perangkat_Manage @Action = 'UPDATE', @Id = @Id,
                @PerangkatCode = @Code, @PerangkatName = @Name, @NamaPetugas = @NamaPetugas,
                @Keterangan = @Ket, @IsActive = @Aktif, @Menu = @Menu, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@Code", request.PerangkatCode ?? string.Empty),
            new SqlParameter("@Name", request.PerangkatName ?? string.Empty),
            new SqlParameter("@NamaPetugas", request.NamaPetugas ?? string.Empty),
            new SqlParameter("@Ket", (object?)request.Keterangan ?? DBNull.Value),
            new SqlParameter("@Aktif", request.IsActive),
            MenuParam(request.Menu),
            new SqlParameter("@UserId", userId));

    public async Task<(bool Success, string Error)> DeleteAsync(int id, int userId)
        => await ExecAsync(
            "EXEC tni.SIS_Perangkat_Manage @Action = 'DELETE', @Id = @Id, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId));

    public async Task<(bool Success, string Error)> UnpairAsync(int id, int userId)
        => await ExecAsync(
            "EXEC tni.SIS_Perangkat_Manage @Action = 'UNPAIR', @Id = @Id, @UserId = @UserId",
            new SqlParameter("@Id", id),
            new SqlParameter("@UserId", userId));

    // Kode pairing digenerate di API (bukan SP) supaya karakter yang mudah
    // tertukar dibuang -- 0/O/1/I/5/S tidak dipakai.
    private const string PairingAlphabet = "ABCDEFGHJKLMNPQRTUVWXY2346789";

    public async Task<(bool Success, string Error, TniPairingCodeDto? Hasil)> GeneratePairingAsync(
        int id, int userId)
    {
        var code = new string(Enumerable.Range(0, 5)
            .Select(_ => PairingAlphabet[Random.Shared.Next(PairingAlphabet.Length)])
            .ToArray());

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<TniPairingCodeDto>(
                    @"EXEC tni.SIS_Perangkat_Manage @Action = 'GENERATE_PAIRING', @Id = @Id,
                        @PairingCode = @Code, @UserId = @UserId",
                    new SqlParameter("@Id", id),
                    new SqlParameter("@Code", code),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, result.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // DIPANGGIL TANPA LOGIN oleh perangkat. Token baru digenerate di sini dan
    // dikembalikan SEKALI -- setelah ini hanya perangkat yang memegangnya.
    public async Task<(bool Success, string Error, TniClaimResultDto? Hasil)> ClaimAsync(string pairingCode)
    {
        var token = Guid.NewGuid().ToString("N");

        try
        {
            var claimed = await _db.Database
                .SqlQueryRaw<int>(
                    @"EXEC tni.SIS_Perangkat_Manage @Action = 'CLAIM_PAIRING',
                        @PairingCode = @Code, @NewToken = @Token",
                    new SqlParameter("@Code", (pairingCode ?? string.Empty).Trim().ToUpperInvariant()),
                    new SqlParameter("@Token", token))
                .ToListAsync();

            if (claimed.Count == 0)
                return (false, "Kode pairing tidak valid atau sudah kedaluwarsa.", null);

            var me = await GetByTokenAsync(token);

            return (true, string.Empty, new TniClaimResultDto { Token = token, Perangkat = me });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // Menu -> JSON array untuk @Menu; null diteruskan sebagai NULL (lihat SP).
    private static SqlParameter MenuParam(List<string>? menu)
        => new("@Menu", System.Data.SqlDbType.NVarChar, -1)
        {
            Value = menu is null ? DBNull.Value : System.Text.Json.JsonSerializer.Serialize(menu)
        };

    private async Task<(bool Success, string Error)> ExecAsync(string sql, params SqlParameter[] p)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(sql, p);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}
