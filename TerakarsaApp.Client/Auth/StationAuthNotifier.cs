namespace TerakarsaApp.Client.Auth;

// Prompt 85: StationTokenHandler -> halaman /station: "token perangkat ini ditolak server (401)"
// saat halaman sedang jalan (diambil perangkat lain atau diputus admin). Singleton karena
// handler HttpClientFactory hidup di scope DI-nya sendiri -- service scoped tidak akan sampai
// ke komponen.
public class StationAuthNotifier
{
    public event Action? TokenRejected;

    public void NotifyTokenRejected() => TokenRejected?.Invoke();
}
