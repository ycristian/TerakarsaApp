using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace TerakarsaApp.API.Services;

public enum CctvTokenCheck
{
    Ok,
    Missing,
    Invalid,
    Expired,
    WrongPath
}

// Prompt 92: token stream pendek untuk <video>/hls.js (tidak bisa membawa JWT dengan nyaman).
// token = base64url("path|expUnix|userId") + "." + base64url(HMACSHA256(secret, payload))
// Terikat ke SATU path kamera, berlaku Cctv:StreamTokenMinutes (default 10 menit).
// Hanya diterbitkan ke user ber-module CCTV (endpoint stream-token di CctvCameraController).
//
// Cctv:StreamTokenSecret kosong -> konstruktor melempar (API menolak start) KECUALI
// environment Development: memakai secret acak per proses.
public class CctvStreamTokenService
{
    private readonly byte[] _key;
    private readonly TimeSpan _lifetime;

    public CctvStreamTokenService(IOptions<CctvOptions> options, IHostEnvironment env, ILogger<CctvStreamTokenService> logger)
    {
        var o = options.Value;
        _lifetime = TimeSpan.FromMinutes(o.StreamTokenMinutes is > 0 and <= 60 ? o.StreamTokenMinutes : 10);

        if (string.IsNullOrWhiteSpace(o.StreamTokenSecret))
        {
            if (!env.IsDevelopment())
            {
                const string pesan =
                    "Cctv:StreamTokenSecret kosong. Isi dengan nilai acak minimal 32 karakter di appsettings " +
                    "server atau env var Cctv__StreamTokenSecret. API tidak dijalankan tanpa secret ini.";
                logger.LogCritical(pesan);
                throw new InvalidOperationException(pesan);
            }

            _key = RandomNumberGenerator.GetBytes(32);
            logger.LogWarning("Cctv:StreamTokenSecret kosong -- Development memakai secret acak per proses " +
                              "(token stream tidak berlaku lagi setelah API restart).");
        }
        else
        {
            if (o.StreamTokenSecret.Length < 32)
            {
                const string pesan = "Cctv:StreamTokenSecret wajib minimal 32 karakter.";
                logger.LogCritical(pesan);
                throw new InvalidOperationException(pesan);
            }

            _key = Encoding.UTF8.GetBytes(o.StreamTokenSecret);
        }
    }

    public (string Token, DateTimeOffset ExpiresAt) Create(string path, int userId)
    {
        if (!CctvPathRules.IsValidPath(path))
            throw new ArgumentException("Path kamera tidak valid.", nameof(path));

        var expiresAt = DateTimeOffset.UtcNow.Add(_lifetime);
        var payload = string.Create(CultureInfo.InvariantCulture, $"{path}|{expiresAt.ToUnixTimeSeconds()}|{userId}");
        var payloadBytes = Encoding.UTF8.GetBytes(payload);
        var sig = HMACSHA256.HashData(_key, payloadBytes);

        return (WebEncoders.Base64UrlEncode(payloadBytes) + "." + WebEncoders.Base64UrlEncode(sig), expiresAt);
    }

    public CctvTokenCheck Validate(string? token, string path)
    {
        if (string.IsNullOrWhiteSpace(token)) return CctvTokenCheck.Missing;

        var dot = token.IndexOf('.');
        if (dot <= 0 || dot == token.Length - 1 || token.IndexOf('.', dot + 1) >= 0) return CctvTokenCheck.Invalid;

        byte[] payloadBytes, sig;
        try
        {
            payloadBytes = WebEncoders.Base64UrlDecode(token[..dot]);
            sig = WebEncoders.Base64UrlDecode(token[(dot + 1)..]);
        }
        catch (FormatException)
        {
            return CctvTokenCheck.Invalid;
        }

        var expected = HMACSHA256.HashData(_key, payloadBytes);
        if (!CryptographicOperations.FixedTimeEquals(expected, sig)) return CctvTokenCheck.Invalid;

        var parts = Encoding.UTF8.GetString(payloadBytes).Split('|');
        if (parts.Length != 3 || !long.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out var exp))
            return CctvTokenCheck.Invalid;

        if (DateTimeOffset.UtcNow.ToUnixTimeSeconds() > exp) return CctvTokenCheck.Expired;

        if (!string.Equals(parts[0], path, StringComparison.Ordinal)) return CctvTokenCheck.WrongPath;

        return CctvTokenCheck.Ok;
    }
}

// Prompt 92: validasi path kamera & nama file yang diteruskan proxy. Tujuan proxy SELALU
// base URL dari konfigurasi; input user hanya boleh menyumbang path + nama file yang lolos aturan ini.
public static partial class CctvPathRules
{
    [GeneratedRegex("^[A-Za-z0-9_-]{1,50}$")]
    private static partial Regex PathRegex();

    [GeneratedRegex("^[A-Za-z0-9_.-]{1,120}$")]
    private static partial Regex FileSegmentRegex();

    public static bool IsValidPath(string? path) => path is not null && PathRegex().IsMatch(path);

    // File HLS dari MediaMTX: index.m3u8, *_stream.m3u8, *_init.mp4, *_seg*.mp4, *_part*.mp4.
    // Boleh bertingkat dengan "/", tetapi tiap bagian wajib lolos regex, tanpa ".", "..",
    // tanpa "//" (bagian kosong), dan tanpa skema URL (":" tidak lolos regex).
    public static bool IsValidFile(string? file)
    {
        if (string.IsNullOrEmpty(file) || file.Length > 300) return false;

        var segments = file.Split('/');
        if (segments.Length > 4) return false;

        foreach (var s in segments)
        {
            if (s.Length == 0 || s == "." || s == ".." || s.Contains("..")) return false;
            if (!FileSegmentRegex().IsMatch(s)) return false;
        }

        return true;
    }
}
