namespace TerakarsaApp.Shared.Inv;

// Prompt 72: DTO movement module Stok Benang -- Terima, Ambil (whole/split),
// Kembali & timbang, Pindah rak, Habis, plus hasil scan & lookup.
//
// CATATAN pemetaan EF: seluruh action inv.SIS_ThreadMovement_Manage mengembalikan
// result set dengan BENTUK SAMA, jadi satu DTO (ThreadMovementResultDto) cukup.

public class ThreadMovementResultDto
{
    public int? MovementId { get; set; }
    public int? ThreadSplitConeId { get; set; }   // terisi untuk action split & RETURN
    public string? ConeCode { get; set; }         // kode kones split hasil RETURN
    public int? WeightGram { get; set; }
}

public class ThreadMovementDto
{
    public int MovementId { get; set; }
    public string MovementType { get; set; } = string.Empty;
    public int ThreadItemId { get; set; }
    public string? ConeCode { get; set; }
    public string? FromCode { get; set; }
    public string? ToCode { get; set; }
    public int? QtyWhole { get; set; }
    public int? WeightGram { get; set; }
    public int? ResourceId { get; set; }
    public string? ResourceName { get; set; }
    public int? ProjectId { get; set; }
    public string? ProjectName { get; set; }
    public string? ReasonCode { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedByName { get; set; }

    // -------- bantuan tampilan (mengikuti blok "Riwayat terakhir" TabletBeranda.dc.html) --------
    public string TypeLabel => MovementType switch
    {
        "RECEIVE" => "TERIMA",
        "ISSUE" => "AMBIL",
        "ISSUE_SPLIT" => "AMBIL SPLIT",
        "RETURN" => "KEMBALI",
        "RETURN_SPLIT" => "TIMBANG ULANG",
        "MOVE" => "PINDAH",
        "MOVE_SPLIT" => "PINDAH SPLIT",
        "ADJUST" => "OPNAME",
        "ADJUST_SPLIT" => "OPNAME SPLIT",
        "EMPTY" => "HABIS",
        _ => MovementType
    };

    // Warna aksen: hijau = masuk/ambil, amber = split/kembali, biru = opname.
    public string TypeColor => MovementType switch
    {
        "RECEIVE" => "var(--bn-teal)",
        "ISSUE" or "ISSUE_SPLIT" => "var(--bn-teal)",
        "RETURN" or "RETURN_SPLIT" => "var(--bn-amber)",
        "ADJUST" or "ADJUST_SPLIT" => "var(--bn-blue)",
        "EMPTY" => "var(--bn-red)",
        _ => "var(--bn-mut)"
    };

    // "6 whole dari A1 → Line 2 · PO TNI AD" / "SP-000412 · 420 g dari Line 1 → A1"
    public string Keterangan
    {
        get
        {
            var bagian = new List<string>();

            if (!string.IsNullOrWhiteSpace(ConeCode))
                bagian.Add(WeightGram.HasValue ? $"{ConeCode} · {WeightGram:N0} g" : ConeCode!);
            else if (QtyWhole.HasValue)
                bagian.Add($"{Math.Abs(QtyWhole.Value)} whole");

            var arah = new List<string>();
            if (!string.IsNullOrWhiteSpace(FromCode)) arah.Add(FromCode!);
            else if (MovementType is ("RETURN" or "RETURN_SPLIT") && !string.IsNullOrWhiteSpace(ResourceName))
                arah.Add(ResourceName!);

            if (!string.IsNullOrWhiteSpace(ToCode)) arah.Add(ToCode!);
            else if (MovementType is ("ISSUE" or "ISSUE_SPLIT") && !string.IsNullOrWhiteSpace(ResourceName))
                arah.Add(ResourceName!);

            if (arah.Count > 0) bagian.Add(string.Join(" → ", arah));
            if (!string.IsNullOrWhiteSpace(ProjectName)) bagian.Add(ProjectName!);
            if (!string.IsNullOrWhiteSpace(Note)) bagian.Add(Note!);

            return string.Join(" · ", bagian);
        }
    }

    // Kolom kanan: perubahan saldo.
    public string Delta => !string.IsNullOrWhiteSpace(ConeCode)
        ? MovementType switch
        {
            "RETURN" => "+1 split",
            "ISSUE_SPLIT" => "−1 split",
            "EMPTY" => "−1 split",
            _ => $"{WeightGram:N0} g"
        }
        : QtyWhole.HasValue
            ? (QtyWhole.Value < 0 ? $"−{Math.Abs(QtyWhole.Value)}" : $"+{QtyWhole.Value}")
            : string.Empty;
}

// Prompt 73: satu baris print_jobs label benang (status cetak di UI).
public class ThreadLabelJobDto
{
    public int PrintJobId { get; set; }
    public string JobType { get; set; } = string.Empty;
    public int RefId { get; set; }
    public string Status { get; set; } = string.Empty;   // PENDING | PRINTING | DONE | ERROR
    public string? ErrorMessage { get; set; }
    public DateTime? PrintedAt { get; set; }
    public DateTime CreatedAt { get; set; }

    public string StatusLabel => Status switch
    {
        "PENDING" => "Menunggu printer",
        "PRINTING" => "Sedang dicetak",
        "DONE" => "Tercetak",
        "ERROR" => "Gagal",
        _ => Status
    };

    public string StatusColor => Status switch
    {
        "DONE" => "var(--bn-teal)",
        "ERROR" => "var(--bn-red)",
        _ => "var(--bn-amber)"
    };
}

public class ThreadResourceLookupDto
{
    public int ResourceId { get; set; }
    public string ResourceName { get; set; } = string.Empty;
    public string? DivisionName { get; set; }

    public string Label => string.IsNullOrWhiteSpace(DivisionName)
        ? ResourceName
        : $"{ResourceName} · {DivisionName}";
}

public class ThreadProjectLookupDto
{
    public int ProjectId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }

    public string Label => string.IsNullOrWhiteSpace(NoPo)
        ? ProjectName
        : $"{ProjectName} · {NoPo}";
}

// Hasil `GET scan/{code}`: isi QR `TB:<sku_code>` atau `TS:<cone_code>`.
public class ThreadScanResultDto
{
    public string Kind { get; set; } = "UNKNOWN";   // ITEM | SPLIT | UNKNOWN
    public ThreadItemDto? Item { get; set; }
    public ThreadSplitConeDto? Cone { get; set; }   // terisi untuk Kind = SPLIT
    public string? RawCode { get; set; }
}

// -------------------- request movement --------------------

public class ThreadReceiveRequest
{
    public int ThreadItemId { get; set; }
    public int ToLocationId { get; set; }
    public int Qty { get; set; }
    public int? ProjectId { get; set; }
    public string? Note { get; set; }
}

public class ThreadIssueRequest
{
    public int ThreadItemId { get; set; }
    public int FromLocationId { get; set; }
    public int Qty { get; set; }
    public int ResourceId { get; set; }
    public int? ProjectId { get; set; }             // null -> Note wajib (ditegakkan SP)
    public string? Note { get; set; }
}

public class ThreadReturnRequest
{
    public int ThreadItemId { get; set; }
    public int WeightGram { get; set; }             // netto, tanpa tube
    public int ToLocationId { get; set; }
    public int? ResourceId { get; set; }            // kembali dari line mana
    public int? ProjectId { get; set; }
    public string? Note { get; set; }
}

public class ThreadIssueSplitRequest
{
    public int ThreadSplitConeId { get; set; }
    public int ResourceId { get; set; }
    public int? ProjectId { get; set; }
    public string? Note { get; set; }
}

public class ThreadReturnSplitRequest
{
    public int ThreadSplitConeId { get; set; }
    public int WeightGram { get; set; }
    public int ToLocationId { get; set; }
    public string? Note { get; set; }
}

public class ThreadMoveRequest
{
    public int ThreadItemId { get; set; }
    public int FromLocationId { get; set; }
    public int ToLocationId { get; set; }
    public int Qty { get; set; }
    public string? Note { get; set; }
}

public class ThreadMoveSplitRequest
{
    public int ThreadSplitConeId { get; set; }
    public int ToLocationId { get; set; }
    public string? Note { get; set; }
}

public class ThreadEmptyRequest
{
    public int ThreadSplitConeId { get; set; }
    public string? Note { get; set; }
}
