using Android.Bluetooth;
using Java.Util;
using TerakarsaApp.Mobile.Services;

namespace TerakarsaApp.Mobile.Platforms.Android;

// Prompt 77: pengiriman byte TSPL ke printer label portabel (Xprinter XP-P323B)
// lewat Bluetooth KLASIK (SPP), UUID standar 00001101-0000-1000-8000-00805F9B34FB.
//
// Koneksi dibuka saat ada job dan ditutup setelah idle 60 detik -- printer portabel
// mematikan radio sendiri kalau dibiarkan menganggur, dan socket basi menyebabkan
// job berikutnya gagal.
public class BluetoothPrinter : IDisposable
{
    private static readonly UUID SppUuid = UUID.FromString("00001101-0000-1000-8000-00805F9B34FB")!;
    private static readonly TimeSpan Idle = TimeSpan.FromSeconds(60);

    private BluetoothSocket? _socket;
    private DateTime _terakhirDipakai = DateTime.MinValue;

    public bool Terhubung => _socket?.IsConnected == true;

    public static List<(string Nama, string Mac)> DaftarPairing()
    {
        var hasil = new List<(string, string)>();

        var adapter = BluetoothAdapter.DefaultAdapter;
        if (adapter is null || !adapter.IsEnabled) return hasil;

        foreach (var d in adapter.BondedDevices ?? new List<BluetoothDevice>())
        {
            if (d.Address is null) continue;
            hasil.Add((d.Name ?? d.Address, d.Address));
        }

        return hasil;
    }

    public (bool Ok, string Error) Kirim(byte[] data)
    {
        var (ok, error) = Pastikan();
        if (!ok) return (false, error);

        try
        {
            var stream = _socket!.OutputStream;
            if (stream is null) return (false, "Printer tidak menerima data.");

            stream.Write(data, 0, data.Length);
            stream.Flush();

            _terakhirDipakai = DateTime.Now;
            return (true, string.Empty);
        }
        catch (Exception ex)
        {
            // Socket basi: tutup supaya percobaan berikutnya membuka koneksi baru.
            Tutup();
            return (false, ex.Message);
        }
    }

    public void TutupKalauIdle()
    {
        if (_socket is null) return;
        if (DateTime.Now - _terakhirDipakai < Idle) return;

        Tutup();
        PrintLog.Tulis("Koneksi printer ditutup (idle 60 detik).");
    }

    public void Tutup()
    {
        try
        {
            _socket?.Close();
        }
        catch (Exception)
        {
        }

        _socket?.Dispose();
        _socket = null;
    }

    private (bool Ok, string Error) Pastikan()
    {
        if (Terhubung) return (true, string.Empty);

        Tutup();

        var mac = PrintPrefs.PrinterMac;
        if (string.IsNullOrWhiteSpace(mac)) return (false, "Printer Bluetooth belum dipilih.");

        var adapter = BluetoothAdapter.DefaultAdapter;
        if (adapter is null) return (false, "Perangkat ini tidak punya Bluetooth.");
        if (!adapter.IsEnabled) return (false, "Bluetooth sedang mati.");

        var device = adapter.GetRemoteDevice(mac);
        if (device is null) return (false, "Printer tidak ditemukan — pasangkan ulang di pengaturan Bluetooth.");

        try
        {
            _socket = device.CreateRfcommSocketToServiceRecord(SppUuid);
            _socket?.Connect();

            if (!Terhubung) return (false, "Printer tidak merespons.");

            _terakhirDipakai = DateTime.Now;
            return (true, string.Empty);
        }
        catch (Exception ex)
        {
            Tutup();
            return (false, ex.Message);
        }
    }

    public void Dispose() => Tutup();
}
