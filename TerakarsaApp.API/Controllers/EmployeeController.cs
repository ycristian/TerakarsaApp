using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Employees;

namespace TerakarsaApp.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
[RequireModule("MASTER_EMPLOYEE")]
public class EmployeeController : ControllerBase
{
    private readonly EmployeeService _employeeService;

    public EmployeeController(EmployeeService employeeService)
    {
        _employeeService = employeeService;
    }

    private int CurrentUserId => int.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);

    [HttpPost("paged")]
    public async Task<IActionResult> GetPaged([FromBody] EmployeePagedRequest request)
    {
        var result = await _employeeService.GetPagedAsync(request);
        return Ok(result);
    }

    [HttpGet("active")]
    public async Task<IActionResult> GetActive()
    {
        var result = await _employeeService.GetActiveAsync();
        return Ok(result);
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var employee = await _employeeService.GetByIdAsync(id);
        if (employee is null) return NotFound();
        return Ok(employee);
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

        var (success, error) = await _employeeService.CreateAsync(request, CurrentUserId);
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

        var (success, error) = await _employeeService.UpdateAsync(request, CurrentUserId);
        if (!success) return BadRequest(error);
        return Ok();
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _employeeService.DeleteAsync(id, CurrentUserId);
        return Ok();
    }

    // Prompt 53: toggle Aktifkan/Nonaktifkan.
    [HttpPatch("active")]
    public async Task<IActionResult> SetActive([FromBody] EmployeeSetActiveRequest request)
    {
        await _employeeService.SetActiveAsync(request.Id, request.IsActive, CurrentUserId);
        return Ok();
    }

    // Prompt 53: saran kode karyawan otomatis {division_code}-{4 digit}.
    [HttpGet("next-code")]
    public async Task<IActionResult> GetNextCode([FromQuery] int divisionId)
    {
        var code = await _employeeService.GetNextCodeAsync(divisionId);
        return Ok(new EmployeeNextCodeDto { SuggestedCode = code });
    }
}
