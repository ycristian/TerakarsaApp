namespace TerakarsaApp.PrintService;

public class PrintWorkerOptions
{
    public string ApiBaseUrl { get; set; } = string.Empty;
    public string ApiKey { get; set; } = string.Empty;
    public string PrinterName { get; set; } = string.Empty;
    public int PollSeconds { get; set; } = 5;
    public int BatchSize { get; set; } = 5;
    public bool DryRun { get; set; } = false;
}
