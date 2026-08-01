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
    public int QtyRejectRework { get; set; }
    public int QtyLost { get; set; }
    public string? Remark { get; set; }
    // Prompt 14: konfirmasi sadar melebihi kuota qty masuk step ini.
    public bool ConfirmExceed { get; set; }
    // Prompt 14b: konfirmasi sadar serahan kurang dari kuota qty masuk step ini.
    public bool ConfirmShort { get; set; }
    // Prompt 39: hanya terisi dari form "Kirim Hasil" (COMPLETE) saat BundleScanCard
    // menampilkan dropdown pelaksana (SuggestedResourceId terisi + station tidak
    // terkunci) -- pemanggil pakai ini kalau ada, fallback ke resource sesi kalau NULL.
    // TIDAK dipakai untuk EDIT (UPDATE tidak pernah mengubah resource_id).
    public int? ResourceId { get; set; }
}
