using System.IO;
using System.Media;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace TerakarsaApp.GateApp.Services;

public enum GateSound
{
    CheckIn,
    CheckOut,
    Duplicate,
    Reject,
}

// Prompt 70: layar gate menghadap SATPAM saja -- karyawan tidak melihatnya. Karena itu bunyi
// berbeda per hasil adalah lapis verifikasi UTAMA, bukan pelengkap: satpam sering menunduk
// mencari kartu di rak dan tidak melihat layar.
//
//   CHECK_IN  -> bip pendek 1x
//   CHECK_OUT -> bip pendek 2x
//   DUPLIKAT  -> bip pelan 1x
//   ditolak / perlu konfirmasi -> bip panjang rendah
//
// PENYIMPANGAN YANG DISENGAJA dari "File WAV di folder exe": bunyinya DISINTESIS di memori lalu
// diputar lewat System.Media.SoundPlayer. Alasannya prompt yang sama meminta pengatur volume di
// menu satpam -- SoundPlayer tidak punya properti volume sama sekali, jadi satu-satunya cara
// mengatur volume tanpa menambah dependensi audio adalah membentuk amplitudonya di gelombang.
// File WAV di folder exe tetap didukung dan MENANG kalau ada (check_in.wav / check_out.wav /
// duplikat.wav / reject.wav) -- waktu itu slider volume tidak berpengaruh, dan itu disebutkan
// di layar. Tidak ada file = tetap jalan (bunyi sintesis), jadi aplikasi tidak pernah bisu
// karena file hilang.
public class GateSoundPlayer
{
    private const int SampleRate = 22050;

    private readonly ILogger<GateSoundPlayer> _logger;
    private readonly Dictionary<GateSound, string> _fileNames = new()
    {
        [GateSound.CheckIn] = "check_in.wav",
        [GateSound.CheckOut] = "check_out.wav",
        [GateSound.Duplicate] = "duplikat.wav",
        [GateSound.Reject] = "reject.wav",
    };

    public GateSoundPlayer(IOptions<GateWorkerOptions> options, ILogger<GateSoundPlayer> logger)
    {
        _logger = logger;
        VolumePercent = Math.Clamp(options.Value.SoundVolumePercent, 0, 100);
    }

    public int VolumePercent { get; set; }

    // true kalau minimal satu file WAV override ada -- dipakai layar "Status & sinkronisasi"
    // untuk memberi tahu bahwa slider volume tidak berlaku untuk file itu.
    public bool HasWavOverrides => _fileNames.Values.Any(f => File.Exists(Path.Combine(AppContext.BaseDirectory, f)));

    public void Play(GateSound sound)
    {
        try
        {
            var path = Path.Combine(AppContext.BaseDirectory, _fileNames[sound]);
            if (File.Exists(path))
            {
                using var filePlayer = new SoundPlayer(path);
                filePlayer.Play();   // asinkron: jangan menahan layar hasil
                return;
            }

            using var stream = new MemoryStream(BuildWav(sound, VolumePercent));
            using var player = new SoundPlayer(stream);
            player.Play();
        }
        catch (Exception ex)
        {
            // Tidak ada speaker, driver audio mati, file WAV rusak: aplikasi TETAP jalan.
            _logger.LogWarning(ex, "Bunyi {Sound} gagal diputar.", sound);
        }
    }

    // Satu bunyi = daftar (frekuensi Hz, panjang ms, jeda setelahnya ms).
    private static (double Freq, int Ms, int GapMs)[] Pattern(GateSound sound) => sound switch
    {
        GateSound.CheckIn => new[] { (1800.0, 110, 0) },
        GateSound.CheckOut => new[] { (1800.0, 90, 80), (1800.0, 90, 0) },
        // "Pelan": frekuensi lebih rendah dan lebih singkat, bukan sekadar lebih kecil volumenya,
        // supaya tetap terdengar beda di keramaian pagi.
        GateSound.Duplicate => new[] { (900.0, 70, 0) },
        GateSound.Reject => new[] { (320.0, 650, 0) },
        _ => new[] { (1000.0, 120, 0) },
    };

    private static byte[] BuildWav(GateSound sound, int volumePercent)
    {
        var pattern = Pattern(sound);
        var totalMs = pattern.Sum(p => p.Ms + p.GapMs);
        var sampleCount = SampleRate * totalMs / 1000;

        var samples = new short[sampleCount];
        var amplitude = (short)(short.MaxValue * 0.6 * Math.Clamp(volumePercent, 0, 100) / 100.0);

        var cursor = 0;
        foreach (var (freq, ms, gapMs) in pattern)
        {
            var toneSamples = SampleRate * ms / 1000;
            for (var i = 0; i < toneSamples && cursor < sampleCount; i++, cursor++)
            {
                // Fade in/out 3 ms di tiap ujung supaya tidak ada "klik" di speaker kecil.
                var fadeSamples = Math.Max(1, SampleRate * 3 / 1000);
                var fade = Math.Min(1.0, Math.Min(i, Math.Max(0, toneSamples - i)) / (double)fadeSamples);
                samples[cursor] = (short)(amplitude * fade * Math.Sin(2 * Math.PI * freq * i / SampleRate));
            }
            cursor += Math.Min(SampleRate * gapMs / 1000, Math.Max(0, sampleCount - cursor));
        }

        return WriteWav(samples);
    }

    // WAV PCM 16-bit mono minimal (44 byte header). Cukup untuk SoundPlayer.
    private static byte[] WriteWav(short[] samples)
    {
        var dataBytes = samples.Length * 2;
        using var ms = new MemoryStream(44 + dataBytes);
        using var writer = new BinaryWriter(ms);

        writer.Write("RIFF".ToCharArray());
        writer.Write(36 + dataBytes);
        writer.Write("WAVE".ToCharArray());
        writer.Write("fmt ".ToCharArray());
        writer.Write(16);                       // ukuran blok fmt
        writer.Write((short)1);                 // PCM
        writer.Write((short)1);                 // mono
        writer.Write(SampleRate);
        writer.Write(SampleRate * 2);           // byte rate
        writer.Write((short)2);                 // block align
        writer.Write((short)16);                // bits per sample
        writer.Write("data".ToCharArray());
        writer.Write(dataBytes);
        foreach (var sample in samples) writer.Write(sample);

        writer.Flush();
        return ms.ToArray();
    }
}
