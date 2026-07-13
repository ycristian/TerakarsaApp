namespace TerakarsaApp.API.Services;

public static class FileNamingHelper
{
    public static string Sanitize(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var chars = name.Select(c => invalid.Contains(c) ? ' ' : c).ToArray();
        var cleaned = string.Join(" ", new string(chars).Split(' ', StringSplitOptions.RemoveEmptyEntries));
        return string.IsNullOrWhiteSpace(cleaned) ? "file" : cleaned;
    }
}
