using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using TerakarsaApp.Client;
using TerakarsaApp.Client.Auth;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

builder.Services.AddScoped<CustomAuthStateProvider>();
builder.Services.AddScoped<Microsoft.AspNetCore.Components.Authorization.AuthenticationStateProvider>(
    sp => sp.GetRequiredService<CustomAuthStateProvider>());
builder.Services.AddAuthorizationCore();

builder.Services.AddScoped<AuthorizedHandler>();

var clientUri = new Uri(builder.HostEnvironment.BaseAddress);
var apiBaseUrl = ResolveApiBaseUrl(clientUri);

// Dua mode akses:
// - Publik lewat Cloudflare Tunnel (host *.terakarsa.id) -> API selalu di api.terakarsa.id.
// - LAN pabrik: API di-host di mesin yang sama dengan Client, port beda -- host-nya ikut
//   dari mana halaman ini dibuka (localhost saat dev di PC, IP LAN saat diakses dari device lain).
static string ResolveApiBaseUrl(Uri clientUri)
{
    if (clientUri.Host.EndsWith("terakarsa.id", StringComparison.OrdinalIgnoreCase))
    {
        return "https://api.terakarsa.id/";
    }

    var apiPort = clientUri.Scheme == "https" ? 7130 : 5281;
    return $"{clientUri.Scheme}://{clientUri.Host}:{apiPort}/";
}

builder.Services.AddHttpClient("AuthAPI", client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
});

builder.Services.AddHttpClient("API", client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
})
.AddHttpMessageHandler<AuthorizedHandler>();

builder.Services.AddScoped(sp =>
    sp.GetRequiredService<IHttpClientFactory>().CreateClient("API"));

builder.Services.AddScoped<TerakarsaApp.Client.Auth.StationTokenHandler>();

builder.Services.AddHttpClient<TerakarsaApp.Client.Services.StationDeviceApiService>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
})
.AddHttpMessageHandler<TerakarsaApp.Client.Auth.StationTokenHandler>();

builder.Services.AddScoped<TerakarsaApp.Client.Auth.DashboardTokenHandler>();

builder.Services.AddHttpClient<TerakarsaApp.Client.Services.DashboardApiService>(client =>
{
    client.BaseAddress = new Uri(apiBaseUrl);
})
.AddHttpMessageHandler<TerakarsaApp.Client.Auth.DashboardTokenHandler>();

builder.Services.AddScoped<AuthApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ProductApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.UserApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ModuleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.DivisionApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.PositionApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ResourceTypeApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ResourceApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.BuyerApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.EmployeeApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.PpicEmployeeApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ProjectApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ProjectAttachmentApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.SizePackApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ArticleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ArticlePhotoApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.WorkflowTemplateApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ArticleWorkflowApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.StationApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.WorkflowLogApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.BundleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.PublicBundleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.PublicPackApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ReportBundleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ReportWipApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ReportProduksiApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ReportActivityLogApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.SuperAdminApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.WorkScheduleApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.DailyPlanApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.DashboardTokenApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.UnlockRequestApiService>();
// Prompt 70: halaman Absensi (kartu karyawan, rekap, koreksi anomali).
builder.Services.AddScoped<TerakarsaApp.Client.Services.AttendanceApiService>();
// Prompt 71-77: module Stok Benang (/gudang/benang). Login biasa + module INV_THREAD,
// BUKAN pola perangkat tanpa login seperti /tni.
builder.Services.AddScoped<TerakarsaApp.Client.Services.ThreadStockApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ThreadOpnameApiService>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.ThreadReportApiService>();
// Prompt 77: halaman /admin/printer (routing job cetak PC vs HP Bluetooth).
builder.Services.AddScoped<TerakarsaApp.Client.Services.PrintAdminApiService>();
// Prompt 78-80: module Cutting (stok bundle dari hamparan).
builder.Services.AddScoped<TerakarsaApp.Client.Services.CuttingApiService>();
// Module PDH TNI AD -- dipakai SEPERTI STASIUN, TANPA LOGIN: tiap service di
// bawah ini memakai HttpClient sendiri yang menyisipkan header X-Tni-Token
// (TniDeviceTokenHandler), BUKAN JWT. Petugas dikenali server dari perangkat.
// Satu-satunya yang masih lewat JWT: endpoint PUTUSAN pembatalan -- lihat
// TniPembatalanApiService, yang memegang dua client sekaligus.
builder.Services.AddScoped<TerakarsaApp.Client.Auth.TniDeviceTokenHandler>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.TniOrderState>();
builder.Services.AddScoped<TerakarsaApp.Client.Services.TniPerangkatState>();

void AddTniClient<T>() where T : class
{
    builder.Services
        .AddHttpClient<T>(c => c.BaseAddress = new Uri(apiBaseUrl))
        .AddHttpMessageHandler<TerakarsaApp.Client.Auth.TniDeviceTokenHandler>();
}

AddTniClient<TerakarsaApp.Client.Services.TniOrderApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniPolaApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniImportApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniPersonelApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniStokApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniPerintahKerjaApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniScanApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniPublicApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniBoxApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniDashboardApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniPembatalanApiService>();
AddTniClient<TerakarsaApp.Client.Services.TniPerangkatApiService>();

await builder.Build().RunAsync();