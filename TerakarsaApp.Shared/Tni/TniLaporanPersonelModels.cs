namespace TerakarsaApp.Shared.Tni;

// Prompt 89: Laporan Personel & Box (PDF A4 landscape, hanya diunduh).
// Sumber: tni.SIS_LaporanPersonel (3 result set).

public class TniLaporanPersonelHeaderDto
{
    public string OrderName { get; set; } = string.Empty;
    public string? Instansi { get; set; }
    // terisi bila rawatan difilter, atau rawatan milik satuan yang difilter
    public string? AreaCode { get; set; }
    public string? AreaName { get; set; }
    // terisi bila satuan difilter
    public string? SatuanCode { get; set; }
    public string? SatuanName { get; set; }
    public int TotalBaris { get; set; }
    public int JumlahSatuan { get; set; }
    // terisi bila pola kemeja / celana difilter
    public string? PolaKemejaKode { get; set; }
    public string? PolaCelanaKode { get; set; }
}

public class TniLaporanPersonelBarisDto
{
    public string KodeRef { get; set; } = string.Empty;
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string Nrp { get; set; } = string.Empty;
    public string? NoHp { get; set; }
    // PRIA | WANITA_HIJAB | WANITA_NON_HIJAB
    public string Gender { get; set; } = string.Empty;
    public string PolaKemejaKode { get; set; } = string.Empty;
    public string PolaCelanaKode { get; set; } = string.Empty;
    // NULL = belum masuk box
    public int? BoxNo { get; set; }
    public string? BoxCode { get; set; }
}

public class TniLaporanPersonelBoxDto
{
    public int BoxNo { get; set; }
    public string BoxCode { get; set; } = string.Empty;
    public bool Gabungan { get; set; }
    // TERBUKA | TERTUTUP | TERKIRIM
    public string Status { get; set; } = string.Empty;
    public int Isi { get; set; }
    // jumlah personel lingkup laporan ini di dalam box
    public int IsiDariLingkup { get; set; }
    public DateTime? PackedAt { get; set; }
    public DateTime? ShippedAt { get; set; }
}

public class TniLaporanPersonelDto
{
    public TniLaporanPersonelHeaderDto? Header { get; set; }
    public List<TniLaporanPersonelBarisDto> Baris { get; set; } = new();
    public List<TniLaporanPersonelBoxDto> Box { get; set; } = new();

    // filter yang dipakai (untuk baris keterangan di kepala PDF)
    public string? Status { get; set; }
    public string? Search { get; set; }
    public bool PerluReview { get; set; }

    // waktu cetak lokal server
    public DateTime DicetakPada { get; set; }
}
