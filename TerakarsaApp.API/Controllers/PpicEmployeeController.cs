using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Employees;

namespace TerakarsaApp.API.Controllers;

// Prompt 53: module PPIC Karyawan -- pintu masuk MANDIRI (module/controller/SP terpisah dari
// MASTER_EMPLOYEE), pola sama dengan SuperAdminController. Guard cakupan PPIC (ppic_managed)
// ditegakkan di SP (SIS_PpicEmployee_Manage/SIS_PpicEmployee_Select), bukan hanya di sini.
[ApiController]
[Route("api/ppic-employee")]
[Authorize]
[RequireModule("PPIC_EMPLOYEE")]
public class PpicEmployeeController : ControllerBase
{
    private readonly PpicEmployeeService _ppicEmployeeService;

    public PpicEmployeeController(PpicEmployeeService ppicEmployeeService)
    {
        _ppicEmployeeService = ppicEmployeeService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] EmployeePagedRequest request)
    {
        var result = await _ppicEmployeeService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var employee = await _ppicEmployeeService.GetByIdAsync(id);
        if (employee is null) return NotFound();
        return Ok(employee);
    }

    [HttpGet("divisions")]
    public async Task<IActionResult> GetDivisions()
    {
        var result = await _ppicEmployeeService.GetPpicManagedDivisionsAsync();
        return Ok(result);
    }

    // Dropdown Jabatan & Line/Resource -- proxy ke PositionService/ResourceService supaya user
    // PPIC_EMPLOYEE-only (tanpa module MASTER_POSITION/MASTER_RESOURCE) tetap bisa isi form.
    [HttpGet("positions")]
    public async Task<IActionResult> GetPositions()
    {
        var result = await _ppicEmployeeService.GetPositionsAsync();
        return Ok(result);
    }

    [HttpGet("resources/{divisionId:int}")]
    public async Task<IActionResult> GetResourcesByDivision(int divisionId)
    {
        var result = await _ppicEmployeeService.GetResourcesByDivisionAsync(divisionId);
        return Ok(result);
    }

    [HttpGet("next-code")]
    public async Task<IActionResult> GetNextCode([FromQuery] int divisionId)
    {
        var code = await _ppicEmployeeService.GetNextCodeAsync(divisionId);
        return Ok(new EmployeeNextCodeDto { SuggestedCode = code });
    }

    [HttpPost]
    public async Task<IActionResult> Create([FromBody] EmployeeCreateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EmployeeName))
            return BadRequest("Nama karyawan wajib diisi.");

        if (request.DivisionId <= 0)
            return BadRequest("Divisi wajib dipilih.");

        if (request.PositionId <= 0)
            return BadRequest("Jabatan wajib dipilih.");

        var (success, error) = await _ppicEmployeeService.CreateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPut]
    public async Task<IActionResult> Update([FromBody] EmployeeUpdateRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EmployeeName))
            return BadRequest("Nama karyawan wajib diisi.");

        if (request.DivisionId <= 0)
            return BadRequest("Divisi wajib dipilih.");

        if (request.PositionId <= 0)
            return BadRequest("Jabatan wajib dipilih.");

        var (success, error) = await _ppicEmployeeService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        var (success, error) = await _ppicEmployeeService.DeleteAsync(id, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpPatch("active")]
    public async Task<IActionResult> SetActive([FromBody] EmployeeSetActiveRequest request)
    {
        var (success, error) = await _ppicEmployeeService.SetActiveAsync(request.Id, request.IsActive, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }
}
