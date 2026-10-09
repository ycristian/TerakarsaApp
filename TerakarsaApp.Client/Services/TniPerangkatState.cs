using Microsoft.JSInterop;
using TerakarsaApp.Client.Auth;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Sesi perangkat TNI: identitas perangkat pemegang token (localStorage).
//
// 2026-10-06 (alter_75): TIDAK ADA lagi pemilihan petugas. Setiap perangkat
// punya SATU nama petugas (Perangkat.NamaPetugas) yang diatur admin di halaman
// pengelolaan perangkat -- perangkat langsung siap dipakai setelah pairing.
public class TniPerangkatState
{
    private readonly TniPerangkatApiService _api;
    private readonly IJSRuntime _js;

    // Kunci localStorage peninggalan pemilih petugas lama -- dibersihkan saat muat.
    private static readonly string[] KunciLama = { "tniPetugasId", "tniPetugasNama" };

    public TniPerangkatState(TniPerangkatApiService api, IJSRuntime js)
    {
        _api = api;
        _js = js;
    }

    public TniPerangkatMeDto? Perangkat { get; private set; }

    // Nama petugas perangkat ini -- dipakai header halaman.
    public string? PetugasNama => Perangkat?.NamaPetugas;

    public bool IsLoaded { get; private set; }

    public bool SudahPairing => Perangkat is not null;

    // true = siap dipakai (perangkat terdaftar).
    public bool Siap => SudahPairing;

    // alter_74: apakah menu ini diizinkan untuk perangkat ini.
    public bool BolehMenu(string code) => Perangkat?.BolehMenu(code) == true;

    public event Action? OnChange;

    public async Task EnsureLoadedAsync(bool paksa = false)
    {
        if (IsLoaded && !paksa) return;

        // null = token tidak ada / sudah dicabut admin -> layar pairing.
        Perangkat = await _api.GetMeAsync();

        foreach (var k in KunciLama) await Hapus(k);

        IsLoaded = true;
        OnChange?.Invoke();
    }

    public async Task SimpanTokenAsync(string token, TniPerangkatMeDto? perangkat)
    {
        await Simpan(TniDeviceTokenHandler.TokenKey, token);
        Perangkat = perangkat;
        IsLoaded = true;
        OnChange?.Invoke();
    }

    // "Keluar" di perangkat: token dibuang. Token di server tidak diubah (itu
    // wewenang admin lewat Putuskan Perangkat), jadi perangkat ini cukup
    // pairing ulang dengan kode baru.
    public async Task KeluarAsync()
    {
        await Hapus(TniDeviceTokenHandler.TokenKey);

        Perangkat = null;
        IsLoaded = false;
        OnChange?.Invoke();
    }

    // localStorage bisa diblokir (mode privat) -- jangan sampai melempar.
    private async Task Simpan(string key, string value)
    {
        try { await _js.InvokeVoidAsync("localStorage.setItem", key, value); } catch { }
    }

    private async Task Hapus(string key)
    {
        try { await _js.InvokeVoidAsync("localStorage.removeItem", key); } catch { }
    }
}
