using Microsoft.Extensions.Options;
using SkiaSharp;

namespace TerakarsaApp.API.Services;

public class ImageCompressionOptions
{
    public int MaxWidth { get; set; } = 1920;
    public int Quality { get; set; } = 80;
}

public class CompressResult
{
    public required Stream Stream { get; init; }
    public required string FileExtension { get; init; }
    public required long SizeKb { get; init; }
}

public class ImageCompressionService
{
    private static readonly string[] CompressibleExtensions = { "jpg", "jpeg", "png" };

    private readonly IOptions<ImageCompressionOptions> _options;

    public ImageCompressionService(IOptions<ImageCompressionOptions> options)
    {
        _options = options;
    }

    public async Task<CompressResult> CompressAsync(Stream input, string fileExtension)
    {
        var extension = fileExtension.TrimStart('.').ToLowerInvariant();

        if (!CompressibleExtensions.Contains(extension))
        {
            var passthrough = new MemoryStream();
            await input.CopyToAsync(passthrough);
            passthrough.Position = 0;
            return new CompressResult
            {
                Stream = passthrough,
                FileExtension = extension,
                SizeKb = (long)Math.Ceiling(passthrough.Length / 1024.0)
            };
        }

        using var original = SKBitmap.Decode(input);
        if (original is null)
            throw new InvalidOperationException("File gambar tidak dapat dibaca atau rusak.");

        var options = _options.Value;
        var source = original;
        SKBitmap? resized = null;

        try
        {
            if (original.Width > options.MaxWidth)
            {
                var newHeight = (int)Math.Round(original.Height * (options.MaxWidth / (double)original.Width));
                resized = original.Resize(new SKImageInfo(options.MaxWidth, newHeight), SKSamplingOptions.Default);
                if (resized is not null)
                    source = resized;
            }

            using var surface = SKSurface.Create(new SKImageInfo(source.Width, source.Height, SKColorType.Rgba8888, SKAlphaType.Opaque));
            var canvas = surface.Canvas;
            canvas.Clear(SKColors.White);
            canvas.DrawBitmap(source, 0, 0, SKSamplingOptions.Default);

            using var image = surface.Snapshot();
            using var data = image.Encode(SKEncodedImageFormat.Jpeg, options.Quality);

            var output = new MemoryStream();
            data.SaveTo(output);
            output.Position = 0;

            return new CompressResult
            {
                Stream = output,
                FileExtension = "jpg",
                SizeKb = (long)Math.Ceiling(output.Length / 1024.0)
            };
        }
        finally
        {
            resized?.Dispose();
        }
    }
}
