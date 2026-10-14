using System.Net.Security;
using System.Net.Sockets;
using System.Security.Cryptography.X509Certificates;

namespace TerakarsaApp.Mobile.Services;

// Prompt 76: mengambil sertifikat server lokal untuk DITAMPILKAN ke admin (TOFU).
//
// Callback validasi di sini sengaja menerima apa saja -- tujuannya BUKAN memercayai
// server, tapi melihat sertifikatnya supaya fingerprint-nya bisa disetujui manual.
// Yang dipercaya saat memakai app hanya fingerprint yang tersimpan di
// AppPrefs.LocalCertSha256 (lihat ServerResolver & TerakarsaWebViewClient).
internal static class SertifikatLokal
{
    public static async Task<(bool Ok, string Pesan, string SidikJari)> AmbilAsync(string webBaseUrl)
    {
        if (!Uri.TryCreate(ServerResolver.ApiBaseUrlFrom(webBaseUrl), UriKind.Absolute, out var api))
            return (false, "Alamat lokal belum benar.", string.Empty);

        if (api.Scheme != "https")
            return (false, "Alamat lokal bukan https — tidak ada sertifikat untuk diambil.", string.Empty);

        try
        {
            using var tcp = new TcpClient();
            await tcp.ConnectAsync(api.Host, api.Port).WaitAsync(TimeSpan.FromSeconds(3));

            await using var ssl = new SslStream(tcp.GetStream(), false, (_, _, _, _) => true);
            await ssl.AuthenticateAsClientAsync(api.Host);

            var cert = ssl.RemoteCertificate;
            if (cert is null) return (false, "Server tidak mengirim sertifikat.", string.Empty);

            using var x509 = X509CertificateLoader.LoadCertificate(cert.GetRawCertData());
            return (true, $"{x509.Subject} (berlaku s/d {x509.NotAfter:dd MMM yyyy})",
                    ServerResolver.SidikJari(x509));
        }
        catch (Exception ex)
        {
            return (false, ex.Message, string.Empty);
        }
    }
}
