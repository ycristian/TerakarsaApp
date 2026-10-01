namespace TerakarsaApp.Shared.UnlockRequests;

// Prompt 57: module admin "Request Unlock" (UNLOCK_REQUEST) -- daftar & detail pengajuan buka
// lock dari stasiun, plus keputusan APPROVE/REJECT. Read dari SIS_UnlockRequest_List /
// SIS_UnlockRequest_Detail (sql/sp_UnlockRequest_Select.sql); tulis tetap lewat
// SIS_UnlockRequest_Manage (Prompt 55, tidak diubah).

// Bentuk yang sama dipakai baris daftar DAN header halaman detail (result set 1).
public class UnlockRequestListItemDto
{
    public int RequestId { get; set; }
    public DateTime CreatedAt { get; set; }             // waktu ajukan
    public int DivisionId { get; set; }
    public string DivisionName { get; set; } = string.Empty;
    public string? StationName { get; set; }            // NULL = bukan dari perangkat stasiun
    public string? RequestedByResourceName { get; set; }
    public string Reason { get; set; } = string.Empty;
    public int JumlahBaris { get; set; }
    // Total SEMUA kategori qty dari snapshot lock (ok + 4 reject + hilang), bukan cuma qty_ok.
    public int TotalQty { get; set; }
    public string State { get; set; } = "PENDING";      // PENDING / APPROVED / REJECTED
    public DateTime? DecidedAt { get; set; }
    public string? DecidedByName { get; set; }
    public string? AdminNote { get; set; }
    // Ada lock item di periode gajian yang sudah final -- APPROVE pasti ditolak SP.
    public bool PeriodeFinal { get; set; }
    // CATATAN: jangan tambah properti hanya-baca (computed) di kelas ini -- dipetakan langsung
    // oleh EF Core SqlQueryRaw, setiap properti harus punya kolom padanan di SP.
}

// Satu baris log yang diminta dibuka. Sebelum = snapshot saat di-lock, Sekarang = nilai
// terkini baris log (untuk request yang masih menunggu keduanya selalu sama -- baris masih
// terkunci, tidak ada jalur yang bisa mengubahnya).
public class UnlockRequestItemDto
{
    public int RequestItemId { get; set; }
    public int WorkflowLogId { get; set; }
    public string ProjectName { get; set; } = string.Empty;
    public string? NoPo { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public string? Style { get; set; }
    public string? Color { get; set; }
    public string StepName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? BundleLetter { get; set; }
    public string? Serial { get; set; }
    public string? SizeName { get; set; }
    public string? PenjahitName { get; set; }

    public string PeriodeLock { get; set; } = string.Empty;   // period_code lock yang diminta dilepas
    public DateTime LockedAt { get; set; }
    public bool PeriodeLockFinal { get; set; }

    public int SebelumQtyOk { get; set; }
    public int SebelumQtyRejectPrint { get; set; }
    public int SebelumQtyRejectFabric { get; set; }
    public int SebelumQtyRejectSewing { get; set; }
    public int SebelumQtyRejectRework { get; set; }
    public int SebelumQtyLost { get; set; }
    public string? SebelumSizeName { get; set; }
    public string? SebelumResourceName { get; set; }

    public int SekarangQtyOk { get; set; }
    public int SekarangQtyRejectPrint { get; set; }
    public int SekarangQtyRejectFabric { get; set; }
    public int SekarangQtyRejectSewing { get; set; }
    public int SekarangQtyRejectRework { get; set; }
    public int SekarangQtyLost { get; set; }
    public string? SekarangSizeName { get; set; }
    public string? SekarangResourceName { get; set; }
    public bool IsDeleted { get; set; }                       // baris log sudah soft delete

    // Terisi hanya kalau baris sudah di-lock ULANG setelah dibuka (lock aktif sekarang bukan
    // lock yang dilepas request ini).
    public string? LockUlangPeriode { get; set; }
    public DateTime? LockUlangLockedAt { get; set; }

    public bool Berubah { get; set; }

    public int SebelumTotalReject => SebelumQtyRejectPrint + SebelumQtyRejectFabric
        + SebelumQtyRejectSewing + SebelumQtyRejectRework;
    public int SekarangTotalReject => SekarangQtyRejectPrint + SekarangQtyRejectFabric
        + SekarangQtyRejectSewing + SekarangQtyRejectRework;
}

public class UnlockRequestDetailDto
{
    public UnlockRequestListItemDto? Header { get; set; }
    public List<UnlockRequestItemDto> Items { get; set; } = new();
}

public class UnlockRequestDecisionRequest
{
    // Opsional saat APPROVE, WAJIB saat REJECT (ditegakkan SP).
    public string? AdminNote { get; set; }
}
