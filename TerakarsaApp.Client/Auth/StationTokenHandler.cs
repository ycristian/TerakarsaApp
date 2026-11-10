using System.Net;
using Microsoft.JSInterop;

namespace TerakarsaApp.Client.Auth;

// Menyertakan header X-Station-Token (token perangkat, disimpan di localStorage)
// pada semua request lewat HttpClient milik StationDeviceApiService. TIDAK memakai
// JWT sama sekali — beda alur dari AuthorizedHandler.
public class StationTokenHandler : DelegatingHandler
{
    public const string TokenKey = "stationToken";
    // alter_87: divisi pilihan sesi untuk stasiun "semua divisi" (dikirim sebagai
    // X-Station-Division). Server mengabaikannya untuk stasiun biasa.
    public const string DivisionKey = "stationDivisionId";
    // Prompt 85: identitas perangkat -- dibuat /station (browser) atau disuntik app Android.
    // Dikirim sebagai X-Station-Device-Id/-Name; server memakainya untuk last_seen_at dan
    // mengadopsi perangkat yang login sebelum alter_88.
    public const string DeviceIdKey = "stationDeviceId";
    public const string DeviceNameKey = "stationDeviceName";

    private readonly IJSRuntime _js;
    private readonly StationAuthNotifier _notifier;

    public StationTokenHandler(IJSRuntime js, StationAuthNotifier notifier)
    {
        _js = js;
        _notifier = notifier;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await _js.InvokeAsync<string?>("localStorage.getItem", TokenKey);
        var hasToken = !string.IsNullOrWhiteSpace(token);
        if (hasToken)
        {
            request.Headers.Add("X-Station-Token", token);

            var divisionId = await _js.InvokeAsync<string?>("localStorage.getItem", DivisionKey);
            if (!string.IsNullOrWhiteSpace(divisionId))
                request.Headers.Add("X-Station-Division", divisionId);

            var deviceId = await _js.InvokeAsync<string?>("localStorage.getItem", DeviceIdKey);
            if (!string.IsNullOrWhiteSpace(deviceId))
                request.Headers.Add("X-Station-Device-Id", deviceId);

            // Header HTTP hanya ASCII -- nama perangkat bisa berisi karakter lain.
            var deviceName = await _js.InvokeAsync<string?>("localStorage.getItem", DeviceNameKey);
            if (!string.IsNullOrWhiteSpace(deviceName))
                request.Headers.Add("X-Station-Device-Name", Uri.EscapeDataString(deviceName));
        }

        var response = await base.SendAsync(request, cancellationToken);

        // Prompt 85: token ditolak saat halaman sedang jalan. Logout dikecualikan: logout
        // memakai token yang memang sudah/akan mati.
        if (hasToken && response.StatusCode == HttpStatusCode.Unauthorized
            && request.RequestUri?.AbsolutePath.EndsWith("/station-device/logout", StringComparison.OrdinalIgnoreCase) != true)
        {
            _notifier.NotifyTokenRejected();
        }

        return response;
    }
}
