using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Authorization;

// Autentikasi TerakarsaApp.PrintService (Windows Worker Service) lewat header
// X-Print-Api-Key, dicocokkan terhadap PrintService:ApiKey di appsettings API.
// Terpisah dari JWT (user) dan X-Station-Token (RequireStationTokenAttribute).
public class RequirePrintApiKeyAttribute : Attribute, IAuthorizationFilter
{
    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var apiKey = context.HttpContext.Request.Headers["X-Print-Api-Key"].FirstOrDefault();
        var options = context.HttpContext.RequestServices.GetRequiredService<IOptions<PrintServiceOptions>>();
        var expectedKey = options.Value.ApiKey;

        if (string.IsNullOrEmpty(expectedKey) || string.IsNullOrEmpty(apiKey) || apiKey != expectedKey)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
        }
    }
}
