namespace TerakarsaApp.PrintService;

// Log teks harian sederhana, terpisah dari ILogger console bawaan host, supaya ada jejak
// yang gampang dibuka di PC printer tanpa perlu mengumpulkan log Windows Event/console.
public class DailyFileLogger
{
    private readonly string _logDir;
    private readonly object _lock = new();

    public DailyFileLogger()
    {
        _logDir = Path.Combine(AppContext.BaseDirectory, "logs");
        Directory.CreateDirectory(_logDir);
    }

    public void Write(string message)
    {
        var path = Path.Combine(_logDir, $"print-{DateTime.Now:yyyyMMdd}.log");
        var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}";

        lock (_lock)
        {
            File.AppendAllLines(path, new[] { line });
        }
    }
}
