using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Services;

namespace TerakarsaApp.API.Authorization;

// Prompt 77: PrintController sekarang bisa dipakai DUA jenis pencetak:
//
//   X-Print-Api-Key      -> TerakarsaApp.PrintService (Windows). JALUR LAMA, tidak
//                           berubah: satu kunci untuk seluruh service.
//   X-Print-Device-Token -> satu HP (app Terakarsa, printer Bluetooth). Token dicocokkan
//                           ke print_devices.device_token yang aktif; id device-nya
//                           disimpan di HttpContext.Items agar controller bisa membatasi
//                           klaim/lapor ke job yang dirutekan ke device itu.
//
// Keduanya TIDAK BOLEH dikirim bersamaan -- kalau ada dua-duanya, request ditolak
// supaya tidak ada jalan pintas naik hak akses.
//
// RequirePrintApiKeyAttribute lama DIBIARKAN ada (tidak dihapus) untuk endpoint lain
// yang mungkin memakainya.
public class RequirePrintAuthAttribute : Attribute, IAsyncAuthorizationFilter
{
    public const string DeviceIdItemKey = "PrintDeviceId";

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var apiKey = context.HttpContext.Request.Headers["X-Print-Api-Key"].FirstOrDefault();
        var deviceToken = context.HttpContext.Request.Headers["X-Print-Device-Token"].FirstOrDefault();

        var adaApiKey = !string.IsNullOrWhiteSpace(apiKey);
        var adaToken = !string.IsNullOrWhiteSpace(deviceToken);

        if (adaApiKey == adaToken)
        {
            // dua-duanya ada, atau dua-duanya tidak ada
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        if (adaApiKey)
        {
            var options = context.HttpContext.RequestServices
                .GetRequiredService<IOptions<PrintServiceOptions>>();
            var expectedKey = options.Value.ApiKey;

            if (string.IsNullOrEmpty(expectedKey) || apiKey != expectedKey)
                context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();

            return;
        }

        // Token device HP: tukar jadi print_device_id (sekaligus mencatat last_seen_at).
        var deviceService = context.HttpContext.RequestServices.GetRequiredService<PrintDeviceService>();
        var info = context.HttpContext.Request.Headers["X-Print-Device-Info"].FirstOrDefault();

        var deviceId = await deviceService.ResolveTokenAsync(deviceToken!, info);

        if (deviceId is null)
        {
            context.Result = new Microsoft.AspNetCore.Mvc.UnauthorizedResult();
            return;
        }

        context.HttpContext.Items[DeviceIdItemKey] = deviceId.Value;
    }
}

public static class PrintAuthExtensions
{
    // null = jalur API key (PrintService Windows) -- SP dipanggil tanpa @DeviceId,
    // persis seperti sebelum Prompt 77.
    public static int? PrintDeviceId(this Microsoft.AspNetCore.Mvc.ControllerBase controller) =>
        controller.HttpContext.Items.TryGetValue(RequirePrintAuthAttribute.DeviceIdItemKey, out var nilai)
            && nilai is int id
            ? id
            : null;
}
