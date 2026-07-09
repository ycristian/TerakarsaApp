using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace TerakarsaApp.PrintService;

// Kirim byte mentah (TSPL) ke printer Windows lewat winspool.drv -- pola standar
// OpenPrinter/StartDocPrinter/StartPagePrinter/WritePrinter/EndPagePrinter/EndDocPrinter.
// Tanpa driver/SDK khusus TSC, sesuai batasan Prompt 11.
[SupportedOSPlatform("windows")]
public static class RawPrinterHelper
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string? pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }

    [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.drv", EntryPoint = "ClosePrinter", SetLastError = true)]
    private static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi)]
    private static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFOA di);

    [DllImport("winspool.drv", EntryPoint = "EndDocPrinter", SetLastError = true)]
    private static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartPagePrinter", SetLastError = true)]
    private static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "EndPagePrinter", SetLastError = true)]
    private static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "WritePrinter", SetLastError = true)]
    private static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    public static void SendBytesToPrinter(string printerName, byte[] bytes)
    {
        if (string.IsNullOrWhiteSpace(printerName))
            throw new InvalidOperationException("Nama printer belum diisi (PrintService:PrinterName).");

        if (!OpenPrinter(printerName, out var hPrinter, IntPtr.Zero))
            throw new InvalidOperationException(
                $"Tidak bisa membuka printer '{printerName}' (Win32 error {Marshal.GetLastWin32Error()}). Pastikan printer terpasang dan namanya sama persis dengan di Windows.");

        try
        {
            var di = new DOCINFOA
            {
                pDocName = "TerakarsaApp Bundle Label",
                pOutputFile = null,
                pDataType = "RAW"
            };

            if (!StartDocPrinter(hPrinter, 1, ref di))
                throw new InvalidOperationException($"Gagal memulai dokumen cetak (Win32 error {Marshal.GetLastWin32Error()}).");

            try
            {
                if (!StartPagePrinter(hPrinter))
                    throw new InvalidOperationException($"Gagal memulai halaman cetak (Win32 error {Marshal.GetLastWin32Error()}).");

                var pUnmanagedBytes = Marshal.AllocHGlobal(bytes.Length);
                try
                {
                    Marshal.Copy(bytes, 0, pUnmanagedBytes, bytes.Length);
                    if (!WritePrinter(hPrinter, pUnmanagedBytes, bytes.Length, out var written) || written != bytes.Length)
                        throw new InvalidOperationException($"Gagal mengirim data ke printer (Win32 error {Marshal.GetLastWin32Error()}).");
                }
                finally
                {
                    Marshal.FreeHGlobal(pUnmanagedBytes);
                }

                EndPagePrinter(hPrinter);
            }
            finally
            {
                EndDocPrinter(hPrinter);
            }
        }
        finally
        {
            ClosePrinter(hPrinter);
        }
    }
}
