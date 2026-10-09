namespace TerakarsaApp.Shared.Tni;

// Prompt 64: stok kemeja & celana PDH TNI AD.
// Stok ANONIM per pola; saldo selalu SUM(qty) tni.stok_mutasi (tidak ada tabel
// saldo). Angka di DTO ini semuanya berasal dari tni.v_stok_pola.

public class TniStokSaldoDto
{
    public string JenisItem { get; set; } = string.Empty;   // KEMEJA | CELANA
    public int PolaId { get; set; }
    public string Kode { get; set; } = string.Empty;
    public bool IsActive { get; set; }

    public int Masuk { get; set; }
    public int Terpakai { get; set; }        // positif (sudah dibalik tandanya)
    public int KeluarLain { get; set; }      // RUSAK + KOREKSI
    public int Bongkar { get; set; }
    public int Saldo { get; set; }

    public int Dijatah { get; set; }         // personel DICETAK dengan pola ini
    public int StokBebas { get; set; }       // saldo - dijatah
    public int KebutuhanSisa { get; set; }   // BELUM_CETAK + DICETAK

    // P | PG | W | WH (kemeja), P | W (celana); baris sudah terurut per grup.
    public string GrupGender { get; set; } = string.Empty;

    // Saldo minus = setoran kemungkinan belum dicatat (scan tidak pernah diblok).
    public bool SaldoMinus => Saldo < 0;

    // Saldo kurang dari kebutuhan -> perlu diproduksi.
    // 2026-10-07: dulu KebutuhanSisa - StokBebas -- personel DICETAK terhitung DUA
    // KALI (ada di KebutuhanSisa DAN sudah dipotong dari StokBebas). Sekarang
    // sama dengan dashboard: Butuh - Saldo.
    public bool Kurang => Saldo < KebutuhanSisa;
    public int Kekurangan => Math.Max(0, KebutuhanSisa - Saldo);
}

// Urutan SEMUA tampilan stok (2026-10-07): grup gender P, PG, W, WH (celana P, W),
// lalu angka pola. W_PG ikut grup W dan WH_PG ikut WH, di bawah ukuran biasanya.
// Data dari SP sudah terurut (tni.v_stok_pola.urut_*); helper ini untuk label
// grup dan untuk daftar pola yang tidak lewat SP stok (dropdown setoran).
public static class TniUrutStok
{
    public static string Grup(string targetGender) =>
        targetGender.StartsWith("WH") ? "WH"
        : targetGender.StartsWith("W") ? "W"
        : targetGender;

    public static string Label(string grup) => grup switch
    {
        "P"  => "Pria",
        "PG" => "Pria Gemuk",
        "W"  => "Wanita",
        "WH" => "Wanita Hijab",
        _    => grup
    };

    public static List<TniPolaDto> Urutkan(IEnumerable<TniPolaDto> pola) =>
        pola.OrderBy(p => Grup(p.TargetGender) switch { "P" => 1, "PG" => 2, "W" => 3, "WH" => 4, _ => 9 })
            .ThenBy(p => p.TargetGender is "W_PG" or "WH_PG" ? 1 : 0)
            .ThenBy(p => p.LingkarDadaAcuan ?? p.SizeAngka ?? 0)
            .ThenBy(p => p.Kode)
            .ToList();
}

// Satu baris isian setoran.
public class TniStokSetoranItem
{
    public string JenisItem { get; set; } = "KEMEJA";
    public int PolaId { get; set; }
    public int Qty { get; set; }
}

public class TniStokSetoranRequest
{
    public DateTime? Tanggal { get; set; }
    public string? Supplier { get; set; }   // teks bebas, opsional (alter_73)
    public List<TniStokSetoranItem> Items { get; set; } = new();
}

public class TniStokSetoranHasilDto
{
    public int JumlahBaris { get; set; }
    public int? TotalKemeja { get; set; }
    public int? TotalCelana { get; set; }
    public int SetoranId { get; set; }
    public bool Digabung { get; set; }      // tanggal & supplier sama -> masuk ke setoran yang sudah ada
}

// 2026-10-07 (alter_77): satu PENGELUARAN = banyak pola, sama seperti setoran.
// Qty tiap baris POSITIF; tanda dari arah: RUSAK selalu kurangi,
// KOREKSI pakai Arah (1 tambah | -1 kurangi). Alasan wajib.
public class TniStokKeluarRequest
{
    public DateTime? Tanggal { get; set; }
    public string JenisMutasi { get; set; } = "RUSAK";   // RUSAK | KOREKSI
    public int Arah { get; set; } = -1;                   // KOREKSI saja
    public string? Alasan { get; set; }
    public List<TniStokSetoranItem> Items { get; set; } = new();
}

public class TniStokMutasiDto
{
    public int MutasiId { get; set; }
    public string? Supplier { get; set; }   // hanya setoran (MASUK)
    public string JenisItem { get; set; } = string.Empty;
    public string Kode { get; set; } = string.Empty;
    public string JenisMutasi { get; set; } = string.Empty;
    public int Qty { get; set; }
    public string? Alasan { get; set; }
    public DateTime Tanggal { get; set; }
    public string? PersonelKodeRef { get; set; }
    public string? PersonelNama { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedByNama { get; set; }
    public int TotalCount { get; set; }

    // Mutasi manual boleh dihapus; TERPAKAI & BONGKAR milik scan/pembatalan.
    public bool BolehHapus => JenisMutasi is "MASUK" or "RUSAK" or "KOREKSI";

    public string JenisMutasiLabel => JenisMutasi switch
    {
        "MASUK" => "Setoran",
        "TERPAKAI" => "Terpakai",
        "RUSAK" => "Rusak",
        "BONGKAR" => "Bongkar",
        "KOREKSI" => "Koreksi",
        _ => JenisMutasi
    };
}

public class TniStokRiwayatResult
{
    public List<TniStokMutasiDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
}

// Tab Riwayat (2026-10-07): satu ENTRI = satu setoran (banyak pola) atau satu
// mutasi RUSAK/KOREKSI. SP mengembalikan baris datar (satu per mutasi);
// UI mengelompokkan lewat (EntriTipe, EntriId). Paging per entri.
public class TniStokRiwayatManualRow
{
    public string EntriTipe { get; set; } = string.Empty;   // SETORAN | KELUAR
    public int EntriId { get; set; }                         // setoran_id | mutasi_id
    public int EntriUrut { get; set; }
    public int TotalEntri { get; set; }

    public DateTime Tanggal { get; set; }
    public string? Supplier { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedByNama { get; set; }
    public DateTime? UpdatedAt { get; set; }                 // header setoran saja

    public int MutasiId { get; set; }
    public string JenisMutasi { get; set; } = string.Empty;
    public string JenisItem { get; set; } = string.Empty;
    public int PolaId { get; set; }
    public string? Kode { get; set; }
    public int Qty { get; set; }
    public string? Alasan { get; set; }
}

public class TniStokRiwayatManualResult
{
    public List<TniStokRiwayatManualRow> Items { get; set; } = new();
    public int TotalEntri { get; set; }
}
