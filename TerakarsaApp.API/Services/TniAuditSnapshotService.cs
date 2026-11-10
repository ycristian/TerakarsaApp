using System.Data;
using System.Globalization;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Data;

namespace TerakarsaApp.API.Services;

// Snapshot + diff semua tabel schema tni (2026-11-09). Lihat TniAuditJurnal.cs
// untuk susunan folder.
//
// Setiap IntervalMenit: semua tabel dibaca lewat tni.SIS_AuditLog_Baca,
// dibandingkan dengan snapshot sebelumnya, tiap baris yang berubah dicatat.
// Perubahan ditandai TANPA LOG kalau:
//   - baris hilang permanen (aplikasi hanya soft delete), atau
//   - tidak ada kolom waktu (updated_at, deleted_at, set_at, ...) yang ikut
//     berubah -- ciri edit lewat SQL langsung, atau
//   - kolom waktunya berubah, tapi tidak ada request di jurnal pada jam itu,
//   - tabel/kolom muncul atau hilang (perubahan struktur).
// Snapshot hanya diperbarui kalau SEMUA tabel berhasil dibaca, jadi perubahan
// selama API mati/DB putus tetap tertangkap di putaran berikutnya.
public class TniAuditSnapshotService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly TniAuditLogOptions _opt;
    private readonly TniAuditJurnal _jurnal;
    private readonly ILogger<TniAuditSnapshotService> _log;
    private readonly HashSet<string> _abaikan;

    public TniAuditSnapshotService(
        IServiceScopeFactory scopeFactory,
        IOptions<TniAuditLogOptions> opt,
        TniAuditJurnal jurnal,
        ILogger<TniAuditSnapshotService> log)
    {
        _scopeFactory = scopeFactory;
        _opt = opt.Value;
        _jurnal = jurnal;
        _log = log;
        _abaikan = new HashSet<string>(_opt.AbaikanKolom, StringComparer.OrdinalIgnoreCase)
        {
            "perangkat.last_seen_at"
        };
    }

    private string FolderTerakhir => Path.Combine(_opt.Folder, "snapshot", "terakhir");
    private string FolderHarian => Path.Combine(_opt.Folder, "snapshot", "harian");
    private string FolderPerubahan => Path.Combine(_opt.Folder, "perubahan");
    private string PathStatus => Path.Combine(_opt.Folder, "snapshot", "status.json");

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        if (!_opt.Aktif) return;

        try { await Task.Delay(TimeSpan.FromSeconds(30), ct); }
        catch (OperationCanceledException) { return; }

        var interval = TimeSpan.FromMinutes(Math.Max(1, _opt.IntervalMenit));
        while (!ct.IsCancellationRequested)
        {
            try
            {
                await JalankanAsync(ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _log.LogError(ex, "Snapshot audit TNI gagal; dicoba lagi {Menit} menit lagi", interval.TotalMinutes);
            }

            try { await Task.Delay(interval, ct); }
            catch (OperationCanceledException) { return; }
        }
    }

    // ---------------------------------------------------------------- model

    private sealed class SnapshotTabel
    {
        public string Tabel { get; set; } = "";
        public List<string> Pk { get; set; } = new();
        public List<string> Kolom { get; set; } = new();
        public List<string> KolomWaktu { get; set; } = new();
        public Dictionary<string, Dictionary<string, string?>> Baris { get; set; } = new();
    }

    private sealed class StatusSnapshot
    {
        public DateTime TerakhirApi { get; set; }
        public DateTime TerakhirDb { get; set; }
        public string? ArsipTerakhir { get; set; }
        public int JumlahPerubahan { get; set; }
        public int JumlahTanpaLog { get; set; }
    }

    private sealed record Perubahan(JsonObject Json, bool TanpaLog, string Tabel, string Kunci,
        string Aksi, string Alasan, string Ringkas);

    // ---------------------------------------------------------------- utama

    public async Task JalankanAsync(CancellationToken ct)
    {
        var (sekarang, skew, dbNow, tabelBaru) = await BacaSemuaTabelAsync(ct);

        var status = BacaJson<StatusSnapshot>(PathStatus);
        var perubahan = new List<Perubahan>();

        if (status == null)
        {
            perubahan.Add(Buat("*", "", "BASELINE", false,
                $"Snapshot pertama: {tabelBaru.Count} tabel, {tabelBaru.Sum(t => t.Baris.Count)} baris.",
                null, new JsonObject(), sekarang, sekarang));
        }
        else
        {
            var tol = TimeSpan.FromSeconds(_opt.ToleransiDetik);
            var dari = status.TerakhirApi;
            var jurnal = _jurnal.Baca(dari - tol - TimeSpan.FromMinutes(1), sekarang + tol);

            var namaBaru = tabelBaru.Select(t => t.Tabel).ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var cur in tabelBaru)
            {
                var prev = BacaJson<SnapshotTabel>(PathTabel(cur.Tabel));
                Bandingkan(prev, cur, jurnal, skew, tol, dari, sekarang, perubahan);
            }

            // Tabel yang ada di snapshot lama tapi sudah tidak ada di DB.
            if (Directory.Exists(FolderTerakhir))
            {
                foreach (var f in Directory.GetFiles(FolderTerakhir, "*.json"))
                {
                    var nama = Path.GetFileNameWithoutExtension(f);
                    if (namaBaru.Contains(nama)) continue;
                    perubahan.Add(Buat(nama, "", "TABEL_HILANG", true, "Tabel sudah tidak ada di DB (DROP/rename).",
                        null, new JsonObject(), dari, sekarang));
                    File.Delete(f);
                }
            }
        }

        TulisPerubahan(sekarang, perubahan);

        Directory.CreateDirectory(FolderTerakhir);
        foreach (var t in tabelBaru) TulisJsonAtomik(PathTabel(t.Tabel), t);

        var hariIni = sekarang.ToString("yyyy-MM-dd");
        string? arsip = status?.ArsipTerakhir;
        if (arsip != hariIni)
        {
            Directory.CreateDirectory(FolderHarian);
            var zip = Path.Combine(FolderHarian, hariIni + ".zip");
            if (!File.Exists(zip)) ZipFile.CreateFromDirectory(FolderTerakhir, zip, CompressionLevel.Optimal, false);
            arsip = hariIni;
        }

        var tanpaLog = perubahan.Count(p => p.TanpaLog);
        TulisJsonAtomik(PathStatus, new StatusSnapshot
        {
            TerakhirApi = sekarang,
            TerakhirDb = dbNow,
            ArsipTerakhir = arsip,
            JumlahPerubahan = perubahan.Count,
            JumlahTanpaLog = tanpaLog
        });

        if (tanpaLog > 0)
            _log.LogWarning("Audit TNI: {Jumlah} perubahan TANPA LOG terdeteksi, lihat {Folder}", tanpaLog, FolderPerubahan);
        else
            _log.LogInformation("Audit TNI: snapshot selesai, {Jumlah} perubahan", perubahan.Count);
    }

    // ---------------------------------------------------------------- baca DB

    private async Task<(DateTime Sekarang, TimeSpan Skew, DateTime DbNow, List<SnapshotTabel> Tabel)>
        BacaSemuaTabelAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        // Koneksi sendiri, bukan milik EF -- tidak mengganggu state DbContext.
        await using var conn = new SqlConnection(db.Database.GetConnectionString());
        await conn.OpenAsync(ct);

        var daftar = new List<(string Nama, string? Pk)>();
        DateTime dbNow = default;
        await using (var cmd = new SqlCommand("tni.SIS_AuditLog_Tabel", conn) { CommandType = CommandType.StoredProcedure })
        await using (var rd = await cmd.ExecuteReaderAsync(ct))
        {
            while (await rd.ReadAsync(ct))
            {
                daftar.Add((rd.GetString(0), rd.IsDBNull(1) ? null : rd.GetString(1)));
                dbNow = rd.GetDateTime(2);
            }
        }
        var sekarang = DateTime.Now;
        var skew = dbNow == default ? TimeSpan.Zero : sekarang - dbNow;

        var hasil = new List<SnapshotTabel>();
        foreach (var (nama, pk) in daftar)
        {
            var t = new SnapshotTabel
            {
                Tabel = nama,
                Pk = string.IsNullOrEmpty(pk) ? new() : pk.Split(',').ToList()
            };

            await using var cmd = new SqlCommand("tni.SIS_AuditLog_Baca", conn)
            {
                CommandType = CommandType.StoredProcedure,
                CommandTimeout = 300
            };
            cmd.Parameters.Add(new SqlParameter("@Tabel", SqlDbType.NVarChar, 128) { Value = nama });
            await using var rd = await cmd.ExecuteReaderAsync(ct);

            for (int i = 0; i < rd.FieldCount; i++)
            {
                t.Kolom.Add(rd.GetName(i));
                var tipe = rd.GetFieldType(i);
                if (tipe == typeof(DateTime) || tipe == typeof(DateTimeOffset)) t.KolomWaktu.Add(rd.GetName(i));
            }

            while (await rd.ReadAsync(ct))
            {
                var row = new Dictionary<string, string?>(t.Kolom.Count);
                for (int i = 0; i < rd.FieldCount; i++)
                    row[t.Kolom[i]] = rd.IsDBNull(i) ? null : Kanonik(rd.GetValue(i));

                var kunci = t.Pk.Count > 0
                    ? string.Join("|", t.Pk.Select(c => row.GetValueOrDefault(c) ?? "NULL"))
                    : "#" + HashBaris(row);
                // Tabel tanpa PK bisa berisi baris kembar: beri akhiran supaya
                // jumlahnya tetap terhitung.
                var k = kunci;
                for (int n = 2; t.Baris.ContainsKey(k); n++) k = $"{kunci}~{n}";
                t.Baris[k] = row;
            }
            hasil.Add(t);
        }
        return (sekarang, skew, dbNow, hasil);
    }

    private static string Kanonik(object v) => v switch
    {
        DateTime d => d.ToString("yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture),
        DateTimeOffset d => d.ToString("yyyy-MM-dd HH:mm:ss.fffffff zzz", CultureInfo.InvariantCulture),
        bool b => b ? "1" : "0",
        byte[] bytes => Convert.ToHexString(bytes),
        IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
        _ => v.ToString() ?? ""
    };

    private static string HashBaris(Dictionary<string, string?> row)
    {
        var s = JsonSerializer.Serialize(row);
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s)))[..16];
    }

    // ---------------------------------------------------------------- diff

    private void Bandingkan(SnapshotTabel? prev, SnapshotTabel cur, List<TniJurnalEntri> jurnal,
        TimeSpan skew, TimeSpan tol, DateTime dari, DateTime sampai, List<Perubahan> hasil)
    {
        if (prev == null)
        {
            hasil.Add(Buat(cur.Tabel, "", "TABEL_BARU", true,
                $"Tabel belum ada di snapshot sebelumnya ({cur.Baris.Count} baris dijadikan pembanding).",
                null, new JsonObject(), dari, sampai));
            return;
        }

        var tambahKolom = cur.Kolom.Except(prev.Kolom, StringComparer.OrdinalIgnoreCase).ToList();
        var hilangKolom = prev.Kolom.Except(cur.Kolom, StringComparer.OrdinalIgnoreCase).ToList();
        if (tambahKolom.Count > 0 || hilangKolom.Count > 0)
        {
            hasil.Add(Buat(cur.Tabel, "", "KOLOM_BERUBAH", true,
                $"Struktur tabel berubah. Kolom baru: {string.Join(", ", tambahKolom)}; hilang: {string.Join(", ", hilangKolom)}.",
                null, new JsonObject(), dari, sampai));
        }

        var kolomBanding = cur.Kolom
            .Where(c => prev.Kolom.Contains(c, StringComparer.OrdinalIgnoreCase))
            .Where(c => !_abaikan.Contains($"{cur.Tabel}.{c}"))
            .ToList();
        var kolomWaktu = cur.KolomWaktu.Where(c => !_abaikan.Contains($"{cur.Tabel}.{c}")).ToList();

        foreach (var (kunci, baru) in cur.Baris)
        {
            if (!prev.Baris.TryGetValue(kunci, out var lama))
            {
                var waktu = kolomWaktu.Select(c => baru.GetValueOrDefault(c)).ToList();
                hasil.Add(Nilai(cur.Tabel, kunci, "TAMBAH", BarisJson(baru), waktu,
                    kolomWaktu.Count > 0, jurnal, skew, tol, dari, sampai, "baris baru"));
                continue;
            }

            var beda = kolomBanding
                .Where(c => !string.Equals(lama.GetValueOrDefault(c), baru.GetValueOrDefault(c), StringComparison.Ordinal))
                .ToList();
            if (beda.Count == 0) continue;

            var kolomJson = new JsonObject();
            foreach (var c in beda)
                kolomJson[c] = new JsonObject { ["lama"] = lama.GetValueOrDefault(c), ["baru"] = baru.GetValueOrDefault(c) };

            var delLama = lama.GetValueOrDefault("deleted_at");
            var delBaru = baru.GetValueOrDefault("deleted_at");
            var aksi = delLama == null && delBaru != null ? "HAPUS_SOFT"
                     : delLama != null && delBaru == null ? "PULIH"
                     : "UBAH";

            var waktuBerubah = beda.Where(c => kolomWaktu.Contains(c)).Select(c => baru.GetValueOrDefault(c)).ToList();
            var ringkas = string.Join(" | ", beda.Select(c =>
                $"{c}: {Pendek(lama.GetValueOrDefault(c))} -> {Pendek(baru.GetValueOrDefault(c))}"));
            hasil.Add(Nilai(cur.Tabel, kunci, aksi, new JsonObject { ["kolom"] = kolomJson }, waktuBerubah,
                kolomWaktu.Count > 0, jurnal, skew, tol, dari, sampai, ringkas));
        }

        foreach (var (kunci, lama) in prev.Baris)
        {
            if (cur.Baris.ContainsKey(kunci)) continue;
            hasil.Add(Buat(cur.Tabel, kunci, "HAPUS_PERMANEN", true,
                "Baris hilang dari DB. Aplikasi tidak pernah hard delete -- pasti di luar aplikasi.",
                "baris lama tersimpan di kolom 'baris' (perubahan-*.jsonl)", BarisJson(lama), dari, sampai));
        }
    }

    // Menentukan apakah perubahan punya pasangan di jurnal.
    private Perubahan Nilai(string tabel, string kunci, string aksi, JsonObject isi, List<string?> waktuBaris,
        bool tabelPunyaWaktu, List<TniJurnalEntri> jurnal, TimeSpan skew, TimeSpan tol,
        DateTime dari, DateTime sampai, string ringkas)
    {
        var waktu = waktuBaris
            .Where(s => s != null)
            .Select(s => DateTime.TryParseExact(s, "yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var d) ? d : (DateTime?)null)
            .Where(d => d.HasValue)
            .Select(d => d!.Value + skew)       // jam DB -> jam API
            .ToList();

        List<TniJurnalEntri> cocok;
        bool tanpaLog;
        string alasan;

        if (waktu.Count == 0)
        {
            if (!tabelPunyaWaktu)
            {
                cocok = jurnal.Where(j => j.Selesai >= dari && j.Mulai <= sampai).ToList();
                tanpaLog = cocok.Count == 0;
                alasan = tanpaLog
                    ? "Tabel tanpa kolom waktu dan tidak ada request tulis di jendela ini."
                    : "Tabel tanpa kolom waktu; ada request tulis di jendela ini (cocok longgar).";
            }
            else
            {
                cocok = new();
                tanpaLog = true;
                alasan = "Isi berubah tapi tidak ada kolom waktu (updated_at/deleted_at/dll.) yang ikut berubah -- ciri edit SQL langsung.";
            }
        }
        else
        {
            cocok = jurnal
                .Where(j => waktu.Any(w => w >= j.Mulai - tol && w <= j.Selesai + tol))
                .ToList();
            tanpaLog = cocok.Count == 0;
            alasan = tanpaLog
                ? "Kolom waktu berubah, tapi tidak ada request API pada jam itu."
                : "Cocok dengan request API.";
        }

        if (cocok.Count > 0)
        {
            var arr = new JsonArray();
            foreach (var j in cocok.Take(3))
                arr.Add(new JsonObject
                {
                    ["id"] = j.Id,
                    ["mulai"] = j.Mulai.ToString("yyyy-MM-dd HH:mm:ss.fff"),
                    ["method"] = j.Method,
                    ["path"] = j.Path,
                    ["status"] = j.Status,
                    ["perangkat_id"] = j.PerangkatId
                });
            isi["jurnal"] = arr;
        }
        isi["waktu_baris"] = new JsonArray(waktuBaris.Where(s => s != null).Select(s => (JsonNode?)JsonValue.Create(s)).ToArray());

        return Buat(tabel, kunci, aksi, tanpaLog, alasan, ringkas, isi, dari, sampai);
    }

    private static Perubahan Buat(string tabel, string kunci, string aksi, bool tanpaLog, string alasan,
        string? ringkas, JsonObject isi, DateTime dari, DateTime sampai)
    {
        var json = new JsonObject
        {
            ["deteksi"] = DateTimeOffset.Now.ToString("o"),
            ["jendela_dari"] = dari.ToString("yyyy-MM-dd HH:mm:ss"),
            ["jendela_sampai"] = sampai.ToString("yyyy-MM-dd HH:mm:ss"),
            ["tabel"] = tabel,
            ["kunci"] = kunci,
            ["aksi"] = aksi,
            ["tanpa_log"] = tanpaLog,
            ["alasan"] = alasan
        };
        foreach (var kv in isi.ToList())
        {
            isi.Remove(kv.Key);
            json[kv.Key] = kv.Value;
        }
        return new Perubahan(json, tanpaLog, tabel, kunci, aksi, alasan, ringkas ?? "");
    }

    private static JsonObject BarisJson(Dictionary<string, string?> row)
    {
        var o = new JsonObject();
        foreach (var (k, v) in row) o[k] = v;
        return new JsonObject { ["baris"] = o };
    }

    private static string Pendek(string? s) =>
        s == null ? "NULL" : s.Length > 60 ? s[..60] + "…" : s;

    // ---------------------------------------------------------------- tulis file

    private void TulisPerubahan(DateTime sekarang, List<Perubahan> perubahan)
    {
        if (perubahan.Count == 0) return;
        Directory.CreateDirectory(FolderPerubahan);
        var tgl = sekarang.ToString("yyyy-MM-dd");

        var sb = new StringBuilder();
        foreach (var p in perubahan) sb.Append(p.Json.ToJsonString(TniAuditJurnal.JsonOpts)).Append('\n');
        File.AppendAllText(Path.Combine(FolderPerubahan, $"perubahan-{tgl}.jsonl"), sb.ToString(), new UTF8Encoding(false));

        var curiga = perubahan.Where(p => p.TanpaLog).ToList();
        if (curiga.Count == 0) return;

        // CSV pemisah titik koma + BOM: langsung terbuka rapi di Excel locale Indonesia.
        var csvPath = Path.Combine(FolderPerubahan, $"tanpa-log-{tgl}.csv");
        var baru = !File.Exists(csvPath);
        var csv = new StringBuilder();
        if (baru) csv.Append('﻿').Append("deteksi;tabel;kunci;aksi;alasan;perubahan\r\n");
        foreach (var p in curiga)
            csv.Append(string.Join(";", new[]
            {
                sekarang.ToString("yyyy-MM-dd HH:mm:ss"), p.Tabel, p.Kunci, p.Aksi, p.Alasan, p.Ringkas
            }.Select(Csv))).Append("\r\n");
        File.AppendAllText(csvPath, csv.ToString(), new UTF8Encoding(false));
    }

    private static string Csv(string s) =>
        s.IndexOfAny(new[] { ';', '"', '\n', '\r' }) >= 0 ? "\"" + s.Replace("\"", "\"\"") + "\"" : s;

    private string PathTabel(string tabel) => Path.Combine(FolderTerakhir, tabel + ".json");

    private T? BacaJson<T>(string path) where T : class
    {
        if (!File.Exists(path)) return null;
        try
        {
            using var fs = File.OpenRead(path);
            return JsonSerializer.Deserialize<T>(fs);
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Snapshot audit TNI rusak, diperlakukan sebagai tidak ada: {Path}", path);
            return null;
        }
    }

    private static void TulisJsonAtomik<T>(string path, T isi)
    {
        var tmp = path + ".tmp";
        using (var fs = File.Create(tmp))
            JsonSerializer.Serialize(fs, isi, TniAuditJurnal.JsonOpts);
        File.Move(tmp, path, overwrite: true);
    }
}
