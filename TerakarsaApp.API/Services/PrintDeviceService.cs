using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.PrintJobs;

namespace TerakarsaApp.API.Services;

// Prompt 77: pengelolaan device cetak (PC & HP Bluetooth) + routing job_type.
//
// Token device dibuat & disimpan SP (SIS_PrintDevice_RegisterMobile) dan hanya
// dikembalikan sekali saat registrasi -- API tidak pernah menyimpannya di tempat lain.
public class PrintDeviceService
{
    private readonly AppDbContext _db;

    public PrintDeviceService(AppDbContext db)
    {
        _db = db;
    }

    private class TokenRow
    {
        public int? PrintDeviceId { get; set; }
    }

    public async Task<int?> ResolveTokenAsync(string deviceToken, string? info)
    {
        var rows = await _db.Database
            .SqlQueryRaw<TokenRow>(
                "EXEC SIS_PrintDevice_ByToken @DeviceToken = @DeviceToken, @Info = @Info",
                new SqlParameter("@DeviceToken", deviceToken),
                new SqlParameter("@Info", string.IsNullOrWhiteSpace(info) ? DBNull.Value : info))
            .ToListAsync();

        return rows.FirstOrDefault()?.PrintDeviceId;
    }

    public async Task<(bool Success, string Error, PrintDeviceRegisterResult? Hasil)> RegisterMobileAsync(
        PrintDeviceRegisterRequest request, int userId)
    {
        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<PrintDeviceRegisterResult>(
                    @"EXEC SIS_PrintDevice_RegisterMobile @DeviceCode = @DeviceCode,
                        @DeviceName = @DeviceName, @PrinterName = @PrinterName, @UserId = @UserId",
                    new SqlParameter("@DeviceCode", request.DeviceCode ?? string.Empty),
                    new SqlParameter("@DeviceName", request.DeviceName ?? string.Empty),
                    new SqlParameter("@PrinterName", (object?)request.PrinterName ?? DBNull.Value),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, rows.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }

    public Task<List<PrintDeviceDto>> GetMobileDevicesAsync() =>
        _db.Database.SqlQueryRaw<PrintDeviceDto>("EXEC SIS_PrintDevice_ListMobile").ToListAsync();

    public Task<List<PrintDeviceDto>> GetAllDevicesAsync() =>
        _db.Database.SqlQueryRaw<PrintDeviceDto>("EXEC SIS_PrintDevice_ListAll").ToListAsync();

    public Task<List<PrintJobRouteDto>> GetRoutesAsync() =>
        _db.Database.SqlQueryRaw<PrintJobRouteDto>("EXEC SIS_PrintJobRoute_List").ToListAsync();

    public async Task<(bool Success, string Error)> SetRouteAsync(PrintJobRouteSetRequest request, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC SIS_PrintJobRoute_Manage @Action = 'SET', @JobType = @JobType,
                    @PrintDeviceId = @PrintDeviceId, @UserId = @UserId",
                new SqlParameter("@JobType", request.JobType ?? string.Empty),
                new SqlParameter("@PrintDeviceId", request.PrintDeviceId),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }
}
