using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Authorization;

// Pembaca identitas aktor modul PDH TNI AD, dipakai semua controller api/tni/*.
//
// Dibuat sebagai extension (bukan base class) supaya sepuluh controller yang
// sudah ada tidak perlu ubah constructor.
//
//   TniActorUserId  -> pengisi created_by. SELALU user id: dari JWT bila
//                      request datang dari user login, kalau tidak user
//                      sistem `tni_system` (Tni:SystemUserId) yang
//                      distash oleh RequireTniDeviceTokenAttribute.
//   TniPerangkatId  -> perangkat pemegang token, masuk ke kolom *_perangkat_id.
//                      Nama petugasnya = perangkat.nama_petugas (alter_75).
//                      BUKAN pengganti created_by.
public static class TniActorExtensions
{
    public static int TniActorUserId(this ControllerBase c)
    {
        var claim = c.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (int.TryParse(claim, out var id) && id > 0) return id;

        return c.HttpContext.Items.TryGetValue(
                   RequireTniDeviceTokenAttribute.SystemUserItemKey, out var v) && v is int sys
            ? sys
            : 0;
    }

    public static int? TniPerangkatId(this ControllerBase c) => c.TniPerangkat()?.PerangkatId;

    public static TniPerangkatMeDto? TniPerangkat(this ControllerBase c)
        => c.HttpContext.Items.TryGetValue(
               RequireTniDeviceTokenAttribute.HttpContextItemKey, out var v)
            ? v as TniPerangkatMeDto
            : null;
}
