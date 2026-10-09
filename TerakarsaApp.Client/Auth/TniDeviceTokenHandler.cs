using Microsoft.JSInterop;

namespace TerakarsaApp.Client.Auth;

// Menyertakan header X-Tni-Token (token perangkat) pada semua request HttpClient
// bernama "TniAPI". TIDAK memakai JWT -- modul /tni dipakai seperti stasiun,
// tanpa login.
//
// Token disimpan di localStorage perangkat dan bertahan sampai di-unpair.
// Petugas TIDAK dikirim: sejak alter_75 server mengenali nama petugas dari
// perangkat pemegang token (satu petugas per perangkat).
public class TniDeviceTokenHandler : DelegatingHandler
{
    public const string TokenKey = "tniToken";

    private readonly IJSRuntime _js;

    public TniDeviceTokenHandler(IJSRuntime js)
    {
        _js = js;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var token = await _js.InvokeAsync<string?>("localStorage.getItem", TokenKey);
        if (!string.IsNullOrWhiteSpace(token))
            request.Headers.Add("X-Tni-Token", token);

        return await base.SendAsync(request, cancellationToken);
    }
}
