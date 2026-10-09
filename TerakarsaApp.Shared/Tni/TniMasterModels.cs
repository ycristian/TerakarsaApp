namespace TerakarsaApp.Shared.Tni;

// Prompt 61: DTO master module PDH TNI AD -- order aktif + pola.
// Satu bentuk DTO dipakai untuk pola KEMEJA maupun CELANA (dibedakan JenisItem);
// kolom yang tidak relevan untuk satu jenis dikembalikan NULL oleh SP.

public class TniOrderAktifDto
{
    public int OrderId { get; set; }
    public string OrderCode { get; set; } = string.Empty;
    public string OrderName { get; set; } = string.Empty;
    public string? Instansi { get; set; }
    public int Tahun { get; set; }
    public int TargetQty { get; set; }
    public int TotalPersonel { get; set; }
    public int JumlahArea { get; set; }
    public int JumlahSatuan { get; set; }
}

public class TniPolaDto
{
    public int PolaId { get; set; }
    public string JenisItem { get; set; } = string.Empty;   // KEMEJA | CELANA
    public string Kode { get; set; } = string.Empty;
    public string? KodeAlt { get; set; }                    // kemeja saja, mis. "14,5-3"
    public string TargetGender { get; set; } = string.Empty;
    public int? SizeAngka { get; set; }                     // celana saja
    public decimal? LingkarDadaAcuan { get; set; }          // kemeja saja
    public bool IsActive { get; set; }

    // ukuran jadi kemeja
    public decimal? LingkarKerah { get; set; }
    public decimal? LebarBahu { get; set; }
    public decimal? LingkarDada { get; set; }
    public decimal? LingkarPerut { get; set; }
    public decimal? LingkarPinggul { get; set; }            // dipakai kedua jenis
    public decimal? PanjangBaju { get; set; }
    public decimal? LingkarLengan { get; set; }
    public decimal? LingkarKerungLengan { get; set; }
    public decimal? PanjangLengan { get; set; }
    public decimal? LingkarManset { get; set; }             // hijab saja (WH / WH_PG)

    // ukuran jadi celana
    public decimal? LingkarPinggang { get; set; }
    public decimal? LingkarSelangkang { get; set; }
    public decimal? LingkarPaha { get; set; }
    public decimal? LingkarLutut { get; set; }
    public decimal? LingkarKaki { get; set; }
    public decimal? PanjangCelana { get; set; }

    // jumlah personel hidup di order aktif yang memakai pola ini
    public int JumlahPemakai { get; set; }

    // -------- bantuan tampilan (tidak dikirim SP) --------
    public bool IsKemeja => JenisItem == "KEMEJA";
    public bool IsHijab => TargetGender is "WH" or "WH_PG";
    public bool BolehHapus => JumlahPemakai == 0;

    public string TargetGenderLabel => TargetGender switch
    {
        "P" => "Pria",
        "PG" => "Pria Gemuk",
        "W" => "Wanita",
        "W_PG" => "Wanita Gemuk",
        "WH" => "Wanita Hijab",
        "WH_PG" => "Wanita Hijab Gemuk",
        _ => TargetGender
    };
}

// Satu request untuk kedua jenis; SP yang menegakkan field mana yang wajib.
public class TniPolaSaveRequest
{
    public int? PolaId { get; set; }                        // null = pola baru
    public string JenisItem { get; set; } = "KEMEJA";
    public string Kode { get; set; } = string.Empty;
    public string? KodeAlt { get; set; }
    public string TargetGender { get; set; } = "P";
    public int? SizeAngka { get; set; }
    public decimal? LingkarDadaAcuan { get; set; }

    public decimal? LingkarKerah { get; set; }
    public decimal? LebarBahu { get; set; }
    public decimal? LingkarDada { get; set; }
    public decimal? LingkarPerut { get; set; }
    public decimal? LingkarPinggul { get; set; }
    public decimal? PanjangBaju { get; set; }
    public decimal? LingkarLengan { get; set; }
    public decimal? LingkarKerungLengan { get; set; }
    public decimal? PanjangLengan { get; set; }
    public decimal? LingkarManset { get; set; }

    public decimal? LingkarPinggang { get; set; }
    public decimal? LingkarSelangkang { get; set; }
    public decimal? LingkarPaha { get; set; }
    public decimal? LingkarLutut { get; set; }
    public decimal? LingkarKaki { get; set; }
    public decimal? PanjangCelana { get; set; }
}

public class TniPolaSetAktifRequest
{
    public bool IsActive { get; set; }
}
