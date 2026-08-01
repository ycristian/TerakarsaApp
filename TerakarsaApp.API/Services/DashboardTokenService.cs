using System.Security.Cryptography;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Dashboards;

namespace TerakarsaApp.API.Services;

// Admin CRUD token dashboard TV (JWT, module DASHBOARD_TARGET). Token PENUH hanya pernah
// dikembalikan oleh CreateAsync/RegenerateAsync/GetLinkAsync -- lihat catatan keamanan di
// prompt_38: token ada di URL secara sengaja (kiosk read-only, dicabut per-perangkat).
public class DashboardTokenService
{
    private const int MaxTokenGenerationAttempts = 5;
    private const string TokenCollisionMarker = "TOKEN_COLLISION|";

    private readonly AppDbContext _db;
    private readonly string _publicBaseUrl;

    // Pola sama dengan StationService.PairingCodeCharset -- 5 karakter, hindari yang
    // gampang tertukar (0/O/l/1/I), gampang dibaca/diketik ulang di layar aktivasi TV.
    private static readonly char[] TokenCharset =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            .Where(c => "0Ol1I".IndexOf(c) < 0)
            .ToArray();

    public DashboardTokenService(AppDbContext db, IOptions<AppOptions> appOptions)
    {
        _db = db;
        _publicBaseUrl = appOptions.Value.PublicBaseUrl;
    }

    private static string GenerateToken()
    {
        var chars = new char[5];
        for (var i = 0; i < chars.Length; i++)
            chars[i] = TokenCharset[RandomNumberGenerator.GetInt32(TokenCharset.Length)];
        return new string(chars);
    }

    private string BuildLink(string token) => $"{_publicBaseUrl}/tv-dashboard/{token}";

    public async Task<DashboardTokenPagedResult> GetPagedAsync(DashboardTokenPagedRequest request)
    {
        var listActionParam = new SqlParameter("@Action", "LIST");
        var searchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<DashboardTokenDto>(
                "EXEC SIS_DashboardToken_List @Action = @Action, @SearchTerm = @SearchTerm, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                listActionParam, searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countActionParam = new SqlParameter("@Action", "COUNT");
        var countSearchParam = new SqlParameter("@SearchTerm", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_DashboardToken_List @Action = @Action, @SearchTerm = @SearchTerm",
                countActionParam, countSearchParam)
            .ToListAsync();

        return new DashboardTokenPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<(bool Success, string Error, DashboardTokenCreateResult? Result)> CreateAsync(DashboardTokenCreateRequest request, int userId)
    {
        var nameParam = new SqlParameter("@TokenName", request.TokenName);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var intervalParam = new SqlParameter("@RefreshIntervalMinutes", request.RefreshIntervalMinutes);
        var userIdParam = new SqlParameter("@UserId", userId);

        for (var attempt = 1; attempt <= MaxTokenGenerationAttempts; attempt++)
        {
            var actionParam = new SqlParameter("@Action", "CREATE");
            var token = GenerateToken();
            var tokenParam = new SqlParameter("@Token", token);

            try
            {
                var result = await _db.Database
                    .SqlQueryRaw<int>(
                        "EXEC SIS_DashboardToken_Manage @Action = @Action, @TokenName = @TokenName, @Token = @Token, @IsActive = @IsActive, @RefreshIntervalMinutes = @RefreshIntervalMinutes, @UserId = @UserId",
                        actionParam, nameParam, tokenParam, isActiveParam, intervalParam, userIdParam)
                    .ToListAsync();

                var newId = result.FirstOrDefault();
                if (newId == 0) return (false, "Gagal membuat token dashboard.", null);

                return (true, string.Empty, new DashboardTokenCreateResult
                {
                    Id = newId,
                    Token = token,
                    Link = BuildLink(token)
                });
            }
            catch (SqlException ex) when (ex.Message.Contains(TokenCollisionMarker) && attempt < MaxTokenGenerationAttempts)
            {
                // Token bentrok (sangat jarang, charset 5 karakter) -- generate ulang & coba lagi.
            }
            catch (SqlException ex)
            {
                var message = ex.Message.Contains(TokenCollisionMarker)
                    ? ex.Message[(ex.Message.IndexOf(TokenCollisionMarker, StringComparison.Ordinal) + TokenCollisionMarker.Length)..]
                    : ex.Message;
                return (false, message, null);
            }
        }

        return (false, "Gagal membuat token dashboard setelah beberapa percobaan.", null);
    }

    public async Task<(bool Success, string Error)> UpdateAsync(DashboardTokenUpdateRequest request, int userId)
    {
        var actionParam = new SqlParameter("@Action", "UPDATE");
        var idParam = new SqlParameter("@Id", request.Id);
        var nameParam = new SqlParameter("@TokenName", request.TokenName);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);
        var intervalParam = new SqlParameter("@RefreshIntervalMinutes", request.RefreshIntervalMinutes);
        var userIdParam = new SqlParameter("@UserId", userId);

        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_DashboardToken_Manage @Action = @Action, @Id = @Id, @TokenName = @TokenName, @IsActive = @IsActive, @RefreshIntervalMinutes = @RefreshIntervalMinutes, @UserId = @UserId",
                actionParam, idParam, nameParam, isActiveParam, intervalParam, userIdParam);
            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    public async Task<(bool Success, string Error, DashboardTokenCreateResult? Result)> RegenerateAsync(int id, int userId)
    {
        var idParam0 = new SqlParameter("@Id", id);
        var existsCheck = await _db.Database
            .SqlQueryRaw<int>("SELECT COUNT(*) AS Value FROM dashboard_tokens WHERE dashboard_token_id = @Id AND deleted_at IS NULL", idParam0)
            .ToListAsync();
        if (existsCheck.FirstOrDefault() == 0) return (false, "Token dashboard tidak ditemukan.", null);

        for (var attempt = 1; attempt <= MaxTokenGenerationAttempts; attempt++)
        {
            var actionParam = new SqlParameter("@Action", "REGENERATE");
            var idParam = new SqlParameter("@Id", id);
            var token = GenerateToken();
            var tokenParam = new SqlParameter("@Token", token);
            var userIdParam = new SqlParameter("@UserId", userId);

            try
            {
                await _db.Database.ExecuteSqlRawAsync(
                    "EXEC SIS_DashboardToken_Manage @Action = @Action, @Id = @Id, @Token = @Token, @UserId = @UserId",
                    actionParam, idParam, tokenParam, userIdParam);

                return (true, string.Empty, new DashboardTokenCreateResult
                {
                    Id = id,
                    Token = token,
                    Link = BuildLink(token)
                });
            }
            catch (SqlException ex) when (ex.Message.Contains(TokenCollisionMarker) && attempt < MaxTokenGenerationAttempts)
            {
                // Token bentrok (sangat jarang, charset 5 karakter) -- generate ulang & coba lagi.
            }
            catch (SqlException ex)
            {
                var message = ex.Message.Contains(TokenCollisionMarker)
                    ? ex.Message[(ex.Message.IndexOf(TokenCollisionMarker, StringComparison.Ordinal) + TokenCollisionMarker.Length)..]
                    : ex.Message;
                return (false, message, null);
            }
        }

        return (false, "Gagal membuat ulang token dashboard setelah beberapa percobaan.", null);
    }

    public async Task DeleteAsync(int id, int userId)
    {
        var actionParam = new SqlParameter("@Action", "DELETE");
        var idParam = new SqlParameter("@Id", id);
        var userIdParam = new SqlParameter("@UserId", userId);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_DashboardToken_Manage @Action = @Action, @Id = @Id, @UserId = @UserId",
            actionParam, idParam, userIdParam);
    }

    public async Task<string?> GetLinkAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);

        var result = await _db.Database
            .SqlQueryRaw<string>("EXEC SIS_DashboardToken_GetToken @Id = @Id", idParam)
            .ToListAsync();

        var token = result.FirstOrDefault();
        return token is null ? null : BuildLink(token);
    }

    // Dipakai oleh RequireDashboardTokenAttribute (kiosk, tanpa JWT).
    public async Task<DashboardTokenAuthDto?> GetByTokenAsync(string token)
    {
        var tokenParam = new SqlParameter("@Token", token);

        var result = await _db.Database
            .SqlQueryRaw<DashboardTokenAuthDto>("EXEC SIS_DashboardToken_GetByToken @Token = @Token", tokenParam)
            .ToListAsync();

        return result.FirstOrDefault();
    }

    public async Task TouchAsync(string token)
    {
        var actionParam = new SqlParameter("@Action", "TOUCH");
        var tokenParam = new SqlParameter("@Token", token);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_DashboardToken_Manage @Action = @Action, @Token = @Token",
            actionParam, tokenParam);
    }
}
