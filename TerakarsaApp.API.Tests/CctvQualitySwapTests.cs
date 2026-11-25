using TerakarsaApp.API.Services;
using TerakarsaApp.Shared.Cctv;

namespace TerakarsaApp.API.Tests;

// Prompt 97, uji terima 8: fungsi murni penukar kualitas pada URL source path MediaMTX.
// Kredensial di bawah palsu (contoh), bukan kode kamera sungguhan.
public class CctvQualitySwapTests
{
    private const string Pre = "rtsp://user:KODE@192.168.8.75:554/Streaming/Channels/";

    [Fact]
    public void Sub_dengan_slash_ke_Main()
    {
        var r = CctvMediaMtxClient.SwapQuality(Pre + "102/", CctvRecordQuality.Main);
        Assert.True(r.Supported);
        Assert.Equal(Pre + "101/", r.Source);
        Assert.Equal(CctvRecordQuality.Sub, r.CurrentQuality);
    }

    [Fact]
    public void Main_tanpa_slash_ke_Sub()
    {
        var r = CctvMediaMtxClient.SwapQuality(Pre + "101", CctvRecordQuality.Sub);
        Assert.True(r.Supported);
        Assert.Equal(Pre + "102", r.Source);
        Assert.Equal(CctvRecordQuality.Main, r.CurrentQuality);
    }

    [Fact]
    public void Channel_dua_digit_tidak_berubah()
    {
        var r = CctvMediaMtxClient.SwapQuality(Pre + "1002", CctvRecordQuality.Main);
        Assert.True(r.Supported);
        Assert.Equal(Pre + "1001", r.Source);
        Assert.Equal(CctvRecordQuality.Sub, r.CurrentQuality);
    }

    [Fact]
    public void Kualitas_sudah_sama_tetap_didukung_dan_url_sama()
    {
        var r = CctvMediaMtxClient.SwapQuality(Pre + "102/", CctvRecordQuality.Sub);
        Assert.True(r.Supported);
        Assert.Equal(Pre + "102/", r.Source);
        Assert.Equal(CctvRecordQuality.Sub, r.CurrentQuality);
    }

    [Theory]
    [InlineData("rtsp://user:KODE@192.168.8.75:554/h264/ch1/main/av_stream")]
    [InlineData("rtsp://user:KODE@192.168.8.75:554/Streaming/Channels/103/")]
    [InlineData("rtsp://user:KODE@192.168.8.75:554/Streaming/Channels/02")]
    [InlineData("rtsp://user:KODE@192.168.8.75:554/Streaming/Channels/102?transportmode=unicast")]
    [InlineData("")]
    [InlineData(null)]
    public void Url_tidak_cocok_tidak_didukung(string? source)
    {
        var r = CctvMediaMtxClient.SwapQuality(source, CctvRecordQuality.Main);
        Assert.False(r.Supported);
        Assert.Null(r.Source);
    }

    [Fact]
    public void Kualitas_tidak_dikenal_tidak_didukung()
    {
        Assert.False(CctvMediaMtxClient.SwapQuality(Pre + "102/", "HD").Supported);
    }

    [Fact]
    public void ToString_tidak_membocorkan_source()
    {
        var r = CctvMediaMtxClient.SwapQuality(Pre + "102/", CctvRecordQuality.Main);
        Assert.DoesNotContain("KODE", r.ToString());
        Assert.DoesNotContain("KODE", new CctvMtxSourceResult(CctvMtxCallOutcome.Ok, Pre + "102/").ToString());
    }

    [Fact]
    public void MaskCredentials_menyamarkan_user_dan_kode()
    {
        var masked = CctvMediaMtxClient.MaskCredentials(Pre + "102/");
        Assert.Equal("rtsp://***@192.168.8.75:554/Streaming/Channels/102/", masked);
    }
}
