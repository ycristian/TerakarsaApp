using Microsoft.JSInterop;

namespace TerakarsaApp.Client.Auth;

// Menyertakan header X-Dashboard-Token (token TV, disimpan di localStorage) pada semua
// request lewat HttpClient milik DashboardApiService. TIDAK memakai JWT sama sekali --
// pola sama dengan StationTokenHandler, key localStorage terpisah dari station.
public class DashboardTokenHandler : DelegatingHandler
{
    public const string TokenKey = "dashboardToken";

    private readonly IJSRuntime _js;

    public DashboardTokenHandler(IJSRuntime js)
    {
        _js = js;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await _js.InvokeAsync<string?>("localStorage.getItem", TokenKey);
        if (!string.IsNullOrWhiteSpace(token))
            request.Headers.Add("X-Dashboard-Token", token);

        return await base.SendAsync(request, cancellationToken);
    }
}
