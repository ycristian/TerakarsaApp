using System.Net.Sockets;

namespace TerakarsaApp.PrintService;

// Prompt 88: kirim byte mentah (TSPL / ESC/POS) langsung ke printer jaringan lewat socket
// TCP (umumnya port 9100, "RAW"/JetDirect) -- printer TIDAK perlu didaftarkan di Windows.
// Dipakai device print_devices.transport = 'TCP'. Pengirim Windows (RawPrinterHelper)
// tetap untuk transport 'WINDOWS'.
//
// Gagal koneksi dilempar sebagai exception dengan pesan "TCP host:port: ..." -- Worker
// melaporkannya ke api/print/report seperti kegagalan cetak lain (retry 3x lalu ERROR).
public static class TcpRawPrinter
{
    private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan WriteTimeout = TimeSpan.FromSeconds(15);

    public static async Task SendAsync(string? host, int? port, byte[] bytes, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(host) || port is null or < 1 or > 65535)
            throw new InvalidOperationException($"TCP {host}:{port}: host/port printer jaringan belum diisi dengan benar.");

        var target = $"TCP {host}:{port}";

        using var client = new TcpClient { NoDelay = true };

        using (var connectCts = CancellationTokenSource.CreateLinkedTokenSource(ct))
        {
            connectCts.CancelAfter(ConnectTimeout);
            try
            {
                await client.ConnectAsync(host, port.Value, connectCts.Token);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                throw new InvalidOperationException($"{target}: connection timeout ({ConnectTimeout.TotalSeconds:0} detik) -- printer mati atau IP salah.");
            }
            catch (SocketException ex)
            {
                throw new InvalidOperationException($"{target}: {DescribeSocketError(ex)}");
            }
        }

        try
        {
            using var writeCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            writeCts.CancelAfter(WriteTimeout);

            var stream = client.GetStream();
            await stream.WriteAsync(bytes, writeCts.Token);
            await stream.FlushAsync(writeCts.Token);

            // Tutup sisi kirim dulu supaya printer tahu data selesai sebelum socket ditutup.
            client.Client.Shutdown(SocketShutdown.Send);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new InvalidOperationException($"{target}: timeout saat mengirim data ke printer.");
        }
        catch (Exception ex) when (ex is IOException or SocketException)
        {
            throw new InvalidOperationException($"{target}: gagal mengirim data - {ex.Message}");
        }
    }

    private static string DescribeSocketError(SocketException ex) => ex.SocketErrorCode switch
    {
        SocketError.ConnectionRefused => "connection refused -- port printer tertutup/salah.",
        SocketError.TimedOut => "connection timeout -- printer mati atau IP salah.",
        SocketError.HostUnreachable or SocketError.NetworkUnreachable => "host unreachable -- cek jaringan/IP printer.",
        SocketError.HostNotFound => "host tidak dikenal.",
        _ => $"{ex.SocketErrorCode}: {ex.Message}"
    };
}
