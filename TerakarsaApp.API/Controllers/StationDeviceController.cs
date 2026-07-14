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

    // Prompt 16: stasiun terkunci (AllowResourceChange = false) memaksa resourceId dari
    // request diabaikan dan diganti default_resource_id stasiun -- penegakan sisi server,
    // bukan hanya UI, supaya tidak bisa dilewati lewat panggilan API langsung.
    private int EffectiveResourceId(int requestedResourceId) =>
        CurrentStation.AllowResourceChange ? requestedResourceId : (CurrentStation.DefaultResourceId ?? requestedResourceId);

    private int? EffectiveResourceId(int? requestedResourceId) =>
        CurrentStation.AllowResourceChange ? requestedResourceId : (CurrentStation.DefaultResourceId ?? requestedResourceId);

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

    // Prompt 24: dropdown "Penjahit" di modal Buat Bundle/Edit Bundle -- divisi station
    // pertama ber-bundle (mis. Sewing), BUKAN divisi Bundling stasiun ini sendiri (lihat
    // FirstBundleStepDivisionId di SIS_Article_BundleSummary / bundling-summary di bawah).
    [HttpGet("resources/{divisionId:int}")]
    public async Task<IActionResult> GetResourcesByDivision(int divisionId)
    {
        var result = await _resourceService.GetActiveByDivisionAsync(divisionId);
        return Ok(result);
    }

    // Prompt 24: ringkasan per size untuk modal "Buat Bundle" -- juga dipakai memvalidasi
    // divisi token = divisi Bundling artikel ini (BundlingDivisionId).
    [HttpGet("bundling/articles/{articleId:int}/summary")]
    public async Task<IActionResult> GetBundlingSummary(int articleId)
    {
        var summary = await _bundleService.GetSummaryAsync(articleId);
        if (summary.Count == 0) return NotFound();
        if (summary[0].BundlingDivisionId != CurrentStation.DivisionId)
            return BadRequest("Divisi ini tidak memiliki step Bundling untuk artikel ini.");

        return Ok(summary);
    }

    // Prompt 24: "Buat Bundle" dari kartu WIP station Bundling -- @BundlingResourceId =
    // operator sesi (WAJIB), penjahit (TailorResourceId/TailorPersonName) opsional.
    [HttpPost("bundles")]
    public async Task<IActionResult> CreateBundle([FromBody] StationBundleCreateRequest request)
    {
        var operatorResourceId = EffectiveResourceId(request.ResourceId);
        if (operatorResourceId <= 0) return BadRequest("Operator wajib dipilih.");
        if (request.ArticleSizeId <= 0) return BadRequest("Ukuran wajib dipilih.");
        if (request.Qty <= 0) return BadRequest("Qty bundle harus lebih dari 0.");

        var summary = await _bundleService.GetSummaryAsync(request.ArticleId);
        if (summary.Count == 0 || summary[0].BundlingDivisionId != CurrentStation.DivisionId)
            return BadRequest("Divisi ini tidak memiliki step Bundling untuk artikel ini.");

        var (success, error, result) = await _bundleService.CreateAsync(new BundleCreateRequest
        {
            ArticleId = request.ArticleId,
            ArticleSizeId = request.ArticleSizeId,
            Qty = request.Qty,
            ResourceId = request.TailorResourceId,
            ResourcePersonName = request.TailorPersonName,
            BundlingResourceId = operatorResourceId,
            AutoPrint = request.AutoPrint
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok(result);
    }

    // Prompt 24: Edit bundle dari tab OUT station Bundling -- qty tersinkron ke log Bundling
    // lewat SIS_Bundle_Manage (bukan REVISE_HANDOVER generik yang dipakai baris lain).
    [HttpPut("bundles/{id:int}")]
    public async Task<IActionResult> UpdateBundle(int id, [FromBody] StationBundleUpdateRequest request)
    {
        var operatorResourceId = EffectiveResourceId(request.ResourceId);
        if (operatorResourceId <= 0) return BadRequest("Operator wajib dipilih.");
        if (request.Qty <= 0) return BadRequest("Qty bundle harus lebih dari 0.");

        var (success, error) = await _bundleService.UpdateAsync(new BundleUpdateRequest
        {
            Id = id,
            Qty = request.Qty,
            ResourceId = request.TailorResourceId,
            ResourcePersonName = request.TailorPersonName,
            BundlingResourceId = operatorResourceId
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 24: cetak ulang label bundle -- semua station boleh, tanpa batasan divisi, cukup
    // token perangkat valid.
    [HttpPost("bundles/{id:int}/reprint")]
    public async Task<IActionResult> ReprintBundle(int id)
    {
        var (success, error, printJobId) = await _bundleService.ReprintAsync(id, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // Prompt 22b: @ResourceId dari operator sesi (query string, sama pola dengan Scan di
    // bawah) -- filter antrian Masuk/Dikerjakan/Dikirim/Counts ke Line operator ini saja.
    // EffectiveResourceId tetap menang kalau stasiun terkunci (memaksa default_resource_id
    // stasiun, mengabaikan resourceId yang dikirim client).
    [HttpGet("pending-receives")]
    public async Task<IActionResult> GetPendingReceives([FromQuery] int? resourceId)
    {
        var result = await _workflowLogService.GetPendingReceivesAsync(CurrentStation.DivisionId, EffectiveResourceId(resourceId));
        return Ok(result);
    }

    // Baris yang dibuat divisi ini sendiri, sudah punya tujuan serah, tapi belum diterima
    // (received_at IS NULL) -- masih boleh direvisi lewat PUT logs/{id}/revise-handover di
    // bawah. Prompt 12e: ini sumber data tab "Dikirim" (dulu "Menunggu Diserahkan").
    [HttpGet("pending-handover")]
    public async Task<IActionResult> GetPendingHandover([FromQuery] int? resourceId)
    {
        var result = await _workflowLogService.GetPendingHandoverAsync(CurrentStation.DivisionId, EffectiveResourceId(resourceId));
        return Ok(result);
    }

    // Prompt 15: 20 baris terakhir yang diterima divisi ini -- dasar tab "Baru Diterima".
    [HttpGet("recent-received")]
    public async Task<IActionResult> GetRecentReceived([FromQuery] int? resourceId)
    {
        var result = await _workflowLogService.GetRecentReceivedAsync(CurrentStation.DivisionId, EffectiveResourceId(resourceId));
        return Ok(result);
    }

    // Prompt 12e: tab "Dikerjakan" -- bundle sudah diterima divisi ini, belum ada baris
    // step berikutnya. TANPA batasan TOP (beda dengan recent-received di atas).
    [HttpGet("in-progress")]
    public async Task<IActionResult> GetInProgress([FromQuery] int? resourceId)
    {
        var result = await _workflowLogService.GetInProgressAsync(CurrentStation.DivisionId, EffectiveResourceId(resourceId));
        return Ok(result);
    }

    // Prompt 23: kartu permanen (artikel x step non-bundle) di tab WIP, tampil berdampingan
    // dengan kartu bundle di atas. Tanpa resourceId (kartu ini tidak terikat Line).
    [HttpGet("active-work")]
    public async Task<IActionResult> GetActiveWork()
    {
        var result = await _workflowLogService.GetActiveWorkAsync(CurrentStation.DivisionId);
        return Ok(result);
    }

    // Prompt 12e: strip 3 angka besar (Masuk/Dikerjakan/Dikirim) di atas /station.
    [HttpGet("counts")]
    public async Task<IActionResult> GetCounts([FromQuery] int? resourceId)
    {
        var result = await _workflowLogService.GetCountsAsync(CurrentStation.DivisionId, EffectiveResourceId(resourceId));
        return Ok(result);
    }

    // Pintu masuk universal panel Scan Bundle di /station: @ResourceId dari operator sesi
    // (query string, sama seperti currentOperatorId dipakai di receive/complete lain),
    // @DivisionId selalu dari token perangkat.
    [HttpGet("scan/{serial}")]
    public async Task<IActionResult> Scan(string serial, [FromQuery] int? resourceId)
    {
        var result = await _bundleService.GetScanInfoAsync(serial, CurrentStation.DivisionId, EffectiveResourceId(resourceId));
        if (result is null) return NotFound("Bundle tidak ditemukan.");
        return Ok(result);
    }

    // Prompt 14: info kuota qty step ber-bundle ("Masuk / Tercatat / Sisa"), dipakai form
    // COMPLETE/EDIT di BundleScanCard dan modal revisi "Menunggu Diserahkan" sebelum submit.
    [HttpGet("quota-info")]
    public async Task<IActionResult> GetQuotaInfo([FromQuery] int articleWorkflowId, [FromQuery] int bundleId)
    {
        var result = await _workflowLogService.GetQuotaInfoAsync(articleWorkflowId, bundleId);
        if (result is null) return NotFound();
        return Ok(result);
    }

    // Prompt 12b: model log 1-baris -- "menerima" kini UPDATE received_at/received_by
    // pada baris yang sudah ada (workflowLogId), bukan lagi INSERT baris RECEIVED baru.
    [HttpPost("receive")]
    public async Task<IActionResult> Receive([FromBody] StationReceiveRequest request)
    {
        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        var (success, error) = await _workflowLogService.ReceiveAsync(new WorkflowLogReceiveInput
        {
            WorkflowLogId = request.WorkflowLogId,
            ReceivedByResourceId = resourceId,
            ReceivedRemark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId
        });

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Pekerjaan step ber-bundle selesai lewat alur scan (dulu berstatus 'COMPLETED', kini
    // satu-satunya arti INSERT di model log baru). Step non-bundle (mis. Cutting) TIDAK lewat
    // endpoint ini -- lihat POST nonbundle-logs/batch di bawah (kartu WIP terpisah, Prompt 23).
    // BundleId karena itu wajib di sini; SP sendiri sebenarnya masih izinkan BundleId kosong,
    // jadi pesan ini murni penjaga tambahan di API supaya kedua jalur tidak tertukar.
    [HttpPost("complete")]
    public async Task<IActionResult> Complete([FromBody] StationCompleteRequest request)
    {
        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        if (request.BundleId is null)
            return BadRequest("Step tanpa bundle dicatat lewat menu Hasil Cutting.");

        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var (success, error) = await _workflowLogService.CreateAsync(new WorkflowLogCreateInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            BundleId = request.BundleId,
            ArticleSizeId = request.ArticleSizeId,
            ResourceId = resourceId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId,
            ConfirmExceed = request.ConfirmExceed,
            ConfirmShort = request.ConfirmShort
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 23: grid "Kirim Hasil" untuk step non-bundle (mis. Cutting/DTF Print) dari kartu
    // WIP -- pindahan dari WorkflowInputController (dihapus). Satu transaksi (lihat
    // WorkflowLogService.CreateBatchAsync), ResourceId = operator sesi WAJIB (beda dengan
    // /workflow-input dulu yang opsional). Validasi divisi/requires_bundle diserahkan ke
    // SIS_WorkflowLog_Manage lewat ActingDivisionId + BundleId = null (SP menolak kalau step
    // bukan milik divisi token atau butuh bundle) -- lihat sp_WorkflowLog_Manage.sql.
    [HttpPost("nonbundle-logs/batch")]
    public async Task<IActionResult> CreateNonBundleLogBatch([FromBody] StationNonBundleBatchCreateRequest request)
    {
        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        if (request.Entries.Count == 0)
            return BadRequest("Minimal satu baris harus diisi.");

        foreach (var entry in request.Entries)
        {
            if (entry.ArticleSizeId <= 0)
                return BadRequest("Size wajib dipilih.");

            if (entry.QtyOk < 0 || entry.QtyRejectPrint < 0 || entry.QtyRejectFabric < 0 || entry.QtyRejectSewing < 0)
                return BadRequest("Qty tidak boleh negatif.");
        }

        var inputs = request.Entries.Select(entry => new WorkflowLogCreateInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            BundleId = null,
            ArticleSizeId = entry.ArticleSizeId,
            ResourceId = resourceId,
            QtyOk = entry.QtyOk,
            QtyRejectPrint = entry.QtyRejectPrint,
            QtyRejectFabric = entry.QtyRejectFabric,
            QtyRejectSewing = entry.QtyRejectSewing,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId,
            ConfirmExceed = false
        }).ToList();

        var (success, error, failedArticleSizeId) = await _workflowLogService.CreateBatchAsync(inputs, _systemUserId);
        if (!success) return BadRequest(new StationNonBundleBatchResult { Error = error, ArticleSizeId = failedArticleSizeId });
        return Ok();
    }

    // Revisi data sebelum diterima (dipakai divisi pembuat baris, lihat "pending-handover"
    // di atas). Ditolak SP kalau baris sudah diterima (received_at terisi) atau bukan
    // milik divisi ini.
    [HttpPut("logs/{id:int}")]
    public async Task<IActionResult> UpdateLog(int id, [FromBody] StationLogUpdateRequest request)
    {
        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var resourceId = EffectiveResourceId(request.ResourceId);

        var (success, error) = await _workflowLogService.UpdateAsync(new WorkflowLogUpdateInput
        {
            Id = id,
            ArticleSizeId = request.ArticleSizeId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId,
            UpdatedByResourceId = resourceId > 0 ? resourceId : null,
            ConfirmExceed = request.ConfirmExceed,
            ConfirmShort = request.ConfirmShort
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 15: pembatalan penerimaan -- hanya divisi penerima, jendela sempit (belum ada
    // hasil tercatat di step berikutnya). Teruskan pesan error SP apa adanya.
    [HttpPost("logs/{id:int}/unreceive")]
    public async Task<IActionResult> UnreceiveLog(int id, [FromBody] StationUnreceiveRequest request)
    {
        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        var (success, error) = await _workflowLogService.UnreceiveAsync(new WorkflowLogUnreceiveInput
        {
            Id = id,
            ActingDivisionId = CurrentStation.DivisionId,
            UpdatedByResourceId = resourceId
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 12e: "Batal Serah" di tab Dikirim -- soft delete baris serah yang salah,
    // hanya selama divisi tujuan belum menerima.
    [HttpPost("logs/{id:int}/cancel-handover")]
    public async Task<IActionResult> CancelHandover(int id, [FromBody] StationCancelHandoverRequest request)
    {
        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        var (success, error) = await _workflowLogService.CancelHandoverAsync(id, CurrentStation.DivisionId, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 12e: "Revisi" di tab Dikirim -- boleh ubah qty, divisi tujuan, dan penjahit
    // selama divisi tujuan belum menerima.
    [HttpPut("logs/{id:int}/revise-handover")]
    public async Task<IActionResult> ReviseHandover(int id, [FromBody] StationReviseHandoverRequest request)
    {
        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        request.ResourceId = resourceId;
        if (request.NewResourceId.HasValue)
            request.NewResourceId = EffectiveResourceId(request.NewResourceId);

        var (success, error) = await _workflowLogService.ReviseHandoverAsync(id, request, CurrentStation.DivisionId, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }
}
