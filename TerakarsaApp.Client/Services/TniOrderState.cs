using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.Client.Services;

// Prompt 61: state order aktif PDH TNI AD, dipakai header & subjudul SELURUH
// halaman /tni/... supaya tiap halaman tidak memanggil endpoint yang sama
// berulang kali.
//
// Scoped (satu per sesi WebAssembly): dimuat sekali lewat EnsureLoadedAsync,
// dan bisa dipaksa muat ulang lewat RefreshAsync setelah angka personel berubah
// (mis. selesai import di Prompt 62).
public class TniOrderState
{
    private readonly TniOrderApiService _api;
    private Task<TniOrderAktifDto?>? _loading;

    public TniOrderState(TniOrderApiService api)
    {
        _api = api;
    }

    public TniOrderAktifDto? Order { get; private set; }

    public bool IsLoaded => Order is not null;

    public int? OrderId => Order?.OrderId;

    // Subjudul standar halaman /tni/...: "Kodam III/Siliwangi - 7.246 personel"
    public string Subjudul =>
        Order is null
            ? string.Empty
            : string.Join(" · ", new[]
            {
                Order.Instansi,
                Order.TotalPersonel > 0 ? $"{Order.TotalPersonel:N0} personel" : null
            }.Where(x => !string.IsNullOrWhiteSpace(x)));

    public event Action? OnChange;

    // Permintaan bersamaan dari beberapa komponen berbagi satu panggilan HTTP.
    public async Task<TniOrderAktifDto?> EnsureLoadedAsync()
    {
        if (Order is not null) return Order;

        _loading ??= LoadAsync();
        return await _loading;
    }

    public async Task<TniOrderAktifDto?> RefreshAsync()
    {
        _loading = LoadAsync();
        return await _loading;
    }

    private async Task<TniOrderAktifDto?> LoadAsync()
    {
        Order = await _api.GetAktifAsync();
        OnChange?.Invoke();
        return Order;
    }
}
