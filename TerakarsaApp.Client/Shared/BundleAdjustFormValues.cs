namespace TerakarsaApp.Client.Shared;

// Nilai form "Penyesuaian" dari BundleScanCard -- pemanggil (BundleScanPublic.razor) yang
// merakit StationAdjustRequest lengkap (menambahkan BundleId dari Info.Bundle dan ResourceId
// dari sesi operator). Lihat Prompt 28 / sp_WorkflowLog_Manage.sql action ADJUST.
public class BundleAdjustFormValues
{
    public int ArticleWorkflowId { get; set; }
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public int? TargetDivisionId { get; set; }
    public string? Remark { get; set; }
}
