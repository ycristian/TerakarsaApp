namespace TerakarsaApp.Shared.Reports;

// Prompt 30: Laporan Produksi Periode Gajian -- read-only, dipakai oleh
// ReportProduksiController (halaman /reports/produksi, module REPORT_PRODUKSI). Lihat
// sql/sp_Report_Produksi.sql untuk definisi Qty Done/Menunggu QC/WIP/Reject.

public class ProduksiAggRowDto
{
    public int? LineResourceId { get; set; }
    public string LineResourceName { get; set; } = string.Empty;
    public int PoId { get; set; }
    public string? PoNumber { get; set; }
    public string PoName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public int QtyDone { get; set; }
    public int QtyMenungguQc { get; set; }
    public int QtyWip { get; set; }
    public int QtyReject { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? RejectDetail { get; set; }
}

public class ProduksiDetailRowDto
{
    public int? LineResourceId { get; set; }
    public string LineResourceName { get; set; } = string.Empty;
    public string PelaksanaName { get; set; } = string.Empty;
    public int PoId { get; set; }
    public string? PoNumber { get; set; }
    public string PoName { get; set; } = string.Empty;
    public int ArticleId { get; set; }
    public string ArticleName { get; set; } = string.Empty;
    public int? BundleId { get; set; }
    public int? BundleNo { get; set; }
    public string? BundleSerial { get; set; }
    public string SizeName { get; set; } = string.Empty;
    public int QtyDone { get; set; }
    public int QtyMenungguQc { get; set; }
    public int QtyWip { get; set; }
    public int QtyReject { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? RejectDetail { get; set; }
}

public class ProduksiSummaryDto
{
    public int QtyDone { get; set; }
    public int QtyMenungguQc { get; set; }
    public int QtyWip { get; set; }
    public int QtyReject { get; set; }
    public int PelaksanaAktif { get; set; }
}

public class ProduksiReportResultDto
{
    public ProduksiSummaryDto Summary { get; set; } = new();
    public List<ProduksiAggRowDto> Agg { get; set; } = new();
    public List<ProduksiDetailRowDto> Detail { get; set; } = new();
}
