using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Bundles;
using TerakarsaApp.Shared.Packs;
using TerakarsaApp.Shared.Projects;
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
    private readonly EmployeeService _employeeService;
    private readonly PackService _packService;
    private readonly ProjectService _projectService;
    private readonly ArticlePhotoService _articlePhotoService;
    private readonly RekapProduksiService _rekapProduksiService;
    private readonly DivisionService _divisionService;
    private readonly int _systemUserId;

    public StationDeviceController(
        WorkflowLogService workflowLogService,
        ResourceService resourceService,
        BundleService bundleService,
        EmployeeService employeeService,
        PackService packService,
        ProjectService projectService,
        ArticlePhotoService articlePhotoService,
        RekapProduksiService rekapProduksiService,
        DivisionService divisionService,
        IOptions<StationOptions> stationOptions)
    {
        _workflowLogService = workflowLogService;
        _resourceService = resourceService;
        _bundleService = bundleService;
        _employeeService = employeeService;
        _packService = packService;
        _projectService = projectService;
        _articlePhotoService = articlePhotoService;
        _rekapProduksiService = rekapProduksiService;
        _divisionService = divisionService;
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

    // Prompt 32: dropdown "Penjahit" (employee) cascading di bawah dropdown Line (TailorResourceId)
    // di modal Buat Bundle/Edit Bundle -- menggantikan input teks bebas.
    [HttpGet("employees/{resourceId:int}")]
    public async Task<IActionResult> GetEmployeesByResource(int resourceId)
    {
        var result = await _employeeService.GetActiveByResourceAsync(resourceId);
        return Ok(result);
    }

    // Prompt 42: dropdown "Divisi" (level pertama) di tab Rekap Produksi -- reuse
    // DivisionService.GetActiveAsync (dipakai juga oleh /reports/produksi admin), client cukup
    // ambil Id + DivisionName. Resource (per divisi) dan Penjahit (per resource) pakai endpoint
    // cascading yang sudah ada di atas (resources/{divisionId}, employees/{resourceId}).
    [HttpGet("divisions")]
    public async Task<IActionResult> GetStationDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    // Prompt 42: tab "Rekap Produksi" -- header (nama divisi/resource/penjahit sesuai level,
    // rentang periode gajian, total pcs) + detail harian + WIP snapshot. Level = pilihan
    // terdalam yang diisi client (DIVISION | RESOURCE | EMPLOYEE).
    [HttpGet("rekap-struk")]
    public async Task<IActionResult> GetRekapStruk(
        [FromQuery] string level, [FromQuery] int divisionId, [FromQuery] int? resourceId,
        [FromQuery] int? employeeId, [FromQuery] DateTime? date)
    {
        var result = await _rekapProduksiService.GetAsync(level, divisionId, resourceId, employeeId, date);
        if (result.Header is null) return NotFound("Divisi tidak ditemukan.");
        return Ok(result);
    }

    // Prompt 42: "Cetak Struk" di tab Rekap Produksi -- snapshot ULANG di SP (bukan payload
    // dari client) lalu insert print_jobs job_type REKAP_PRODUKSI.
    [HttpPost("rekap-struk/print")]
    public async Task<IActionResult> PrintRekapStruk([FromBody] RekapStrukPrintRequest request)
    {
        var (success, error, printJobId) = await _rekapProduksiService.PrintAsync(request, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
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
    // operator sesi (WAJIB), penjahit (TailorResourceId/TailorEmployeeId) opsional.
    [HttpPost("bundles")]
    public async Task<IActionResult> CreateBundle([FromBody] StationBundleCreateRequest request)
    {
        var operatorResourceId = EffectiveResourceId(request.ResourceId);
        if (operatorResourceId <= 0) return BadRequest("Operator wajib dipilih.");
        if (request.ArticleSizeId <= 0) return BadRequest("Ukuran wajib dipilih.");
        if (request.Qty <= 0) return BadRequest("Qty bundle harus lebih dari 0.");
        if (request.PrintCopies < 0) return BadRequest("Jumlah label tidak boleh negatif.");

        var summary = await _bundleService.GetSummaryAsync(request.ArticleId);
        if (summary.Count == 0 || summary[0].BundlingDivisionId != CurrentStation.DivisionId)
            return BadRequest("Divisi ini tidak memiliki step Bundling untuk artikel ini.");

        // Fix: qty tidak boleh melebihi Stock Cutting (sisa hasil Cutting yang sudah diterima
        // divisi Bundling tapi belum dijadikan bundle) -- lihat SIS_Article_BundleSummary.
        var sizeInfo = summary.FirstOrDefault(s => s.ArticleSizeId == request.ArticleSizeId);
        if (sizeInfo is not null && request.Qty > sizeInfo.StockCutting)
            return BadRequest($"Qty tidak boleh lebih dari Stock Cutting ({sizeInfo.StockCutting}).");

        var (success, error, result) = await _bundleService.CreateAsync(new BundleCreateRequest
        {
            ArticleId = request.ArticleId,
            ArticleSizeId = request.ArticleSizeId,
            Qty = request.Qty,
            ResourceId = request.TailorResourceId,
            EmployeeId = request.TailorEmployeeId,
            BundlingResourceId = operatorResourceId,
            PrintCopies = request.PrintCopies,
            Remarks = request.Remarks
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
        if (request.ArticleSizeId <= 0) return BadRequest("Ukuran wajib dipilih.");
        if (request.Qty <= 0) return BadRequest("Qty bundle harus lebih dari 0.");

        var (success, error) = await _bundleService.UpdateAsync(new BundleUpdateRequest
        {
            Id = id,
            Qty = request.Qty,
            ArticleSizeId = request.ArticleSizeId,
            ResourceId = request.TailorResourceId,
            EmployeeId = request.TailorEmployeeId,
            BundlingResourceId = operatorResourceId,
            Remarks = request.Remarks
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Fix: "Hapus" bundle dari tab OUT station Bundling -- dipakai untuk baris yang sudah
    // received_at (auto-diterima Line tujuan saat dibuat) tapi masih WIP murni & dalam
    // jendela 1 jam (lihat SIS_Station_PendingHandover/SIS_Bundle_Manage DELETE). SP sendiri
    // yang menegakkan aturan waktu/status -- endpoint ini cukup teruskan error apa adanya.
    [HttpDelete("bundles/{id:int}")]
    public async Task<IActionResult> DeleteBundle(int id)
    {
        var (success, error) = await _bundleService.DeleteAsync(id, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 24: cetak ulang label bundle -- semua station boleh, tanpa batasan divisi, cukup
    // token perangkat valid. Fix: @copies (default 1) -- jumlah label yang dicetak, diisi user
    // lewat modal konfirmasi Cetak Ulang.
    [HttpPost("bundles/{id:int}/reprint")]
    public async Task<IActionResult> ReprintBundle(int id, [FromQuery] int copies = 1)
    {
        if (copies < 1) return BadRequest("Jumlah label harus minimal 1.");

        var (success, error, printJobId) = await _bundleService.ReprintAsync(id, copies, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // Prompt: "Print Label Cacat" -- popup di BundleScanCard setelah Kirim Hasil dengan
    // reject > 0. Copies = jumlah lembar, semua station boleh (sama seperti reprint di atas).
    [HttpPost("bundles/{id:int}/print-defect-label")]
    public async Task<IActionResult> PrintDefectLabel(int id, [FromBody] BundlePrintDefectLabelRequest request)
    {
        if (request.Copies < 1) return BadRequest("Jumlah label harus minimal 1.");

        var (success, error, printJobId) = await _bundleService.PrintDefectLabelAsync(id, request.Copies, request.Remark, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // Fix: "Cetak Reject" -- nota reject untuk satu baris log timeline (BundleScanCard),
    // tombol client hanya tampil kalau baris itu punya reject > 0 (SP menegakkan ulang).
    // Semua station boleh, sama seperti reprint label bundle di atas.
    [HttpPost("logs/{id:int}/print-reject")]
    public async Task<IActionResult> PrintReject(int id, [FromQuery] int copies = 1)
    {
        if (copies < 1) return BadRequest("Jumlah label harus minimal 1.");

        var (success, error, printJobId) = await _workflowLogService.PrintRejectAsync(id, copies, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    // Prompt 41 (lanjutan): "Print Hasil" -- cetak kupon manual segera setelah Kirim Hasil,
    // tanpa menunggu divisi berikutnya menerima. Sama pola dengan print-reject di atas.
    [HttpPost("logs/{id:int}/print-hasil")]
    public async Task<IActionResult> PrintHasil(int id)
    {
        var (success, error, printJobId) = await _workflowLogService.PrintHasilAsync(id, _systemUserId);
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

    // Fix: foto utama artikel untuk kartu "Buat Bundle" di tab WIP -- setara
    // api/article-photos/{articleId}/primary (ArticlePhotoController) tapi lewat token
    // stasiun, bukan JWT, supaya bisa dipanggil dari /station tanpa login.
    [HttpGet("articles/{articleId:int}/photo")]
    public async Task<IActionResult> GetArticlePhoto(int articleId)
    {
        var result = await _articlePhotoService.GetPrimaryPhotoForDownloadAsync(articleId);
        if (result is null) return NotFound();

        var (stream, contentType, fileName) = result.Value;
        return File(stream, contentType, fileName);
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
        }, _systemUserId);

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
            || request.QtyRejectSewing < 0 || request.QtyRejectRework < 0 || request.QtyLost < 0)
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
            QtyRejectRework = request.QtyRejectRework,
            QtyLost = request.QtyLost,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId,
            ConfirmExceed = request.ConfirmExceed,
            ConfirmShort = request.ConfirmShort,
            ActingAllowResourceChange = CurrentStation.AllowResourceChange,
            // Prompt 40: penerima manual dipilih operator pengirim -- diteruskan apa adanya,
            // SP satu-satunya penjaga (hanya dipakai kalau step tujuan auto_receive = 1 dan
            // counterpart pengirim tidak valid).
            AutoReceiveResourceId = request.AutoReceiveResourceId
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 40: dropdown "Diterima Oleh ({divisi tujuan})" wajib di form Kirim Hasil ketika
    // ReceiverPickerRequired = true (lihat SIS_Bundle_ScanInfo).
    [HttpGet("receiver-options")]
    public async Task<IActionResult> GetReceiverOptions([FromQuery] int articleWorkflowId, [FromQuery] int? bundleId)
    {
        var result = await _workflowLogService.GetReceiverOptionsAsync(articleWorkflowId, bundleId);
        return Ok(result);
    }

    // Prompt 28: panel Penyesuaian di /b/{serial} -- mutasi qty reject/hilang -> reject/hilang
    // lain ATAU Qty OK (BundleScanCard). Hanya divisi pemilik step (ActingDivisionId dari
    // token) yang boleh menyesuaikan -- ditegakkan ulang di SIS_WorkflowLog_Manage.
    [HttpPost("adjust")]
    public async Task<IActionResult> Adjust([FromBody] StationAdjustRequest request)
    {
        var resourceId = EffectiveResourceId(request.ResourceId);
        if (resourceId <= 0) return BadRequest("Operator wajib dipilih.");

        var (success, error) = await _workflowLogService.AdjustAsync(new WorkflowLogAdjustInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            BundleId = request.BundleId,
            ResourceId = resourceId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            QtyRejectRework = request.QtyRejectRework,
            QtyLost = request.QtyLost,
            TargetDivisionId = request.TargetDivisionId,
            Remark = request.Remark,
            ActingDivisionId = CurrentStation.DivisionId
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

            if (entry.QtyOk < 0 || entry.QtyRejectPrint < 0 || entry.QtyRejectFabric < 0 || entry.QtyRejectSewing < 0
                || entry.QtyRejectRework < 0 || entry.QtyLost < 0)
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
            QtyRejectRework = entry.QtyRejectRework,
            QtyLost = entry.QtyLost,
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
            || request.QtyRejectSewing < 0 || request.QtyRejectRework < 0 || request.QtyLost < 0)
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
            QtyRejectRework = request.QtyRejectRework,
            QtyLost = request.QtyLost,
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
            || request.QtyRejectSewing < 0 || request.QtyRejectRework < 0 || request.QtyLost < 0)
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

    // Prompt 25: modul Packing -- hanya stasiun dengan enable_packing yang boleh membuka
    // tab "Packing"/memanggil endpoint ini (lihat SIS_Station_GetByToken + StationMeDto).
    private IActionResult? RequirePackingEnabled() =>
        CurrentStation.EnablePacking ? null : StatusCode(403, "Modul packing tidak aktif untuk stasiun ini.");

    [HttpGet("packing/projects")]
    public async Task<IActionResult> GetPackingProjects()
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        var result = await _projectService.GetPagedAsync(new ProjectPagedRequest
        {
            PageNumber = 1,
            PageSize = 500,
            SortColumn = "CreatedAt",
            SortDirection = "desc"
        });
        return Ok(result.Items);
    }

    [HttpGet("packing/stock/{projectId:int}")]
    public async Task<IActionResult> GetPackingStock(int projectId)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        var result = await _packService.GetStockAvailableAsync(projectId);
        return Ok(result);
    }

    [HttpGet("packing/packs/{projectId:int}")]
    public async Task<IActionResult> GetPackingPacks(int projectId)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        var result = await _packService.GetProjectPackingAsync(projectId);
        return Ok(result);
    }

    [HttpPost("packing/packs")]
    public async Task<IActionResult> CreatePack([FromBody] PackCreateRequest request)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        if (request.Items.Count == 0)
            return BadRequest("Karung harus berisi minimal 1 item.");

        var (success, error, result) = await _packService.CreateAsync(request, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(result);
    }

    [HttpPut("packing/packs/{id:int}/plan")]
    public async Task<IActionResult> UpdatePackPlan(int id, [FromBody] PackUpdatePlanRequest request)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        if (request.Items.Count == 0)
            return BadRequest("Karung harus berisi minimal 1 item.");

        var (success, error) = await _packService.UpdatePlanAsync(id, request, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut("packing/packs/{id:int}/confirm")]
    public async Task<IActionResult> ConfirmPack(int id, [FromBody] PackConfirmRequest request)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        if (request.Items.Count == 0)
            return BadRequest("Minimal satu item harus dikonfirmasi.");

        var (success, error) = await _packService.ConfirmAsync(id, request, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("packing/packs/{id:int}/reprint")]
    public async Task<IActionResult> ReprintPack(int id, [FromQuery] int copies = 1)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;
        if (copies < 1) return BadRequest("Jumlah label harus minimal 1.");

        var (success, error, printJobId) = await _packService.ReprintAsync(id, copies, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok(new { PrintJobId = printJobId });
    }

    [HttpDelete("packing/packs/{id:int}")]
    public async Task<IActionResult> DeletePack(int id, [FromQuery] string? reason)
    {
        var forbid = RequirePackingEnabled();
        if (forbid is not null) return forbid;

        if (string.IsNullOrWhiteSpace(reason))
            return BadRequest("Alasan hapus karung wajib diisi.");

        var (success, error) = await _packService.DeleteAsync(id, reason, _systemUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    // Prompt 25: panel scan QR karung di /station (sama pola dengan scan/{serial} bundle
    // di atas), operator sesi tidak relevan untuk packing (read-only, tanpa aksi lanjutan).
    [HttpGet("packing/scan/{serial}")]
    public async Task<IActionResult> ScanPack(string serial)
    {
        var result = await _packService.GetScanInfoAsync(serial);
        if (result is null) return NotFound("Karung tidak ditemukan.");
        return Ok(result);
    }
}
