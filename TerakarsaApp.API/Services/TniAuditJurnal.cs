using System.Security.Claims;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.Extensions.Options;
using TerakarsaApp.API.Authorization;
using TerakarsaApp.Shared.Tni;

namespace TerakarsaApp.API.Services;

// Audit log lokal PDH TNI AD (2026-11-09). Dua lapis, semuanya FILE di Folder
// (bukan tabel DB, supaya tidak ikut berubah kalau DB diutak-atik langsung):
//
//   jurnal\jurnal-yyyy-MM-dd.jsonl       setiap request tulis ke api/tni/* dan
//                                        api/public/tni/* (middleware di bawah)
//   perubahan\perubahan-yyyy-MM-dd.jsonl setiap baris tni yang berubah antar
//                                        snapshot (TniAuditSnapshotService)
//   perubahan\tanpa-log-yyyy-MM-dd.csv   hanya perubahan yang TIDAK punya
//                                        pasangan di jurnal -> yang perlu dicek
//   snapshot\terakhir\*.json             isi terakhir tiap tabel (pembanding)
//   snapshot\harian\yyyy-MM-dd.zip       salinan snapshot pertama tiap hari
public class TniAuditLogOptions
{
    public bool Aktif { get; set; } = true;
    public string Folder { get; set; } = @"D:\TMOS-Log\tni";
    public int IntervalMenit { get; set; } = 15;

    // Kelonggaran saat mencocokkan jam di baris DB dengan jam request di jurnal.
    public int ToleransiDetik { get; set; } = 10;

    // Body JSON lebih besar dari ini tidak disimpan isinya di jurnal.
    public int MaxBodyBytes { get; set; } = 32768;

    // Kolom "tabel.kolom" yang berubah sendiri tanpa request tulis -> diabaikan
    // saat diff. perangkat.last_seen_at SELALU diabaikan (diperbarui tiap GET).
    public List<string> AbaikanKolom { get; set; } = new();
}

public record TniJurnalEntri(
    string Id, DateTime Mulai, DateTime Selesai, string Method, string Path, int Status, int? PerangkatId);

public class TniAuditJurnal
{
    public static readonly JsonSerializerOptions JsonOpts = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private readonly object _lock = new();
    private readonly TniAuditLogOptions _opt;
    private readonly ILogger<TniAuditJurnal> _log;

    public TniAuditJurnal(IOptions<TniAuditLogOptions> opt, ILogger<TniAuditJurnal> log)
    {
        _opt = opt.Value;
        _log = log;
    }

    private string FolderJurnal => Path.Combine(_opt.Folder, "jurnal");

    // Tidak pernah melempar: gagal tulis log tidak boleh menggagalkan request.
    public void Tulis(DateTimeOffset waktu, JsonObject entri)
    {
        if (!_opt.Aktif) return;
        try
        {
            var bytes = Encoding.UTF8.GetBytes(entri.ToJsonString(JsonOpts) + "\n");
            lock (_lock)
            {
                Directory.CreateDirectory(FolderJurnal);
                var path = Path.Combine(FolderJurnal, $"jurnal-{waktu:yyyy-MM-dd}.jsonl");
                using var fs = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
                fs.Write(bytes);
            }
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Gagal menulis jurnal audit TNI ke {Folder}", FolderJurnal);
        }
    }

    // Entri jurnal yang rentang request-nya bersinggungan dengan [dari, sampai]
    // (jam lokal API).
    public List<TniJurnalEntri> Baca(DateTime dari, DateTime sampai)
    {
        var hasil = new List<TniJurnalEntri>();
        for (var tgl = dari.Date; tgl <= sampai.Date; tgl = tgl.AddDays(1))
        {
            var path = Path.Combine(FolderJurnal, $"jurnal-{tgl:yyyy-MM-dd}.jsonl");
            if (!File.Exists(path)) continue;

            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            using var sr = new StreamReader(fs, Encoding.UTF8);
            string? line;
            while ((line = sr.ReadLine()) != null)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try
                {
                    using var doc = JsonDocument.Parse(line);
                    var r = doc.RootElement;
                    var mulai = DateTimeOffset.Parse(r.GetProperty("mulai").GetString()!).LocalDateTime;
                    var selesai = DateTimeOffset.Parse(r.GetProperty("selesai").GetString()!).LocalDateTime;
                    if (selesai < dari || mulai > sampai) continue;

                    int? perangkatId = r.TryGetProperty("perangkat_id", out var p) && p.ValueKind == JsonValueKind.Number
                        ? p.GetInt32() : null;
                    hasil.Add(new TniJurnalEntri(
                        r.GetProperty("id").GetString() ?? "",
                        mulai, selesai,
                        r.GetProperty("method").GetString() ?? "",
                        r.GetProperty("path").GetString() ?? "",
                        r.GetProperty("status").GetInt32(),
                        perangkatId));
                }
                catch (Exception ex)
                {
                    // Baris rusak/terpotong (mis. disk penuh) tidak boleh menghentikan diff.
                    _log.LogWarning(ex, "Baris jurnal audit TNI tidak terbaca di {Path}", path);
                }
            }
        }
        return hasil;
    }
}

// Mencatat setiap request tulis (selain GET/HEAD/OPTIONS) ke api/tni/* dan
// api/public/tni/*. Dipasang SETELAH UseAuthentication (user JWT sudah ada)
// dan SEBELUM UseAuthorization (request yang ditolak 401/403 ikut tercatat).
// Perangkat (X-Tni-Token) baru diketahui setelah filter controller jalan,
// jadi dibaca dari HttpContext.Items sesudah _next.
public class TniAuditJurnalMiddleware
{
    private readonly RequestDelegate _next;

    public TniAuditJurnalMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext ctx, TniAuditJurnal jurnal, IOptions<TniAuditLogOptions> opt)
    {
        var req = ctx.Request;
        if (!opt.Value.Aktif
            || HttpMethods.IsGet(req.Method) || HttpMethods.IsHead(req.Method) || HttpMethods.IsOptions(req.Method)
            || !(req.Path.StartsWithSegments("/api/tni", StringComparison.OrdinalIgnoreCase)
                 || req.Path.StartsWithSegments("/api/public/tni", StringComparison.OrdinalIgnoreCase)))
        {
            await _next(ctx);
            return;
        }

        var mulai = DateTimeOffset.Now;
        var max = opt.Value.MaxBodyBytes;
        JsonNode? body = null;
        string? bodyCatatan = null;

        if (req.ContentType?.Contains("json", StringComparison.OrdinalIgnoreCase) == true)
        {
            if (req.ContentLength is long len && len > max)
            {
                bodyCatatan = $"body {len} byte, isi tidak disimpan";
            }
            else
            {
                try
                {
                    req.EnableBuffering();
                    using var reader = new StreamReader(req.Body, Encoding.UTF8, false, 4096, leaveOpen: true);
                    var text = await reader.ReadToEndAsync();
                    req.Body.Position = 0;

                    if (text.Length > max) bodyCatatan = $"body {text.Length} karakter, isi tidak disimpan";
                    else if (text.Length > 0)
                    {
                        try { body = JsonNode.Parse(text); }
                        catch (JsonException) { body = JsonValue.Create(text); }
                    }
                }
                catch (Exception ex)
                {
                    bodyCatatan = "body tidak terbaca: " + ex.Message;
                    if (req.Body.CanSeek) req.Body.Position = 0;
                }
            }
        }

        string? error = null;
        try
        {
            await _next(ctx);
        }
        catch (Exception ex)
        {
            error = ex.GetType().Name + ": " + ex.Message;
            throw;
        }
        finally
        {
            var selesai = DateTimeOffset.Now;
            var perangkat = ctx.Items.TryGetValue(RequireTniDeviceTokenAttribute.HttpContextItemKey, out var pv)
                ? pv as TniPerangkatMeDto
                : null;
            int? userId = int.TryParse(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier), out var uid) ? uid : null;

            var e = new JsonObject
            {
                ["id"] = ctx.TraceIdentifier,
                ["mulai"] = mulai.ToString("o"),
                ["selesai"] = selesai.ToString("o"),
                ["durasi_ms"] = (int)(selesai - mulai).TotalMilliseconds,
                ["method"] = req.Method,
                ["path"] = req.Path.Value,
                ["query"] = req.QueryString.HasValue ? req.QueryString.Value : null,
                ["status"] = error != null ? 500 : ctx.Response.StatusCode,
                ["ip"] = ctx.Connection.RemoteIpAddress?.ToString(),
                ["user_id"] = userId,
                ["user"] = ctx.User.Identity?.IsAuthenticated == true ? ctx.User.Identity.Name : null,
                ["perangkat_id"] = perangkat?.PerangkatId,
                ["perangkat_code"] = perangkat?.PerangkatCode,
                ["nama_petugas"] = perangkat?.NamaPetugas
            };
            if (error != null) e["error"] = error;
            if (body != null) e["body"] = body;
            if (bodyCatatan != null) e["body_catatan"] = bodyCatatan;

            // Upload (mis. import Excel): simpan nama field + nama/ukuran file
            // saja. Form hanya dibaca kalau endpoint sudah mem-parse-nya.
            try
            {
                var form = ctx.Features.Get<IFormFeature>()?.Form;
                if (form != null)
                {
                    var fields = new JsonObject();
                    foreach (var kv in form)
                    {
                        var v = kv.Value.ToString();
                        fields[kv.Key] = v.Length > 500 ? v[..500] + "…" : v;
                    }
                    var files = new JsonArray();
                    foreach (var f in form.Files)
                        files.Add(new JsonObject { ["field"] = f.Name, ["nama"] = f.FileName, ["byte"] = f.Length });
                    if (fields.Count > 0) e["form"] = fields;
                    if (files.Count > 0) e["files"] = files;
                }
            }
            catch
            {
                // form tidak tersedia -- abaikan
            }

            jurnal.Tulis(mulai, e);
        }
    }
}
