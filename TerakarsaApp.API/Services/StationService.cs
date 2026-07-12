using System.Security.Cryptography;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Stations;

namespace TerakarsaApp.API.Services;

public class StationService
{
    private readonly AppDbContext _db;
    private readonly string _publicBaseUrl;

    // Prompt 20: charset kode pairing -- hindari karakter yang gampang tertukar (0/O/l/1/I).
    private static readonly char[] PairingCodeCharset =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            .Where(c => "0Ol1I".IndexOf(c) < 0)
            .ToArray();

    public StationService(AppDbContext db, IOptions<AppOptions> appOptions)
    {
        _db = db;
        _publicBaseUrl = appOptions.Value.PublicBaseUrl;
    }

    private class NewStationRow
    {
        public int NewId { get; set; }
        public string NewToken { get; set; } = string.Empty;
    }

    private class PairingCodeRow
    {
        public string PairingCode { get; set; } = string.Empty;
        public DateTime ExpiresAt { get; set; }
    }

    private class ClaimedStationRow
    {
        public int StationId { get; set; }
    }

    private static string GeneratePairingCode()
    {
        var chars = new char[5];
        for (var i = 0; i < chars.Length; i++)
            chars[i] = PairingCodeCharset[RandomNumberGenerator.GetInt32(PairingCodeCharset.Length)];
        return new string(chars);
    }

    public async Task<StationPagedResult> GetPagedAsync(StationPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<StationDto>(
                "EXEC SIS_Station_GetAll @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_Station_GetAll @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new StationPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<StationDto?> GetByIdAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<StationDto>("EXEC SIS_Station_GetById @Id = @Id", idParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<StationMeDto?> GetByTokenAsync(string token)
    {
        var tokenParam = new SqlParameter("@Token", token);

        var result = await _db.Database
            .SqlQueryRaw<StationMeDto>("EXEC SIS_Station_GetByToken @Token = @Token", tokenParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task<(bool Success, string Error, StationTokenResult? Result)> CreateAsync(StationCreateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "CREATE");
        var codeParam = new SqlParameter("@StationCode", request.StationCode);
        var nameParam = new SqlParameter("@StationName", request.StationName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var defaultResourceIdParam = new SqlParameter("@DefaultResourceId", request.DefaultResourceId ?? (object)DBNull.Value);
        var allowResourceChangeParam = new SqlParameter("@AllowResourceChange", request.AllowResourceChange);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<NewStationRow>(
                    "EXEC SIS_Station_Manage @Action = @Action, @StationCode = @StationCode, @StationName = @StationName, @DivisionId = @DivisionId, @IsActive = @IsActive, @DefaultResourceId = @DefaultResourceId, @AllowResourceChange = @AllowResourceChange, @UserId = @UserId",
                    actionParam, codeParam, nameParam, divisionIdParam, isActiveParam, defaultResourceIdParam, allowResourceChangeParam, userIdParam)
                .ToListAsync();

            var row = result.FirstOrDefault();
            if (row is null) return (false, "Gagal membuat stasiun.", null);

            return (true, string.Empty, new StationTokenResult { Id = row.NewId, Token = row.NewToken });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public async Task<(bool Success, string Error)> UpdateAsync(StationUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var codeParam = new SqlParameter("@StationCode", request.StationCode);
        var nameParam = new SqlParameter("@StationName", request.StationName);
        var divisionIdParam = new SqlParameter("@DivisionId", request.DivisionId);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var defaultResourceIdParam = new SqlParameter("@DefaultResourceId", request.DefaultResourceId ?? (object)DBNull.Value);
        var allowResourceChangeParam = new SqlParameter("@AllowResourceChange", request.AllowResourceChange);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @StationCode = @StationCode, @StationName = @StationName, @DivisionId = @DivisionId, @IsActive = @IsActive, @DefaultResourceId = @DefaultResourceId, @AllowResourceChange = @AllowResourceChange, @UserId = @UserId",
                actionParam, idParam, codeParam, nameParam, divisionIdParam, isActiveParam, defaultResourceIdParam, allowResourceChangeParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    // Prompt 20: generate kode pairing 5 karakter di sisi API, retry bila bentrok unique
    // index (SqlException 2601/2627) dengan kode baru -- lihat UX_stations_pairing_code.
    public async Task<(bool Success, string Error, StationPairingResult? Result)> GeneratePairingCodeAsync(int id, int userId)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            var code = GeneratePairingCode();

            var actionParam = new SqlParameter("@Action", "GENERATE_PAIRING");
            var idParam = new SqlParameter("@Id", id);
            var codeParam = new SqlParameter("@PairingCode", code);
            var userIdParam = new SqlParameter("@UserId", userId);

            try
            {
                var result = await _db.Database
                    .SqlQueryRaw<PairingCodeRow>(
                        "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @PairingCode = @PairingCode, @UserId = @UserId",
                        actionParam, idParam, codeParam, userIdParam)
                    .ToListAsync();

                var row = result.FirstOrDefault();
                if (row is null) return (false, "Stasiun tidak ditemukan atau nonaktif.", null);

                return (true, string.Empty, new StationPairingResult
                {
                    Code = row.PairingCode,
                    ExpiresAt = row.ExpiresAt,
                    Link = $"{_publicBaseUrl}/station/{row.PairingCode}"
                });
            }
            catch (SqlException ex) when (ex.Number is 2601 or 2627)
            {
                // Kode bentrok dengan kode aktif station lain, coba kode baru.
            }
            catch (SqlException ex)
            {
                return (false, ex.Message, null);
            }
        }

        return (false, "Gagal membuat kode pairing, coba lagi.", null);
    }

    // Prompt 20: perangkat menukar kode pairing dengan station_token baru (anonim).
    public async Task<(bool Success, string Error, StationTokenResult? Result)> ClaimPairingAsync(string code)
    {
        var newToken = Guid.NewGuid().ToString("N");

        var actionParam = new SqlParameter("@Action", "CLAIM_PAIRING");
        var codeParam = new SqlParameter("@PairingCode", code);
        var tokenParam = new SqlParameter("@NewToken", newToken);

        try
        {
            var result = await _db.Database
                .SqlQueryRaw<ClaimedStationRow>(
                    "EXEC SIS_Station_Manage @Action = @Action, @PairingCode = @PairingCode, @NewToken = @NewToken",
                    actionParam, codeParam, tokenParam)
                .ToListAsync();

            var row = result.FirstOrDefault();
            if (row is null) return (false, "Kode pairing tidak valid atau sudah kedaluwarsa.", null);

            return (true, string.Empty, new StationTokenResult { Id = row.StationId, Token = newToken });
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    // Prompt 20: putuskan perangkat -- dipakai admin ("Putuskan Perangkat") maupun
    // perangkat sendiri (logout, @UserId = system user karena tanpa JWT).
    public async Task<(bool Success, string Error)> UnpairAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UNPAIR");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_Station_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
                actionParam, idParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}
