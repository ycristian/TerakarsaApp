using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using TerakarsaApp.API.Data;
using TerakarsaApp.Shared.Inv;

namespace TerakarsaApp.API.Services;

// Prompt 72: movement module Stok Benang. SELURUH perubahan saldo ada di
// inv.SIS_ThreadMovement_Manage (satu transaksi per mutasi, saldo tidak boleh minus);
// service ini hanya meneruskan parameter dan menerjemahkan SqlException jadi pesan UI.
//
// Dipisah dari ThreadStockService (master/SKU) supaya satu file tidak jadi tempat
// semuanya -- pola sama dengan TniStokService vs TniPolaService.
public class ThreadMovementService
{
    private readonly AppDbContext _db;
    private readonly ThreadStockService _threadStockService;

    public ThreadMovementService(AppDbContext db, ThreadStockService threadStockService)
    {
        _db = db;
        _threadStockService = threadStockService;
    }

    // ==================== MUTASI ====================

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ReceiveAsync(
        ThreadReceiveRequest request, int userId) =>
        ManageAsync("RECEIVE", userId,
            new SqlParameter("@ItemId", request.ThreadItemId),
            new SqlParameter("@ToLocationId", request.ToLocationId),
            new SqlParameter("@Qty", request.Qty),
            new SqlParameter("@ProjectId", request.ProjectId ?? (object)DBNull.Value),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> IssueAsync(
        ThreadIssueRequest request, int userId) =>
        ManageAsync("ISSUE", userId,
            new SqlParameter("@ItemId", request.ThreadItemId),
            new SqlParameter("@FromLocationId", request.FromLocationId),
            new SqlParameter("@Qty", request.Qty),
            new SqlParameter("@ResourceId", request.ResourceId),
            new SqlParameter("@ProjectId", request.ProjectId ?? (object)DBNull.Value),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    // Mengembalikan cone_code kones split baru (dipakai halaman Kembali & label Prompt 73).
    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ReturnAsync(
        ThreadReturnRequest request, int userId) =>
        ManageAsync("RETURN", userId,
            new SqlParameter("@ItemId", request.ThreadItemId),
            new SqlParameter("@WeightGram", request.WeightGram),
            new SqlParameter("@ToLocationId", request.ToLocationId),
            new SqlParameter("@ResourceId", request.ResourceId ?? (object)DBNull.Value),
            new SqlParameter("@ProjectId", request.ProjectId ?? (object)DBNull.Value),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> IssueSplitAsync(
        ThreadIssueSplitRequest request, int userId) =>
        ManageAsync("ISSUE_SPLIT", userId,
            new SqlParameter("@SplitConeId", request.ThreadSplitConeId),
            new SqlParameter("@ResourceId", request.ResourceId),
            new SqlParameter("@ProjectId", request.ProjectId ?? (object)DBNull.Value),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ReturnSplitAsync(
        ThreadReturnSplitRequest request, int userId) =>
        ManageAsync("RETURN_SPLIT", userId,
            new SqlParameter("@SplitConeId", request.ThreadSplitConeId),
            new SqlParameter("@WeightGram", request.WeightGram),
            new SqlParameter("@ToLocationId", request.ToLocationId),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> MoveAsync(
        ThreadMoveRequest request, int userId) =>
        ManageAsync("MOVE", userId,
            new SqlParameter("@ItemId", request.ThreadItemId),
            new SqlParameter("@FromLocationId", request.FromLocationId),
            new SqlParameter("@ToLocationId", request.ToLocationId),
            new SqlParameter("@Qty", request.Qty),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> MoveSplitAsync(
        ThreadMoveSplitRequest request, int userId) =>
        ManageAsync("MOVE_SPLIT", userId,
            new SqlParameter("@SplitConeId", request.ThreadSplitConeId),
            new SqlParameter("@ToLocationId", request.ToLocationId),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    public Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> EmptyAsync(
        ThreadEmptyRequest request, int userId) =>
        ManageAsync("EMPTY", userId,
            new SqlParameter("@SplitConeId", request.ThreadSplitConeId),
            new SqlParameter("@Note", (object?)request.Note ?? DBNull.Value));

    // ==================== BACA ====================

    public Task<List<ThreadItemStockDto>> GetStocksByItemAsync(int itemId, bool hanyaAda) =>
        _db.Database.SqlQueryRaw<ThreadItemStockDto>(
                "EXEC inv.SIS_ThreadStock_ByItem @ItemId = @ItemId, @HanyaAda = @HanyaAda",
                new SqlParameter("@ItemId", itemId),
                new SqlParameter("@HanyaAda", hanyaAda))
            .ToListAsync();

    public Task<List<ThreadMovementDto>> GetRecentMovementsAsync(int itemId, int top) =>
        _db.Database.SqlQueryRaw<ThreadMovementDto>(
                "EXEC inv.SIS_ThreadMovement_Recent @ItemId = @ItemId, @Top = @Top",
                new SqlParameter("@ItemId", itemId),
                new SqlParameter("@Top", top))
            .ToListAsync();

    public async Task<ThreadSplitConeDto?> GetSplitConeByCodeAsync(string coneCode)
    {
        var rows = await _db.Database
            .SqlQueryRaw<ThreadSplitConeDto>(
                "EXEC inv.SIS_ThreadSplitCone_GetByCode @ConeCode = @ConeCode",
                new SqlParameter("@ConeCode", coneCode ?? string.Empty))
            .ToListAsync();

        return rows.FirstOrDefault();
    }

    public async Task<ThreadSplitConeDto?> GetSplitConeByIdAsync(int splitConeId)
    {
        var rows = await _db.Database
            .SqlQueryRaw<ThreadSplitConeDto>(
                "EXEC inv.SIS_ThreadSplitCone_GetByCode @SplitConeId = @SplitConeId",
                new SqlParameter("@SplitConeId", splitConeId))
            .ToListAsync();

        return rows.FirstOrDefault();
    }

    public Task<List<ThreadResourceLookupDto>> GetResourcesAsync() =>
        _db.Database.SqlQueryRaw<ThreadResourceLookupDto>("EXEC inv.SIS_ThreadLookup_Resources").ToListAsync();

    public Task<List<ThreadProjectLookupDto>> GetProjectsAsync() =>
        _db.Database.SqlQueryRaw<ThreadProjectLookupDto>("EXEC inv.SIS_ThreadLookup_Projects").ToListAsync();

    // ==================== SCAN ====================

    // Isi QR label: `TB:<sku_code>` (label SKU, sama untuk semua kones whole SKU itu)
    // atau `TS:<cone_code>` (label satu kones split). Tanpa prefix: coba sku_code dulu,
    // lalu cone_code -- supaya scanner Bluetooth yang hanya mengirim kodenya tetap jalan.
    public async Task<ThreadScanResultDto> ScanAsync(string code)
    {
        var raw = (code ?? string.Empty).Trim();
        var hasil = new ThreadScanResultDto { RawCode = raw };

        if (raw.Length == 0) return hasil;

        var prefix = raw.Length >= 3 ? raw[..3].ToUpperInvariant() : string.Empty;
        var isi = prefix is "TB:" or "TS:" ? raw[3..].Trim() : raw;

        if (prefix != "TS:")
        {
            var item = await _threadStockService.GetItemBySkuAsync(isi);
            if (item is not null)
            {
                hasil.Kind = "ITEM";
                hasil.Item = item;
                return hasil;
            }

            // prefix TB: tapi sku_code tidak ada -> jangan coba sebagai kones split
            if (prefix == "TB:") return hasil;
        }

        var cone = await GetSplitConeByCodeAsync(isi);
        if (cone is not null)
        {
            hasil.Kind = "SPLIT";
            hasil.Cone = cone;
            hasil.Item = (await _threadStockService.GetItemByIdAsync(cone.ThreadItemId))?.Item;
        }

        return hasil;
    }

    // ==================== bantuan ====================

    private async Task<(bool Success, string Error, ThreadMovementResultDto? Hasil)> ManageAsync(
        string action, int userId, params SqlParameter[] parameters)
    {
        // Parameter dirakit dinamis supaya tiap action hanya mengirim yang relevan
        // (sisanya memakai default NULL di SP).
        var names = parameters.Select(p => $"{p.ParameterName} = {p.ParameterName}");
        var sql = $"EXEC inv.SIS_ThreadMovement_Manage @Action = @Action, {string.Join(", ", names)}, @UserId = @UserId";

        var all = new List<SqlParameter> { new("@Action", action) };
        all.AddRange(parameters);
        all.Add(new SqlParameter("@UserId", userId));

        try
        {
            var rows = await _db.Database
                .SqlQueryRaw<ThreadMovementResultDto>(sql, all.ToArray())
                .ToListAsync();

            return (true, string.Empty, rows.FirstOrDefault());
        }
        catch (SqlException ex)
        {
            return (false, ex.Message, null);
        }
    }
}
