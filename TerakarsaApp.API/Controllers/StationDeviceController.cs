using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Stations;
using TerakarsaApp.Shared.WorkflowLogs;

namespace TerakarsaApp.API.Controllers;

// Endpoint untuk perangkat stasiun (tablet/HP) di lantai produksi.
// TIDAK memakai [Authorize] JWT — autentikasi murni lewat header X-Station-Token,
// divalidasi oleh RequireStationTokenAttribute terhadap sp SIS_Station_GetByToken.
// created_by log dari stasiun memakai user sistem (lihat StationOptions.SystemUserId,
// diisi dari sql/seed_station_system_user.sql via appsettings Station:SystemUserId).
[ApiController]
[Route("api/station")]
[RequireStationToken]
public class StationDeviceController : ControllerBase
{
    private readonly WorkflowLogService _workflowLogService;
    private readonly ResourceService _resourceService;
    private readonly BundleService _bundleService;
    private readonly int _systemUserId;

    public StationDeviceController(
        WorkflowLogService workflowLogService,
        ResourceService resourceService,
        BundleService bundleService,
        IOptions<StationOptions> stationOptions)
    {
        _workflowLogService = workflowLogService;
        _resourceService = resourceService;
        _bundleService = bundleService;
        _systemUserId = stationOptions.Value.SystemUserId;
    }

    private StationMeDto CurrentStation => (StationMeDto)HttpContext.Items[RequireStationTokenAttribute.HttpContextItemKey]!;

    [HttpGet("me")]
    public IActionResult Me()
    {
        return Ok(CurrentStation);
    }

    [HttpGet("resources")]
    public async Task<IActionResult> GetResources()
    {
        var result = await _resourceService.GetActiveByDivisionAsync(CurrentStation.DivisionId);
        return Ok(result);
    }

    [HttpGet("pending-receives")]
    public async Task<IActionResult> GetPendingReceives()
    {
        var result = await _workflowLogService.GetPendingReceivesAsync(CurrentStation.DivisionId);
        return Ok(result);
    }

    // Baris yang dibuat divisi ini sendiri, sudah punya tujuan serah, tapi belum diterima
    // (received_at IS NULL) -- masih boleh direvisi lewat PUT logs/{id} di bawah.
    [HttpGet("pending-handover")]
    public async Task<IActionResult> GetPendingHandover()
    {
        var result = await _workflowLogService.GetPendingHandoverAsync(CurrentStation.DivisionId);
        return Ok(result);
    }

    // Pintu masuk universal panel Scan Bundle di /station: @ResourceId dari operator sesi
    // (query string, sama seperti currentOperatorId dipakai di receive/complete lain),
    // @DivisionId selalu dari token perangkat.
    [HttpGet("scan/{serial}")]
    public async Task<IActionResult> Scan(string serial, [FromQuery] int? resourceId)
    {
        var result = await _bundleService.GetScanInfoAsync(serial, CurrentStation.DivisionId, resourceId);
        if (result is null) return NotFound("Bundle tidak ditemukan.");
        return Ok(result);
    }

    // Prompt 12b: model log 1-baris -- "menerima" kini UPDATE received_at/received_by
    // pada baris yang sudah ada (workflowLogId), bukan lagi INSERT baris RECEIVED baru.
    [HttpPost("receive")]
    public async Task<IActionResult> Receive([FromBody] StationReceiveRequest request)
    {
        if (request.ResourceId <= 0) return BadRequest("Operator wajib dipilih.");

        var (success, error) = await _workflowLogService.ReceiveAsync(new WorkflowLogReceiveInput
        {
            WorkflowLogId = request.WorkflowLogId,
            ReceivedByResourceId = request.ResourceId,
            ReceivedRemark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId
        });

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Pekerjaan step ber-bundle selesai lewat alur scan (dulu berstatus 'COMPLETED', kini
    // satu-satunya arti INSERT di model log baru). Sejak Prompt 12c, step non-bundle (mis.
    // Cutting) tidak lagi dicatat lewat stasiun -- panel "Dikerjakan" dihapus, pencatatannya
    // pindah ke halaman /workflow-input (WorkflowInputController, login biasa). BundleId
    // karena itu wajib di sini; SP sendiri sebenarnya masih izinkan BundleId kosong (dipakai
    // dulu oleh panel yang sudah dihapus), jadi pesan ini murni penjaga tambahan di API.
    [HttpPost("complete")]
    public async Task<IActionResult> Complete([FromBody] StationCompleteRequest request)
    {
        if (request.ResourceId <= 0) return BadRequest("Operator wajib dipilih.");

        if (request.BundleId is null)
            return BadRequest("Step tanpa bundle dicatat lewat menu Hasil Cutting.");

        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0 || request.QtyRework < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var (success, error) = await _workflowLogService.CreateAsync(new WorkflowLogCreateInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            BundleId = request.BundleId,
            ArticleSizeId = request.ArticleSizeId,
            ResourceId = request.ResourceId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            QtyRework = request.QtyRework,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Revisi data sebelum diterima (dipakai divisi pembuat baris, lihat "pending-handover"
    // di atas). Ditolak SP kalau baris sudah diterima (received_at terisi) atau bukan
    // milik divisi ini.
    [HttpPut("logs/{id:int}")]
    public async Task<IActionResult> UpdateLog(int id, [FromBody] StationLogUpdateRequest request)
    {
        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0 || request.QtyRework < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var (success, error) = await _workflowLogService.UpdateAsync(new WorkflowLogUpdateInput
        {
            Id = id,
            ArticleSizeId = request.ArticleSizeId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            QtyRework = request.QtyRework,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId
        });

        if (!success) return BadRequest(error);
        return Ok();
    }
}
