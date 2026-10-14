namespace TerakarsaApp.Shared.Inv;

// Prompt 74: DTO stock opname benang.
//
// Stok sistem & hasil opname TERPISAH: DTO di sini hanya membawa fakta fisik
// (counted_qty) + snapshot sistem (system_qty). Perubahan stok terjadi lewat
// movement ADJUST/MOVE yang dibuat saat sesi ditutup.

public class ThreadOpnameSessionDto
{
    public int SessionId { get; set; }
    public string SessionNo { get; set; } = string.Empty;    // SO26-0001
    public string Status { get; set; } = string.Empty;       // OPEN | CLOSED
    public DateTime StartedAt { get; set; }
    public DateTime? ClosedAt { get; set; }
    public string? StartedByName { get; set; }
    public string? Note { get; set; }

    public int TotalRak { get; set; }
    public int RakSelesai { get; set; }
    public int TotalSku { get; set; }
    public int SkuDihitung { get; set; }
    public int SkuSelisih { get; set; }

    public bool IsOpen => Status == "OPEN";
    public string ProgresRak => $"{RakSelesai}/{TotalRak} rak";
    public string ProgresSku => $"Sudah dihitung {SkuDihitung} dari {TotalSku} SKU";
}

public class ThreadOpnameLocationDto
{
    public int SessionId { get; set; }
    public int ThreadLocationId { get; set; }
    public string Code { get; set; } = string.Empty;
    public string? Name { get; set; }
    public string Status { get; set; } = string.Empty;       // PENDING | DRAFT | DONE
    public int TotalSku { get; set; }
    public int SkuDihitung { get; set; }
    public int SkuSelisih { get; set; }

    public bool Selesai => Status == "DONE";

    // Teks kanan di panel rak (mockup TabletOpname): "selesai" / "3 / 7" / "12 SKU".
    public string ProgresLabel => Selesai
        ? "selesai"
        : SkuDihitung > 0 ? $"{SkuDihitung} / {TotalSku}" : $"{TotalSku} SKU";

    public string ProgresColor => Selesai
        ? "var(--bn-teal)"
        : SkuDihitung > 0 ? "var(--bn-blue)" : "var(--bn-mut)";
}

public class ThreadOpnameLineDto
{
    public int LineId { get; set; }
    public int SessionId { get; set; }
    public int ThreadLocationId { get; set; }
    public string LocationCode { get; set; } = string.Empty;
    public int ThreadItemId { get; set; }
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string ConeSize { get; set; } = string.Empty;
    public string? PhotoPath { get; set; }
    public string TypeName { get; set; } = string.Empty;
    public string BrandName { get; set; } = string.Empty;

    public int SystemQty { get; set; }
    public int? CountedQty { get; set; }                    // null = belum dihitung
    public int SplitExpected { get; set; }
    public int? SplitFound { get; set; }
    public string? Resolution { get; set; }
    public DateTime? CountedAt { get; set; }
    public string? CountedByName { get; set; }

    // -------- bantuan tampilan (mockup Opname.dc.html) --------
    public bool SudahDihitung => CountedQty.HasValue;
    public int Diff => (CountedQty ?? SystemQty) - SystemQty;
    public bool Cocok => SudahDihitung && Diff == 0;
    public bool AdaFoto => !string.IsNullOrWhiteSpace(PhotoPath);

    public string Judul => string.IsNullOrWhiteSpace(ColorCode) ? ColorName : $"{ColorName} · {ColorCode}";
    public string Keterangan => $"{TypeName} · {BrandName} · {ConeSize}";

    // "Cocok" / "Selisih −2" / "belum"
    public string DiffLabel => !SudahDihitung ? "belum"
        : Diff == 0 ? "Cocok"
        : Diff > 0 ? $"Selisih +{Diff}" : $"Selisih −{Math.Abs(Diff)}";

    public string DiffColor => !SudahDihitung ? "var(--bn-mut)"
        : Diff == 0 ? "var(--bn-teal)" : "var(--bn-amber)";

    // "2 kones · ada 2"
    public string SplitLabel => SplitExpected == 0 && (SplitFound ?? 0) == 0
        ? "0 kones"
        : $"{SplitExpected} kones · ada {SplitFound ?? 0}";

    public bool SplitSelisih => SudahDihitung && (SplitFound ?? 0) != SplitExpected;
}

public class ThreadOpnameSplitDto
{
    public int OpnameSplitId { get; set; }
    public int LineId { get; set; }
    public int ThreadSplitConeId { get; set; }
    public string ConeCode { get; set; } = string.Empty;
    public int WeightGram { get; set; }
    public bool? IsFound { get; set; }                      // null = belum dicek
    public string? SystemLocationCode { get; set; }
}

// Satu usulan hasil PREVIEW_CLOSE. ProposalId hanya nomor urut sementara.
public class ThreadOpnameProposalDto
{
    public int ProposalId { get; set; }
    public string Kind { get; set; } = string.Empty;        // WHOLE | SPLIT
    public string ActionUsulan { get; set; } = string.Empty; // MOVE | ADJUST | MOVE_SPLIT | ADJUST_SPLIT
    public int LineId { get; set; }
    public int ThreadItemId { get; set; }
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public string TypeName { get; set; } = string.Empty;
    public string BrandName { get; set; } = string.Empty;
    public int? FromLocationId { get; set; }
    public string? FromCode { get; set; }
    public int? ToLocationId { get; set; }
    public string? ToCode { get; set; }
    public int? Qty { get; set; }
    public int? SystemQty { get; set; }
    public int? CountedQty { get; set; }
    public int? ThreadSplitConeId { get; set; }
    public string? ConeCode { get; set; }
    public int? WeightGram { get; set; }
    public bool ReasonRequired { get; set; }

    public string Judul => string.IsNullOrWhiteSpace(ColorCode) ? ColorName : $"{ColorName} · {ColorCode}";

    public string ActionLabel => ActionUsulan switch
    {
        "MOVE" => "Pindah rak",
        "ADJUST" => Qty > 0 ? "Tambah stok" : "Kurangi stok",
        "MOVE_SPLIT" => "Pindah kones split",
        "ADJUST_SPLIT" => "Kones hilang",
        _ => ActionUsulan
    };

    public string Rincian => ActionUsulan switch
    {
        "MOVE" => $"{Qty} kones {FromCode} → {ToCode}",
        "ADJUST" => $"{(Qty > 0 ? "+" : "−")}{Math.Abs(Qty ?? 0)} kones di {FromCode ?? ToCode}"
                    + (SystemQty.HasValue ? $" (sistem {SystemQty}, fisik {CountedQty})" : string.Empty),
        "MOVE_SPLIT" => $"{ConeCode} {FromCode ?? "-"} → {ToCode}",
        "ADJUST_SPLIT" => $"{ConeCode} · {WeightGram} g tidak ditemukan di {FromCode}",
        _ => string.Empty
    };
}

// Baris hasil sesi yang sudah ditutup (riwayat).
public class ThreadOpnameResultDto
{
    public int LineId { get; set; }
    public string LocationCode { get; set; } = string.Empty;
    public string SkuCode { get; set; } = string.Empty;
    public string ColorName { get; set; } = string.Empty;
    public string ColorCode { get; set; } = string.Empty;
    public int SystemQty { get; set; }
    public int? CountedQty { get; set; }
    public int SplitExpected { get; set; }
    public int? SplitFound { get; set; }
    public string? Resolution { get; set; }
    public string? MovementType { get; set; }
    public int? MovementQty { get; set; }
    public string? ReasonCode { get; set; }
    public string? ReasonName { get; set; }
    public string? Note { get; set; }
    public string? MovementFromCode { get; set; }
    public string? MovementToCode { get; set; }
    public string? CountedByName { get; set; }
    public DateTime? CountedAt { get; set; }

    public int Diff => (CountedQty ?? SystemQty) - SystemQty;

    public string DiffLabel => Diff == 0 ? "cocok" : Diff > 0 ? $"+{Diff}" : $"−{Math.Abs(Diff)}";

    public string ResolusiLabel => Resolution switch
    {
        "MOVE" => $"Pindah {MovementFromCode} → {MovementToCode}",
        "ADJUST" => $"Sesuaikan {(MovementQty > 0 ? "+" : "−")}{Math.Abs(MovementQty ?? 0)}"
                    + (string.IsNullOrWhiteSpace(ReasonName) ? string.Empty : $" · {ReasonName}"),
        "NONE" => "Tidak ada perubahan",
        _ => "-"
    };
}

public class ThreadReasonCodeDto
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public bool RequiresNote { get; set; }
    public int SortOrder { get; set; }
}

// Gabungan hasil inv.SIS_ThreadOpname_Current (dirakit di API).
public class ThreadOpnameCurrentDto
{
    public ThreadOpnameSessionDto? Session { get; set; }
    public List<ThreadOpnameLocationDto> Locations { get; set; } = new();
}

public class ThreadOpnameRakDto
{
    public List<ThreadOpnameLineDto> Lines { get; set; } = new();
    public List<ThreadOpnameSplitDto> Splits { get; set; } = new();
}

public class ThreadOpnameDetailDto
{
    public ThreadOpnameSessionDto? Session { get; set; }
    public List<ThreadOpnameResultDto> Results { get; set; } = new();
}

// -------------------- request --------------------

public class ThreadOpnameOpenRequest
{
    // Kosong = semua rak aktif.
    public List<int> LocationIds { get; set; } = new();
    public string? Note { get; set; }
}

public class ThreadOpnameAddLineRequest
{
    public int SessionId { get; set; }
    public int LocationId { get; set; }
    public int ThreadItemId { get; set; }
}

public class ThreadOpnameSplitFoundDto
{
    public int SplitConeId { get; set; }
    public bool IsFound { get; set; }
}

public class ThreadOpnameCountRequest
{
    public int LineId { get; set; }
    public int CountedQty { get; set; }
    public List<ThreadOpnameSplitFoundDto> Splits { get; set; } = new();
}

public class ThreadOpnameResolutionDto
{
    public int LineId { get; set; }
    public string Action { get; set; } = "ADJUST";          // MOVE | ADJUST | NONE | MOVE_SPLIT | ADJUST_SPLIT
    public int? Qty { get; set; }
    public int? FromLocationId { get; set; }
    public int? ToLocationId { get; set; }
    public int? SplitConeId { get; set; }
    public string? ReasonCode { get; set; }
    public string? Note { get; set; }
}

public class ThreadOpnameCloseRequest
{
    public int SessionId { get; set; }
    public List<ThreadOpnameResolutionDto> Resolutions { get; set; } = new();
    public string? Note { get; set; }
}
