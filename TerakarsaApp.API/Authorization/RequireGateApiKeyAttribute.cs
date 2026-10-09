using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Authorization;

// Prompt 70: autentikasi TerakarsaApp.GateApp (aplikasi tablet di meja satpam) lewat header
// X-Gate-Api-Key, dicocokkan terhadap GateService:ApiKey di appsettings API.
// Terpisah dari JWT (user), X-Station-Token (RequireStationTokenAttribute) dan X-Print-Api-Key
// (RequirePrintApiKeyAttribute) -- aplikasi gate memang tanpa login, dan akses menu satpam di
// dalamnya ditentukan jabatan kartu (positions.is_gate_operator), bukan oleh key ini.
public class RequireGateApiKeyAttribute : Attribute, IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var apiKey = context.HttpContext.Request.Headers["X-Gate-Api-Key"].FirstOrDefault();
        var options = context.HttpContext.RequestServices.GetRequiredService<IOptions<GateServiceOptions>>();
        var expectedKey = options.Value.ApiKey;

        if (string.IsNullOrEmpty(expectedKey) || string.IsNullOrEmpty(apiKey) || apiKey != expectedKey)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
        }
    }
}
