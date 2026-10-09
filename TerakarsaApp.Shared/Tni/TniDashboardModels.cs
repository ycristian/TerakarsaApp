namespace TerakarsaApp.Shared.Tni;

// Prompt 69: dashboard progres & kebutuhan size PDH TNI AD.
//
// Semua angka DITURUNKAN di SQL dari tni.v_personel + tni.v_stok_pola --
// DTO ini tidak menghitung status atau saldo apa pun, hanya menyusun ulang
// untuk tampilan (persen, lebar batang, label).

// Satu baris progres; dipakai baik untuk rawatan maupun satuan.
public class TniProgresRowDto
{
    public int AreaId { get; set; }
    public string AreaCode { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;

    public int Total { get; set; }
    public int BelumCetak { get; set; }
    public int Dicetak { get; set; }        // kartu tercetak, belum dapat set
    public int SetJadi { get; set; }        // dapat set, belum masuk box
    public int MasukBox { get; set; }       // di box, belum terkirim
    public int Terkirim { get; set; }

    public decimal PersenBox { get; set; }
    public decimal PersenKirim { get; set; }

    public int BoxTerbuka { get; set; }
    public int BoxTertutup { get; set; }
    public int BoxTerkirim { get; set; }

    // Angka yang dibaca owner: sisa pekerjaan, bukan yang sudah selesai.
    public int BelumDapatSet => BelumCetak + Dicetak;
    public int BelumMasukBox => BelumCetak + Dicetak + SetJadi;

    public int TotalBox => BoxTerbuka + BoxTertutup + BoxTerkirim;

    // Lebar segmen progress bar bertumpuk, dalam persen.
    public decimal Lebar(int jumlah) => Total == 0 ? 0 : jumlah * 100m / Total;
}

public class TniProgresAreaDto : TniProgresRowDto
{
    public string? Kota { get; set; }
}

public class TniProgresSatuanDto : TniProgresRowDto
{
    public int SatuanId { get; set; }
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
}

public class TniDashboardProgresDto
{
    public List<TniProgresAreaDto> Area { get; set; } = new();
    public List<TniProgresSatuanDto> Satuan { get; set; } = new();

    // Total seluruh order -- dijumlahkan dari baris area, bukan query terpisah.
    public int Total => Area.Sum(x => x.Total);
    public int BelumDapatSet => Area.Sum(x => x.BelumDapatSet);
    public int BelumMasukBox => Area.Sum(x => x.BelumMasukBox);
    public int Terkirim => Area.Sum(x => x.Terkirim);

    public decimal PersenBox => Total == 0
        ? 0
        : Area.Sum(x => x.MasukBox + x.Terkirim) * 100m / Total;

    public List<TniProgresSatuanDto> SatuanOf(int areaId) =>
        Satuan.Where(x => x.AreaId == areaId)
              .OrderBy(x => x.PersenBox)          // paling tertinggal di atas
              .ThenBy(x => x.SatuanCode)
              .ToList();
}

// Satu pola di layar Kebutuhan size.
//
// PENTING: Butuh boleh difilter per rawatan, tapi Saldo/StokBebas SELALU
// GLOBAL -- stok tidak dibagi per area (stok anonim per pola).
public class TniKebutuhanSizeDto
{
    public int PolaId { get; set; }
    public string JenisItem { get; set; } = string.Empty;   // KEMEJA | CELANA
    public string Kode { get; set; } = string.Empty;
    public bool IsActive { get; set; }

    public int Butuh { get; set; }
    public int Saldo { get; set; }
    public int StokBebas { get; set; }
    public int Dijatah { get; set; }
    public int Selisih { get; set; }                        // Saldo - Butuh
    public string GrupGender { get; set; } = string.Empty;  // P | PG | W | WH -- urutan baris

    public bool Cukup => Selisih >= 0;
    public int Kurang => Selisih < 0 ? -Selisih : 0;
}
