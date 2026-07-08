using Microsoft.JSInterop;

namespace TerakarsaApp.Client.Auth;

// Menyertakan header X-Station-Token (token perangkat, disimpan di localStorage)
// pada semua request lewat HttpClient milik StationDeviceApiService. TIDAK memakai
// JWT sama sekali — beda alur dari AuthorizedHandler.
public class StationTokenHandler : DelegatingHandler
{
    public const string TokenKey = "stationToken";

    private readonly IJSRuntime _js;

    public StationTokenHandler(IJSRuntime js)
    {
        _js = js;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await _js.InvokeAsync<string?>("localStorage.getItem", TokenKey);
        if (!string.IsNullOrWhiteSpace(token))
            request.Headers.Add("X-Station-Token", token);

        return await base.SendAsync(request, cancellationToken);
    }
}
