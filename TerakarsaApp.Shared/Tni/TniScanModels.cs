namespace TerakarsaApp.Shared.Tni;

// Prompt 66: scan "Set Jadi" & halaman QR /t/{token} PDH TNI AD.

public class TniScanRequest
{
    // Boleh qr_token ATAU kode_ref (input manual bila QR rusak).
    public string Kode { get; set; } = string.Empty;
}

// Satu result set dari tni.SIS_Scan_SetJadi -- bukan exception, supaya UI bisa
// membedakan warna hasil tanpa membaca pesan error.
public class TniScanHasilDto
{
    public string Hasil { get; set; } = string.Empty;     // OK | SUDAH | TIDAK_DIKENAL | DITOLAK | KONFIRMASI (masuk box beda satuan, 2026-10-07)
    public string Pesan { get; set; } = string.Empty;

    public int? PersonelId { get; set; }
    public string? KodeRef { get; set; }
    public string? Pangkat { get; set; }
    public string? Nama { get; set; }
    public string? SatuanName { get; set; }
    public string? PolaKemejaKode { get; set; }
    public string? PolaCelanaKode { get; set; }
    public DateTime? SetAt { get; set; }
    public string? SetByNama { get; set; }

    // Saldo SETELAH dikurangi. Boleh minus -- scan tidak pernah diblok karena stok.
    public int? SaldoKemeja { get; set; }
    public int? SaldoCelana { get; set; }

    // --- dipakai juga oleh scan Masuk Box (Prompt 67) ---
    public string? BoxCode { get; set; }
    public int? Isi { get; set; }
    public int? Kapasitas { get; set; }

    public bool Ok => Hasil == "OK";
    public bool Sudah => Hasil == "SUDAH";
    public bool PerluKonfirmasi => Hasil == "KONFIRMASI";

    public bool StokMinus => (SaldoKemeja ?? 0) < 0 || (SaldoCelana ?? 0) < 0;

    public string? PolaMinus =>
        (SaldoKemeja ?? 0) < 0 ? PolaKemejaKode
        : (SaldoCelana ?? 0) < 0 ? PolaCelanaKode
        : null;
}

// Halaman publik /t/{token} tanpa login -- HANYA data minimal.
// SENGAJA tanpa NRP, No HP, dan ukuran badan.
public class TniPublicPersonelDto
{
    public string KodeRef { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string? SatuanName { get; set; }

    // 2026-10-06 diizinkan owner untuk publik. No HP & ukuran badan TETAP tidak.
    public string? Nrp { get; set; }
    public string? PolaKemejaKode { get; set; }
    public string? PolaCelanaKode { get; set; }
    public int? TinggiBadan { get; set; }
    public int? BeratBadan { get; set; }
    public string? Kategori { get; set; }
    public string? AreaName { get; set; }

    public string StatusProgres { get; set; } = string.Empty;
    public DateTime? SetAt { get; set; }
    public string? BoxCode { get; set; }
    public DateTime? BoxedAt { get; set; }
    public DateTime? ShippedAt { get; set; }

    public string KategoriLabel => Kategori == "TU_SIZING" ? "T.U : Sizing" : "Diukur";
}

// Komplain ukuran dari halaman QR /t/{token} -- boleh tanpa perangkat/login.
public class TniKomplainRequest
{
    public string NoTelp { get; set; } = string.Empty;
    public string Komentar { get; set; } = string.Empty;   // boleh berbaris banyak
}

// Daftar komplain -- HANYA untuk perangkat terdaftar (berisi no telp).
public class TniKomplainDto
{
    public int KomplainId { get; set; }
    public string NoTelp { get; set; } = string.Empty;
    public string Komentar { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }
    public string? PetugasNama { get; set; }
}

// Satu baris riwayat sesi scan (hanya di memori halaman, tidak disimpan).
public class TniScanRiwayatItem
{
    public string Hasil { get; set; } = string.Empty;
    public string? KodeRef { get; set; }
    public string? Nama { get; set; }
    public string Pesan { get; set; } = string.Empty;
    public DateTime Jam { get; set; } = DateTime.Now;

    // Prompt 68: dipakai sheet aksi "Ajukan batal" di layar scan.
    // Terisi untuk hasil OK MAUPUN SUDAH (kartu dikenal). Status terkini TIDAK
    // ditebak dari mode scan -- sheet membacanya ulang dari server saat dibuka,
    // jadi kartu yang sudah lanjut ke box/terkirim tetap ditangani benar.
    public int? PersonelId { get; set; }
    public string? StatusProgres { get; set; }
    public string? BoxCode { get; set; }

    public bool BolehAjukanBatal => PersonelId.HasValue;
}
