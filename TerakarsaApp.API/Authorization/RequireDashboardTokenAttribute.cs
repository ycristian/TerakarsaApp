using System.Collections.Concurrent;
using Microsoft.AspNetCore.Mvc.Filters;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Authorization;

// Autentikasi kiosk TV lewat header X-Dashboard-Token, TANPA JWT -- pola sama dengan
// RequireStationTokenAttribute. TOUCH (last_seen_at) di-throttle di memori proses (per
// token, minimal 2 menit antar TOUCH) supaya tidak menulis ke DB tiap request meski TV
// refresh tiap 5 menit.
public class RequireDashboardTokenAttribute : Attribute, IAsyncAuthorizationFilter
{
    public const string HttpContextItemKey = "DashboardToken";

    private static readonly TimeSpan TouchThrottle = TimeSpan.FromMinutes(2);
    private static readonly ConcurrentDictionary<string, DateTime> LastTouchedAt = new();

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var token = context.HttpContext.Request.Headers["X-Dashboard-Token"].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(token))
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        var dashboardTokenService = context.HttpContext.RequestServices.GetRequiredService<DashboardTokenService>();
        var auth = await dashboardTokenService.GetByTokenAsync(token);
        if (auth is null)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        context.HttpContext.Items[HttpContextItemKey] = auth;

        var now = DateTime.UtcNow;
        if (!LastTouchedAt.TryGetValue(token, out var last) || now - last >= TouchThrottle)
        {
            LastTouchedAt[token] = now;
            await dashboardTokenService.TouchAsync(token);
        }
    }
}
