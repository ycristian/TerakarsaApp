namespace TerakarsaApp.Shared.Inv;

// Prompt 75: DTO riwayat movement, ringkasan landing, matriks lokasi, dan
// pemakaian per project. Semua READ-ONLY.

// Satu baris riwayat movement (inv.SIS_ThreadMovement_List). Lebih lengkap dari
// ThreadMovementDto (Prompt 72, riwayat per SKU): membawa identitas SKU, nama alasan,
// dan nomor sesi opname.
public class ThreadMovementRowDto
{
    public int MovementId { get; set; }
    public string MovementType { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; }

    public int ThreadItemId { get; set; }
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string BrandName { get; set; } = string.Empty;

    public string? ConeCode { get; set; }
    public string? FromCode { get; set; }
    public string? ToCode { get; set; }
    public int? QtyWhole { get; set; }
    public int? WeightGram { get; set; }

    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? ProjectId { get; set; }
    public string? ProjectName { get; set; }
    public string? NoPo { get; set; }

    public string? ReasonCode { get; set; }
    public string? ReasonName { get; set; }
    public string? Note { get; set; }

    public int CreatedBy { get; set; }
    public string? CreatedByName { get; set; }

    public int? OpnameLineId { get; set; }
    public int? OpnameSessionId { get; set; }
    public string? OpnameSessionNo { get; set; }

    public int TotalCount { get; set; }

    // -------- bantuan tampilan --------
    public string Judul => string.IsNullOrWhiteSpace(ColorCode) ? ColorName : $"{ColorName} · {ColorCode}";

    public string TypeLabel => MovementType switch
    {
        "RECEIVE" => "TERIMA",
        "ISSUE" => "AMBIL",
        "ISSUE_SPLIT" => "AMBIL SPLIT",
        "RETURN" => "KEMBALI",
        "RETURN_SPLIT" => "TIMBANG ULANG",
        "MOVE" => "PINDAH",
        "MOVE_SPLIT" => "PINDAH SPLIT",
        "ADJUST" => "PENYESUAIAN",
        "ADJUST_SPLIT" => "PENYESUAIAN SPLIT",
        "EMPTY" => "HABIS",
        _ => MovementType
    };

    // Warna sesuai prompt: ISSUE hijau tua, RETURN oranye, MOVE abu, ADJUST merah,
    // RECEIVE biru.
    public string TypeColor => MovementType switch
    {
        "RECEIVE" => "var(--bn-blue)",
        "ISSUE" or "ISSUE_SPLIT" => "var(--bn-teal)",
        "RETURN" or "RETURN_SPLIT" => "var(--bn-amber)",
        "MOVE" or "MOVE_SPLIT" => "var(--bn-mut)",
        "ADJUST" or "ADJUST_SPLIT" or "EMPTY" => "var(--bn-red)",
        _ => "var(--bn-mut)"
    };

    public bool IsAdjust => MovementType is "ADJUST" or "ADJUST_SPLIT";

    public string Jumlah => !string.IsNullOrWhiteSpace(ConeCode)
        ? $"{ConeCode}{(WeightGram.HasValue ? $" · {WeightGram:N0} g" : string.Empty)}"
        : QtyWhole.HasValue ? $"{Math.Abs(QtyWhole.Value)} kones" : "-";

    public string Arah
    {
        get
        {
            var bagian = new List<string>();
            if (!string.IsNullOrWhiteSpace(FromCode)) bagian.Add(FromCode!);
            if (!string.IsNullOrWhiteSpace(ToCode)) bagian.Add(ToCode!);
            return bagian.Count == 0 ? "-" : string.Join(" → ", bagian);
        }
    }

    public string Delta => QtyWhole.HasValue
        ? (QtyWhole.Value < 0 ? $"−{Math.Abs(QtyWhole.Value)}" : $"+{QtyWhole.Value}")
        : !string.IsNullOrWhiteSpace(ConeCode)
            ? MovementType switch
            {
                "RETURN" => "+1 split",
                "ISSUE_SPLIT" => "−1 split",
                "EMPTY" or "ADJUST_SPLIT" => "−1 split",
                _ => $"{WeightGram:N0} g"
            }
            : string.Empty;
}

public class ThreadMovementListResult
{
    public List<ThreadMovementRowDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
}

public class ThreadStockTotalDto
{
    public int SkuAktif { get; set; }
    public int SkuTotal { get; set; }
    public int WholeTotal { get; set; }
    public int SplitKones { get; set; }
    public int SplitGram { get; set; }
    public int SplitDiLine { get; set; }
    public int SplitDiLineGram { get; set; }
    public int LokasiAktif { get; set; }
    public int? OpnameSessionId { get; set; }
    public string? OpnameSessionNo { get; set; }
}

public class ThreadTodayDto
{
    public string MovementType { get; set; } = string.Empty;
    public int Jumlah { get; set; }
    public int QtyWhole { get; set; }
    public int WeightGram { get; set; }
}

public class ThreadLowStockDto
{
    public int ThreadItemId { get; set; }
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string BrandName { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string? PhotoPath { get; set; }
    public int QtyWholeTotal { get; set; }
    public int SplitCountInStock { get; set; }
    public int Dipakai30Hari { get; set; }

    public string Judul => string.IsNullOrWhiteSpace(ColorCode) ? ColorName : $"{ColorName} · {ColorCode}";
}

public class ThreadSummaryDto
{
    public ThreadStockTotalDto Total { get; set; } = new();
    public List<ThreadTodayDto> HariIni { get; set; } = new();
    public List<ThreadLowStockDto> Perhatian { get; set; } = new();

    public int HariIniJumlah(string movementType) =>
        HariIni.FirstOrDefault(t => t.MovementType == movementType)?.Jumlah ?? 0;

    // "n ambil · n kembali" di kartu landing.
    public int AmbilHariIni => HariIniJumlah("ISSUE") + HariIniJumlah("ISSUE_SPLIT");
    public int KembaliHariIni => HariIniJumlah("RETURN") + HariIniJumlah("RETURN_SPLIT");
    public int TerimaHariIni => HariIniJumlah("RECEIVE");
}

public class ThreadLocationStockDto
{
    public int ThreadLocationId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string? Name { get; set; }
    public bool IsActive { get; set; }
    public int SkuCount { get; set; }
    public int QtyWhole { get; set; }
    public int SplitCount { get; set; }
    public int SplitGram { get; set; }
}

public class ThreadUsageDto
{
    public int? ProjectId { get; set; }
    public string? ProjectName { get; set; }
    public string? NoPo { get; set; }
    public int ThreadItemId { get; set; }
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string BrandName { get; set; } = string.Empty;
    public int WholeIssued { get; set; }
    public int SplitGramIssued { get; set; }
    public int SplitGramReturned { get; set; }
    public int SplitGramNet { get; set; }

    public string Judul => string.IsNullOrWhiteSpace(ColorCode) ? ColorName : $"{ColorName} · {ColorCode}";
    public string ProjectLabel => string.IsNullOrWhiteSpace(NoPo)
        ? ProjectName ?? "-"
        : $"{ProjectName} · {NoPo}";
}
