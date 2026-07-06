using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Users;

namespace TerakarsaApp.API.Services;

public class UserService
{
    private readonly AppDbContext _db;

    public UserService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<UserPagedResult> GetPagedAsync(UserPagedRequest request)
    {
        var searchParam = new SqlParameter("@Search", request.Search ?? (object)DBNull.Value);
        var pageNumberParam = new SqlParameter("@PageNumber", request.PageNumber);
        var pageSizeParam = new SqlParameter("@PageSize", request.PageSize);
        var sortColumnParam = new SqlParameter("@SortColumn", request.SortColumn ?? (object)DBNull.Value);
        var sortDirectionParam = new SqlParameter("@SortDirection", request.SortDirection);

        var items = await _db.Database
            .SqlQueryRaw<UserDto>(
                "EXEC SIS_User_Manage @Action = 'GET', @Search = @Search, @PageNumber = @PageNumber, @PageSize = @PageSize, @SortColumn = @SortColumn, @SortDirection = @SortDirection",
                searchParam, pageNumberParam, pageSizeParam, sortColumnParam, sortDirectionParam)
            .ToListAsync();

        var countParam = new SqlParameter("@Search", request.Search ?? (object)DBNull.Value);

        var countResult = await _db.Database
            .SqlQueryRaw<int>(
                "EXEC SIS_User_Manage @Action = 'COUNT', @Search = @Search",
                countParam)
            .ToListAsync();

        return new UserPagedResult
        {
            Items = items,
            TotalCount = countResult.FirstOrDefault(),
            PageNumber = request.PageNumber,
            PageSize = request.PageSize
        };
    }

    public async Task<bool> CreateAsync(UserCreateRequest request)
    {
        var usernameParam = new SqlParameter("@Username", request.Username);
        var passwordParam = new SqlParameter("@Password", HashPassword(request.Password));
        var fullNameParam = new SqlParameter("@FullName", request.FullName);
        var roleParam = new SqlParameter("@Role", request.Role);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_User_Manage @Action = 'INSERT', @Username = @Username, @Password = @Password, @FullName = @FullName, @Role = @Role",
            usernameParam, passwordParam, fullNameParam, roleParam);

        return true;
    }

    public async Task UpdateAsync(UserUpdateRequest request)
    {
        var idParam = new SqlParameter("@Id", request.Id);
        var fullNameParam = new SqlParameter("@FullName", request.FullName);
        var roleParam = new SqlParameter("@Role", request.Role);
        var isActiveParam = new SqlParameter("@IsActive", request.IsActive);

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_User_Manage @Action = 'UPDATE', @Id = @Id, @FullName = @FullName, @Role = @Role, @IsActive = @IsActive",
            idParam, fullNameParam, roleParam, isActiveParam);
    }

    public async Task ResetPasswordAsync(UserResetPasswordRequest request)
    {
        var idParam = new SqlParameter("@Id", request.Id);
        var passwordParam = new SqlParameter("@Password", HashPassword(request.NewPassword));

        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_User_Manage @Action = 'RESET_PASSWORD', @Id = @Id, @Password = @Password",
            idParam, passwordParam);
    }

    public async Task DeleteAsync(int id)
    {
        var idParam = new SqlParameter("@Id", id);
        await _db.Database.ExecuteSqlRawAsync(
            "EXEC SIS_User_Manage @Action = 'DELETE', @Id = @Id",
            idParam);
    }

    private static string HashPassword(string password)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(password));
        return Convert.ToHexString(bytes).ToLower();
    }
}
