using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Authorization;

// Otorisasi PERANGKAT modul PDH TNI AD lewat header X-Tni-Token, TANPA JWT --
// alurnya sama dengan RequireStationTokenAttribute, tapi memakai tabel
// tni.perangkat (terpisah dari `stations`: tidak terikat divisi/resource).
//
// 2026-10-06 (alter_75): TIDAK ADA lagi pemilihan petugas. Setiap perangkat
// punya SATU nama petugas; jejak kerja menyimpan perangkat_id pemegang token,
// dan nama yang tampil dibaca dari perangkat.nama_petugas. created_by tetap
// user sistem `tni_system` (Tni:SystemUserId).
public class RequireTniDeviceTokenAttribute : Attribute, IAsyncAuthorizationFilter
{
    public const string HttpContextItemKey = "TniPerangkat";
    public const string SystemUserItemKey = "TniSystemUserId";

    public const string TokenHeader = "X-Tni-Token";

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var token = context.HttpContext.Request.Headers[TokenHeader].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(token))
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        var service = context.HttpContext.RequestServices.GetRequiredService<TniPerangkatService>();
        var perangkat = await service.GetByTokenAsync(token);
        if (perangkat is null)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        context.HttpContext.Items[HttpContextItemKey] = perangkat;

        // created_by untuk request tanpa login -- dibaca lewat TniActorUserId().
        var opts = context.HttpContext.RequestServices
            .GetRequiredService<IOptions<TniOptions>>().Value;
        context.HttpContext.Items[SystemUserItemKey] = opts.SystemUserId;
    }
}
