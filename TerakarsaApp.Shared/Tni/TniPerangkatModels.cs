namespace TerakarsaApp.Shared.Tni;

// Perangkat TNI (tanpa login) -- 2026-10-02.
//
// Modul /tni dipakai SEPERTI STASIUN: masuk dengan KODE PAIRING, bukan login.
// TERPISAH dari tabel `stations` -- perangkat TNI tidak terikat divisi maupun
// resource produksi.
//
// 2026-10-06 (alter_75): SATU nama petugas per perangkat (NamaPetugas), tanpa
// pemilihan petugas. Jejak kerja menyimpan perangkat_id; created_by tetap user
// sistem `tni_system`.

// alter_74: daftar menu /tni yang bisa diizinkan per perangkat. SATU sumber untuk
// tile Beranda, gerbang TniLayout, dan centang di halaman pengelolaan perangkat.
// Kode harus sama dengan CK_tni_perangkat_menu_code.
public record TniMenu(string Code, string Label, string Route, string Icon)
{
    public static readonly IReadOnlyList<TniMenu> Semua = new[]
    {
        new TniMenu("PERINTAH_KERJA", "Perintah Kerja", "/tni/perintah-kerja", "fe fe-clipboard"),
        new TniMenu("SCAN",           "Scan",           "/tni/scan",           "fe fe-maximize"),
        new TniMenu("BOX",            "Box",            "/tni/box",            "fe fe-package"),
        new TniMenu("STOK",           "Stok",           "/tni/stok",           "fe fe-layers"),
        new TniMenu("PERSONEL",       "Personel",       "/tni/personel",       "fe fe-users"),
        new TniMenu("DASHBOARD",      "Dashboard",      "/tni/dashboard",      "fe fe-bar-chart-2"),
        new TniMenu("IMPORT",         "Import",         "/tni/import",         "fe fe-upload"),
        new TniMenu("POLA",           "Master Pola",    "/tni/pola",           "fe fe-grid")
    };

    // Menu pemilik sebuah path ("/tni/box/12" -> BOX). null = bukan halaman menu
    // (mis. beranda /tni) -> selalu boleh.
    public static TniMenu? DariPath(string path)
    {
        var p = "/" + (path ?? string.Empty).Split('?', '#')[0].Trim('/').ToLowerInvariant();
        return Semua.FirstOrDefault(m => p == m.Route || p.StartsWith(m.Route + "/"));
    }
}

public class TniPerangkatDto
{
    public int PerangkatId { get; set; }
    public string PerangkatCode { get; set; } = string.Empty;
    public string PerangkatName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public string? Keterangan { get; set; }
    public DateTime? PairedAt { get; set; }
    public DateTime? LastSeenAt { get; set; }

    // Hanya terisi selama kode masih berlaku (15 menit).
    public string? PairingCode { get; set; }
    public DateTime? PairingCodeExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; }

    // alter_75: satu-satunya petugas perangkat ini.
    public string NamaPetugas { get; set; } = string.Empty;

    // alter_74: kode menu yang diizinkan, dipisah koma.
    public string? MenuAkses { get; set; }
    public List<string> MenuList => (MenuAkses ?? string.Empty)
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();

    public bool Terhubung => PairedAt.HasValue;
    public bool AdaKodeAktif => !string.IsNullOrEmpty(PairingCode);
}

// Identitas perangkat yang sedang memegang token -- dipakai header halaman.
public class TniPerangkatMeDto
{
    public int PerangkatId { get; set; }
    public string PerangkatCode { get; set; } = string.Empty;
    public string PerangkatName { get; set; } = string.Empty;
    public string NamaPetugas { get; set; } = string.Empty;   // alter_75
    public DateTime? PairedAt { get; set; }

    // alter_74: menu yang boleh dibuka perangkat ini, dipisah koma.
    public string? MenuAkses { get; set; }

    public bool BolehMenu(string code) =>
        (MenuAkses ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Contains(code, StringComparer.OrdinalIgnoreCase);
}

public class TniPerangkatCreateRequest
{
    public string PerangkatCode { get; set; } = string.Empty;
    public string PerangkatName { get; set; } = string.Empty;
    public string NamaPetugas { get; set; } = string.Empty;   // alter_75: wajib
    public string? Keterangan { get; set; }
    public bool IsActive { get; set; } = true;

    // alter_74: kode menu yang diizinkan. null saat CREATE = semua menu;
    // null saat UPDATE = tidak diubah.
    public List<string>? Menu { get; set; }
}

public class TniPairingCodeDto
{
    public string PairingCode { get; set; } = string.Empty;
    public DateTime ExpiresAt { get; set; }
}

public class TniClaimRequest
{
    public string PairingCode { get; set; } = string.Empty;
}

// Token dikembalikan SEKALI saja, saat klaim berhasil.
public class TniClaimResultDto
{
    public string Token { get; set; } = string.Empty;
    public TniPerangkatMeDto? Perangkat { get; set; }
}
