using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Prompt 61: order aktif module PDH TNI AD. Semua halaman /tni/... bekerja pada
// order tni.orders.is_active = 1 -- client menyimpannya di TniOrderState.
// SP di schema tni, jadi EXEC WAJIB memakai awalan schema (tanpa itu SQL Server
// mencari di dbo).
public class TniOrderService
{
    private readonly AppDbContext _db;

    public TniOrderService(AppDbContext db)
    {
        _db = db;
    }

    public async Task<TniOrderAktifDto?> GetAktifAsync()
    {
        var result = await _db.Database
            .SqlQueryRaw<TniOrderAktifDto>("EXEC tni.SIS_Order_Aktif")
            .ToListAsync();

        return result.FirstOrDefault();
    }
}
