namespace TerakarsaApp.Client.Shared;

// Nilai form "Selesaikan" dari BundleScanCard — pemanggil (StationDevice.razor /
// BundleScanPublic.razor) yang merakit StationCompleteRequest lengkap (menambahkan
// ArticleWorkflowId dari Info.Action dan ResourceId dari sesi operator).
public class BundleCompleteFormValues
{
    public int QtyOk { get; set; }
    public int QtyRejectPrint { get; set; }
    public int QtyRejectFabric { get; set; }
    public int QtyRejectSewing { get; set; }
    public string? Remark { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini.
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
}
