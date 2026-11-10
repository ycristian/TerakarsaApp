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

    // Prompt 88: daftar LENGKAP device tujuan job_type (multi-pilih di halaman admin).
    public async Task<(bool Success, string Error)> SetRouteAsync(PrintJobRouteSetRequest request, int userId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                @"EXEC SIS_PrintJobRoute_Manage @Action = 'SET', @JobType = @JobType,
                    @PrintDeviceIdsCsv = @PrintDeviceIdsCsv, @UserId = @UserId",
                new SqlParameter("@JobType", request.JobType ?? string.Empty),
                new SqlParameter("@PrintDeviceIdsCsv", string.Join(',', request.PrintDeviceIds.Distinct())),
                new SqlParameter("@UserId", userId));

            return (true, string.Empty);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message);
        }
    }

    // ==================== Prompt 88 ====================

    // Isi PrinterPicker: device aktif yang jadi tujuan route job type ini.
    public Task<List<PrintDeviceOptionDto>> GetForJobTypeAsync(string jobType) =>
        _db.Database
            .SqlQueryRaw<PrintDeviceOptionDto>(
                "EXEC SIS_PrintDevice_ListForJobType @JobType = @JobType",
                new SqlParameter("@JobType", jobType.Trim().ToUpperInvariant()))
            .ToListAsync();

    // Cek pilihan printer TANPA membuat job (aturan yang sama dengan SP pembuat job,
    // SIS_PrintJob_ResolveDevice). Dipakai jalur yang aksinya terjadi lebih dulu dari
    // pembuatan label (claim bundle cutting di station). null = boleh lanjut.
    public async Task<string?> ValidateAsync(string jobType, int? printDeviceId)
    {
        try
        {
            await _db.Database.ExecuteSqlRawAsync(
                "EXEC SIS_PrintJob_ResolveDevice @JobType = @JobType, @RequestedDeviceId = @RequestedDeviceId, @DeviceId = @DeviceId OUTPUT",
                new SqlParameter("@JobType", jobType),
                new SqlParameter("@RequestedDeviceId", (object?)printDeviceId ?? DBNull.Value),
                new SqlParameter("@DeviceId", System.Data.SqlDbType.Int) { Direction = System.Data.ParameterDirection.Output });
            return null;
        }
        catch (SqlException ex)
        {
            return ex.Message;
        }
    }

    private class DeviceIdRow
    {
        public int PrintDeviceId { get; set; }
    }

    private class NewPrintJobRow
    {
        public int NewPrintJobId { get; set; }
    }

    // id null = tambah device PC baru; terisi = ubah (device HP: hanya nama/grup/aktif).
    public async Task<(bool Success, string Error, int PrintDeviceId)> SaveDeviceAsync(
        int? id, PrintDeviceSaveRequest request, int userId)
    {
        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<DeviceIdRow>(
                    @"EXEC SIS_PrintDevice_Manage @Action = @Action, @Id = @Id, @DeviceCode = @DeviceCode,
                        @DeviceName = @DeviceName, @Transport = @Transport, @PrinterName = @PrinterName,
                        @Host = @Host, @Port = @Port, @RenderMode = @RenderMode, @DeviceGroup = @DeviceGroup,
                        @IsActive = @IsActive, @UserId = @UserId",
                    new SqlParameter("@Action", id.HasValue ? "UPDATE" : "CREATE"),
                    new SqlParameter("@Id", (object?)id ?? DBNull.Value),
                    new SqlParameter("@DeviceCode", request.DeviceCode ?? string.Empty),
                    new SqlParameter("@DeviceName", request.DeviceName ?? string.Empty),
                    new SqlParameter("@Transport", request.Transport ?? string.Empty),
                    new SqlParameter("@PrinterName", (object?)request.PrinterName ?? DBNull.Value),
                    new SqlParameter("@Host", (object?)request.Host ?? DBNull.Value),
                    new SqlParameter("@Port", (object?)request.Port ?? DBNull.Value),
                    new SqlParameter("@RenderMode", request.RenderMode ?? string.Empty),
                    new SqlParameter("@DeviceGroup", request.DeviceGroup ?? string.Empty),
                    new SqlParameter("@IsActive", request.IsActive),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, rows.FirstOrDefault()?.PrintDeviceId ?? 0);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }

    // Job TEST_PRINT langsung ke device ini (tanpa route).
    public async Task<(bool Success, string Error, int PrintJobId)> TestPrintAsync(int id, int userId)
    {
        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<NewPrintJobRow>(
                    "EXEC SIS_PrintDevice_Manage @Action = 'TEST_PRINT', @Id = @Id, @UserId = @UserId",
                    new SqlParameter("@Id", id),
                    new SqlParameter("@UserId", userId))
                .ToListAsync();

            return (true, string.Empty, rows.FirstOrDefault()?.NewPrintJobId ?? 0);
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, 0);
        }
    }
}
