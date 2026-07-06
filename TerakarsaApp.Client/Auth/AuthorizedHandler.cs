using Microsoft.AspNetCore.Components;
using System.Net;
using System.Net.Http.Headers;

namespace TerakarsaApp.Client.Auth;

public class AuthorizedHandler : DelegatingHandler
{
    private readonly CustomAuthStateProvider _authStateProvider;
    private readonly NavigationManager _nav;
    private readonly AuthApiService _authApi;

    // Static: dibagi lintas request paralel dalam sesi browser yang sama, supaya beberapa
    // request yang gagal 401 bersamaan hanya memicu satu kali panggilan refresh ke server.
    private static readonly object _gate = new();
    private static Task<bool>? _inFlightRefresh;

    public AuthorizedHandler(CustomAuthStateProvider authStateProvider, NavigationManager nav, AuthApiService authApi)
    {
        _authStateProvider = authStateProvider;
        _nav = nav;
        _authApi = authApi;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        await AttachTokenAsync(request);
        var response = await base.SendAsync(request, cancellationToken);

        if (response.StatusCode != HttpStatusCode.Unauthorized)
            return response;

        var refreshed = await GetOrStartRefreshAsync();
        if (!refreshed)
        {
            await _authStateProvider.MarkUserAsLoggedOut();
            _nav.NavigateTo("/login", forceLoad: true);
            return response;
        }

        var retryRequest = await CloneRequestAsync(request);
        await AttachTokenAsync(retryRequest);
        return await base.SendAsync(retryRequest, cancellationToken);
    }

    private async Task AttachTokenAsync(HttpRequestMessage request)
    {
        var token = await _authStateProvider.GetAccessToken();
        if (!string.IsNullOrWhiteSpace(token))
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }

    private Task<bool> GetOrStartRefreshAsync()
    {
        lock (_gate)
        {
            if (_inFlightRefresh is null || _inFlightRefresh.IsCompleted)
                _inFlightRefresh = DoRefreshAsync();

            return _inFlightRefresh;
        }
    }

    private async Task<bool> DoRefreshAsync()
    {
        try
        {
            return await _authApi.TryRefreshTokenAsync();
        }
        finally
        {
            lock (_gate) { _inFlightRefresh = null; }
        }
    }

    private static async Task<HttpRequestMessage> CloneRequestAsync(HttpRequestMessage request)
    {
        var clone = new HttpRequestMessage(request.Method, request.RequestUri);

        if (request.Content is not null)
        {
            var bytes = await request.Content.ReadAsByteArrayAsync();
            clone.Content = new ByteArrayContent(bytes);
            foreach (var header in request.Content.Headers)
                clone.Content.Headers.Add(header.Key, header.Value);
        }

        foreach (var header in request.Headers)
            clone.Headers.TryAddWithoutValidation(header.Key, header.Value);

        return clone;
    }
}