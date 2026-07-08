using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
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
    private readonly DivisionService _divisionService;
    private readonly int _systemUserId;

    public StationDeviceController(
        WorkflowLogService workflowLogService,
        ResourceService resourceService,
        DivisionService divisionService,
        IOptions<StationOptions> stationOptions)
    {
        _workflowLogService = workflowLogService;
        _resourceService = resourceService;
        _divisionService = divisionService;
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

    [HttpGet("active-work")]
    public async Task<IActionResult> GetActiveWork()
    {
        var result = await _workflowLogService.GetActiveWorkAsync(CurrentStation.DivisionId);
        return Ok(result);
    }

    [HttpGet("target-divisions")]
    public async Task<IActionResult> GetTargetDivisions()
    {
        var result = await _divisionService.GetActiveAsync();
        return Ok(result);
    }

    [HttpPost("receive")]
    public async Task<IActionResult> Receive([FromBody] StationReceiveRequest request)
    {
        if (request.ResourceId <= 0) return BadRequest("Operator wajib dipilih.");

        var (success, error) = await _workflowLogService.CreateAsync(new WorkflowLogCreateInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            ResourceId = request.ResourceId,
            Remark = request.Remark,
            Status = "RECEIVED"
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPost("complete")]
    public async Task<IActionResult> Complete([FromBody] StationCompleteRequest request)
    {
        if (request.ResourceId <= 0) return BadRequest("Operator wajib dipilih.");

        if (request.QtyOk < 0 || request.QtyRejectPrint < 0 || request.QtyRejectFabric < 0
            || request.QtyRejectSewing < 0 || request.QtyRework < 0)
            return BadRequest("Qty tidak boleh negatif.");

        var (success, error) = await _workflowLogService.CreateAsync(new WorkflowLogCreateInput
        {
            ArticleWorkflowId = request.ArticleWorkflowId,
            ResourceId = request.ResourceId,
            QtyOk = request.QtyOk,
            QtyRejectPrint = request.QtyRejectPrint,
            QtyRejectFabric = request.QtyRejectFabric,
            QtyRejectSewing = request.QtyRejectSewing,
            QtyRework = request.QtyRework,
            TargetDivisionId = request.TargetDivisionId,
            Remark = request.Remark,
            Status = "COMPLETED"
        }, _systemUserId);

        if (!success) return BadRequest(error);
        return Ok();
    }
}
