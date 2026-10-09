namespace TerakarsaApp.Shared.Tni;

// Prompt 63: beranda module & halaman Personel PDH TNI AD.
// Status SELALU berasal dari tni.v_personel.status_progres (BELUM_CETAK,
// DICETAK, SET_JADI, MASUK_BOX, TERKIRIM) -- jangan menurunkannya ulang di UI.

public class TniBerandaSummaryDto
{
    public int Total { get; set; }
    public int Dicetak { get; set; }              // status <> BELUM_CETAK
    public int DapatSet { get; set; }             // SET_JADI + MASUK_BOX + TERKIRIM
    public int MasukBox { get; set; }             // MASUK_BOX + TERKIRIM
    public int Terkirim { get; set; }
    public int SetBelumBox { get; set; }          // SET_JADI
    public int KartuBelumScan { get; set; }       // DICETAK
    public int PerluReview { get; set; }
    public int PembatalanMenunggu { get; set; }

    public int PersenBox => Total == 0 ? 0 : (int)Math.Round(MasukBox * 100.0 / Total);
    public int PersenKirim => Total == 0 ? 0 : (int)Math.Round(Terkirim * 100.0 / Total);
}

public class TniPersonelListItemDto
{
    public int PersonelId { get; set; }
    public string KodeRef { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string Nrp { get; set; } = string.Empty;
    public int AreaId { get; set; }
    public int SatuanId { get; set; }
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;
    public string PolaKemejaKode { get; set; } = string.Empty;
    public string PolaCelanaKode { get; set; } = string.Empty;
    public string StatusProgres { get; set; } = string.Empty;
    public string? BoxCode { get; set; }
    public string StatusData { get; set; } = string.Empty;
    public int TotalCount { get; set; }           // diulang di tiap baris oleh SP

    public bool PerluReview => StatusData == "PERLU_REVIEW";
}

public class TniPersonelListResult
{
    public List<TniPersonelListItemDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
}

public class TniPersonelDetailDto
{
    public int PersonelId { get; set; }
    public int OrderId { get; set; }
    public string KodeRef { get; set; } = string.Empty;
    public int NoUrut { get; set; }
    public string QrToken { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string Nama { get; set; } = string.Empty;
    public string Nrp { get; set; } = string.Empty;
    public string? NoHp { get; set; }
    public string Gender { get; set; } = string.Empty;
    public int? TinggiBadan { get; set; }
    public int? BeratBadan { get; set; }
    public string Kategori { get; set; } = string.Empty;

    public int AreaId { get; set; }
    public string AreaCode { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;
    public int SatuanId { get; set; }
    public string SatuanCode { get; set; } = string.Empty;
    public string SatuanName { get; set; } = string.Empty;

    public int PolaKemejaId { get; set; }
    public string PolaKemejaKode { get; set; } = string.Empty;
    public int PolaCelanaId { get; set; }
    public string PolaCelanaKode { get; set; } = string.Empty;

    // ukuran JADI pola (pembanding ukuran badan)
    public decimal? PolaKemejaLingkarKerah { get; set; }
    public decimal? PolaKemejaLebarBahu { get; set; }
    public decimal? PolaKemejaLingkarDada { get; set; }
    public decimal? PolaKemejaLingkarPerut { get; set; }
    public decimal? PolaKemejaLingkarPinggul { get; set; }
    public decimal? PolaKemejaPanjangBaju { get; set; }
    public decimal? PolaKemejaLingkarLengan { get; set; }
    public decimal? PolaKemejaLingkarKerungLengan { get; set; }
    public decimal? PolaKemejaPanjangLengan { get; set; }
    public decimal? PolaKemejaLingkarManset { get; set; }

    public decimal? PolaCelanaLingkarPinggang { get; set; }
    public decimal? PolaCelanaLingkarPinggul { get; set; }
    public decimal? PolaCelanaLingkarSelangkang { get; set; }
    public decimal? PolaCelanaLingkarPaha { get; set; }
    public decimal? PolaCelanaLingkarLutut { get; set; }
    public decimal? PolaCelanaLingkarKaki { get; set; }
    public decimal? PolaCelanaPanjangCelana { get; set; }

    // 8 ukuran badan kemeja
    public decimal? LingkarLeher { get; set; }
    public decimal? LebarBahu { get; set; }
    public decimal? LingkarDada { get; set; }
    public decimal? LingkarPerut { get; set; }
    public decimal? PanjangBadanDepan { get; set; }
    public decimal? PanjangLengan { get; set; }
    public decimal? LingkarLengan { get; set; }
    public decimal? LingkarKetiak { get; set; }

    // 7 ukuran badan celana
    public decimal? LingkarPinggangCelana { get; set; }
    public decimal? LingkarPinggul { get; set; }
    public decimal? LingkarPesak { get; set; }
    public decimal? LingkarPaha { get; set; }
    public decimal? LingkarLutut { get; set; }
    public decimal? LingkarCelanaBawah { get; set; }
    public decimal? PanjangCelana { get; set; }

    public string? SizeBajuIsian { get; set; }
    public string? SizeCelanaIsian { get; set; }
    public string? EmailPengisi { get; set; }
    public DateTime? SubmittedAt { get; set; }

    public string StatusData { get; set; } = string.Empty;
    public string? CatatanReview { get; set; }

    public string StatusProgres { get; set; } = string.Empty;
    public DateTime? PrintedAt { get; set; }
    public string? PrintedByNama { get; set; }
    public int PrintCount { get; set; }
    public DateTime? SetAt { get; set; }
    public string? SetByNama { get; set; }
    public DateTime? BoxedAt { get; set; }
    public string? BoxedByNama { get; set; }
    public int? BoxId { get; set; }
    public string? BoxCode { get; set; }
    public int? UrutDalamBox { get; set; }
    public DateTime? BoxPackedAt { get; set; }
    public DateTime? BoxShippedAt { get; set; }

    // ---------- bantuan tampilan ----------
    public bool PerluReview => StatusData == "PERLU_REVIEW";
    public bool TidakHadirUkur => Kategori == "TU_SIZING";
    public bool SudahSet => SetAt.HasValue;
    public bool BolehHapus => !PrintedAt.HasValue;

    public string GenderLabel => Gender switch
    {
        "PRIA" => "Pria",
        "WANITA_HIJAB" => "Wanita — Hijab",
        "WANITA_NON_HIJAB" => "Wanita — Non Hijab",
        _ => Gender
    };

    public string KategoriLabel => Kategori == "TU_SIZING" ? "T.U : Sizing" : "Diukur";
}

public class TniPersonelUpdateRequest
{
    public string Nrp { get; set; } = string.Empty;
    public string Nama { get; set; } = string.Empty;
    public string? Pangkat { get; set; }
    public string? NoHp { get; set; }
    public string Gender { get; set; } = "PRIA";
}

public class TniPersonelSetPolaRequest
{
    public int PolaKemejaId { get; set; }
    public int PolaCelanaId { get; set; }
}

public class TniPersonelCatatanRequest
{
    public string? Catatan { get; set; }
}

// Satu baris area x satuan dari tni.SIS_Wilayah_List (satuan boleh NULL kalau
// area belum punya satuan).
public class TniWilayahRowDto
{
    public int AreaId { get; set; }
    public string AreaCode { get; set; } = string.Empty;
    public string AreaName { get; set; } = string.Empty;
    public int? SatuanId { get; set; }
    public string? SatuanCode { get; set; }
    public string? SatuanName { get; set; }
}
