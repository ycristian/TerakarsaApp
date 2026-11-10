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

        // alter_87: divisi pilihan sesi (stasiun allow_all_divisions). Divalidasi di SP;
        // tanpa header / stasiun biasa = divisi stasiun seperti sebelumnya.
        int? divisionId = int.TryParse(context.HttpContext.Request.Headers["X-Station-Division"].FirstOrDefault(), out var d) && d > 0
            ? d : null;

        var stationService = context.HttpContext.RequestServices.GetRequiredService<StationService>();
        var station = await stationService.GetByTokenAsync(token, divisionId);
        if (station is null)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        context.HttpContext.Items[HttpContextItemKey] = station;

        // Prompt 85: catat kehadiran perangkat (last_seen_at) + adopsi perangkat lama, maks
        // 1x/menit/stasiun. Header perangkat boleh tidak ada (client lama). Gagal di sini tidak
        // boleh menggagalkan request stasiun.
        var tracker = context.HttpContext.RequestServices.GetRequiredService<StationPresenceTracker>();
        if (tracker.ShouldTouch(station.StationId))
        {
            var headers = context.HttpContext.Request.Headers;
            var deviceId = StationDeviceIdentity.CleanId(headers["X-Station-Device-Id"].FirstOrDefault());
            var deviceName = StationDeviceIdentity.CleanHeaderName(headers["X-Station-Device-Name"].FirstOrDefault());

            try
            {
                await stationService.TouchAsync(station.StationId, deviceId, deviceName);
            }
            catch (Exception ex)
            {
                var logger = context.HttpContext.RequestServices.GetRequiredService<ILogger<RequireStationTokenAttribute>>();
                logger.LogWarning(ex, "TOUCH stasiun {StationId} gagal.", station.StationId);
            }
        }
    }
}
