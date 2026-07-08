using Microsoft.AspNetCore.Mvc.Filters;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Authorization;

// Autentikasi perangkat stasiun lewat header X-Station-Token, TANPA JWT.
// Dipakai untuk endpoint yang diakses langsung dari tablet/HP di lantai produksi.
public class RequireStationTokenAttribute : Attribute, IAsyncAuthorizationFilter
{
    public const string HttpContextItemKey = "Station";

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var token = context.HttpContext.Request.Headers["X-Station-Token"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(token))
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        var stationService = context.HttpContext.RequestServices.GetRequiredService<StationService>();
        var station = await stationService.GetByTokenAsync(token);
        if (station is null)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        context.HttpContext.Items[HttpContextItemKey] = station;
    }
}
