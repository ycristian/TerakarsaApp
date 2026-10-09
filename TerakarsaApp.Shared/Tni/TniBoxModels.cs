namespace TerakarsaApp.Shared.Tni;

// Prompt 67: box & scan "Masuk Box" PDH TNI AD.
//
// Status box TIDAK disimpan sebagai kolom -- diturunkan dari packed_at/shipped_at
// oleh SP (TERBUKA / TERTUTUP / TERKIRIM). Kode box tidak pernah diganti maupun
// didaur ulang.

public class TniBoxListItemDto
{
    public int BoxId { get; set; }
    public string BoxCode { get; set; } = string.Empty;

    // alter_72: nomor urut box dalam ORDER (1, 2, 3, ...) -- beda dengan
    // BoxCode yang urut per satuan. Untuk "box ke berapa" & pencarian.
    public int BoxNo { get; set; }

    public int AreaId { get; set; }
    public string AreaCode { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;
    public int? SatuanId { get; set; }
    public string? SatuanCode { get; set; }
    public string SatuanName { get; set; } = string.Empty;   // 'Gabungan' bila box gabungan
    public bool Gabungan { get; set; }
    public int Urut { get; set; }
    public int Kapasitas { get; set; }
    public int Isi { get; set; }
    public int JumlahSatuan { get; set; }                    // satuan berbeda di dalam box
    public DateTime? PackedAt { get; set; }
    public string? PackedByNama { get; set; }
    public DateTime? ShippedAt { get; set; }
    public string? ShippedByNama { get; set; }
    public string? Keterangan { get; set; }
    public string Status { get; set; } = string.Empty;       // TERBUKA | TERTUTUP | TERKIRIM

    public bool Terbuka => Status == "TERBUKA";
    public bool Tertutup => Status == "TERTUTUP";
    public bool Terkirim => Status == "TERKIRIM";

    // PDF hanya tersedia untuk box tertutup/terkirim.
    public bool BolehPdf => !Terbuka;
    public bool BolehHapus => Terbuka && Isi == 0;
    public bool Penuh => Isi >= Kapasitas;

    public int Persen => Kapasitas == 0 ? 0 : Math.Min(100, (int)Math.Round(Isi * 100.0 / Kapasitas));
}

public class TniBoxHeaderDto : TniBoxListItemDto
{
    public int OrderId { get; set; }
    public string OrderName { get; set; } = string.Empty;
    public string? Instansi { get; set; }
}

public class TniBoxIsiDto
{
    public int PersonelId { get; set; }
    public int? UrutDalamBox { get; set; }
    public string KodeRef { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string Nrp { get; set; } = string.Empty;
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
    public string AreaCode { get; set; } = string.Empty;    // rawatan personel (2026-10-07)
    public string AreaName { get; set; } = string.Empty;
    public string PolaKemejaKode { get; set; } = string.Empty;
    public string PolaCelanaKode { get; set; } = string.Empty;
    public DateTime? BoxedAt { get; set; }
}

public class TniBoxRekapDto
{
    public string JenisItem { get; set; } = string.Empty;   // KEMEJA | CELANA
    public string Kode { get; set; } = string.Empty;
    public int Jumlah { get; set; }
}

public class TniBoxDetailDto
{
    public TniBoxHeaderDto? Header { get; set; }
    public List<TniBoxIsiDto> Isi { get; set; } = new();
    public List<TniBoxRekapDto> Rekap { get; set; } = new();

    public List<TniBoxRekapDto> RekapKemeja =>
        Rekap.Where(x => x.JenisItem == "KEMEJA").ToList();

    public List<TniBoxRekapDto> RekapCelana =>
        Rekap.Where(x => x.JenisItem == "CELANA").ToList();
}

public class TniBoxCreateRequest
{
    // Box satuan: isi SatuanId. Box gabungan: kosongkan SatuanId, isi AreaId.
    public int? SatuanId { get; set; }
    public int? AreaId { get; set; }
    public int? Kapasitas { get; set; }
}

public class TniBoxCreateHasilDto
{
    public int BoxId { get; set; }
    public string BoxCode { get; set; } = string.Empty;
    public int Urut { get; set; }
    public int BoxNo { get; set; }
}

public class TniBoxAksiHasilDto
{
    public int Isi { get; set; }
}

// Scan "Masuk Box" -- hasilnya memakai TniScanHasilDto yang sama dengan Set Jadi
// (Prompt 66), dengan BoxCode/Isi/Kapasitas terisi.
public class TniMasukBoxRequest
{
    public string Kode { get; set; } = string.Empty;
    public int BoxId { get; set; }
    // 2026-10-07: true = petugas sudah konfirmasi "beda satuan / rawatan" (Hasil KONFIRMASI)
    public bool Paksa { get; set; }
}
