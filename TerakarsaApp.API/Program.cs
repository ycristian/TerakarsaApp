using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using System.Text;
using System.Threading.RateLimiting;
using TerakarsaApp.API.Data;
using TerakarsaApp.API.Services;

var builder = WebApplication.CreateBuilder(args);

// DbContext
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection"),
        sqlOptions => sqlOptions.EnableRetryOnFailure(maxRetryCount: 3, maxRetryDelay: TimeSpan.FromSeconds(5), errorNumbersToAdd: null)));

// JWT
// Key produksi/Azure WAJIB datang dari App Settings/environment variable
// (JwtSettings__Key), bukan dari appsettings.json -- ini perilaku bawaan ASP.NET
// Core configuration (env var dengan "__" menimpa section:key di appsettings).
var jwt = builder.Configuration.GetSection("JwtSettings");
var jwtKey = jwt["Key"];
if (string.IsNullOrEmpty(jwtKey) || jwtKey.Length < 32)
    throw new InvalidOperationException(
        "JwtSettings:Key wajib diisi minimal 32 karakter (set lewat App Settings/env var JwtSettings__Key untuk produksi).");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwt["Issuer"],
            ValidAudience = jwt["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });

// Rate limit endpoint auth (login/refresh) -- bukan endpoint station.
builder.Services.AddRateLimiter(options =>
{
    options.AddPolicy("auth", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            Window = TimeSpan.FromMinutes(1),
            PermitLimit = 5,
            QueueLimit = 0
        }));

    // Prompt 85: claim stasiun anonim + kode login terkunci permanen -> batasi tebakan kode.
    options.AddPolicy("station-claim", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            Window = TimeSpan.FromMinutes(1),
            PermitLimit = 10,
            QueueLimit = 0
        }));

    // Prompt 92: rute video CCTV (HLS live / playback). Segmen diminta terus-menerus
    // (12 kamera x LL-HLS bisa puluhan request/detik), jadi batasnya LONGGAR per IP --
    // hanya rem untuk klien yang rusak/berulah, bukan limiter login.
    options.AddPolicy("cctv-stream", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            Window = TimeSpan.FromMinutes(1),
            PermitLimit = 6000,
            QueueLimit = 0
        }));

    options.OnRejected = async (context, cancellationToken) =>
    {
        context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
        context.HttpContext.Response.ContentType = "text/plain";
        await context.HttpContext.Response.WriteAsync(
            "Terlalu banyak percobaan. Coba lagi sebentar lagi.", cancellationToken);
    };
});

builder.Services.AddAuthorization();
builder.Services.AddControllers();
builder.Services.AddScoped<AuthService>();
builder.Services.AddScoped<ProductService>();
builder.Services.AddScoped<UserService>();
builder.Services.AddScoped<ModuleService>();
builder.Services.AddScoped<DivisionService>();
builder.Services.AddScoped<PositionService>();
builder.Services.AddScoped<ResourceTypeService>();
builder.Services.AddScoped<ResourceService>();
builder.Services.AddScoped<BuyerService>();
builder.Services.AddScoped<EmployeeService>();
builder.Services.AddScoped<PpicEmployeeService>();
builder.Services.AddScoped<ProjectService>();
builder.Services.AddScoped<ProjectAttachmentService>();
builder.Services.AddScoped<SizePackService>();
builder.Services.AddScoped<ArticleService>();
builder.Services.AddScoped<ArticlePhotoService>();
builder.Services.AddScoped<WorkflowTemplateService>();
builder.Services.AddScoped<ArticleWorkflowService>();
builder.Services.AddScoped<StationService>();
builder.Services.AddSingleton<StationPresenceTracker>();
builder.Services.AddScoped<WorkflowLogService>();
builder.Services.AddScoped<WorkflowLockService>();
builder.Services.AddScoped<BundleService>();
// Prompt 82: pemecahan bundle (bundle anak) + selisih hilang/lebih.
builder.Services.AddScoped<BundleSplitService>();
builder.Services.AddScoped<PackService>();
builder.Services.AddScoped<PrintJobService>();
// Prompt 77: device cetak HP (Bluetooth) + routing job_type.
builder.Services.AddScoped<PrintDeviceService>();
builder.Services.AddScoped<ReportBundleService>();
builder.Services.AddScoped<ReportWipService>();
builder.Services.AddScoped<ReportProduksiService>();
builder.Services.AddScoped<ReportActivityLogService>();
builder.Services.AddScoped<SuperAdminService>();
builder.Services.AddScoped<WorkScheduleService>();
builder.Services.AddScoped<DailyPlanService>();
builder.Services.AddScoped<DashboardTokenService>();
builder.Services.AddScoped<DashboardService>();
builder.Services.AddScoped<RekapProduksiService>();
// Prompt 58: absensi + pengelolaan pegawai dari perangkat stasiun.
builder.Services.AddScoped<StationAttendanceService>();
// Prompt 59: tab "Rekap Produksi" + output non-PO di perangkat stasiun (BUKAN
// RekapProduksiService di atas -- itu rekap struk Prompt 42, kini blok
// Settlement di dasar tab yang sama).
builder.Services.AddScoped<StationRekapProduksiService>();
// Prompt 60-69: module PDH TNI AD (schema SQL `tni`).
builder.Services.AddScoped<TniOrderService>();
builder.Services.AddScoped<TniPolaService>();
builder.Services.AddScoped<TniImportService>();
builder.Services.AddScoped<TniPersonelService>();
builder.Services.AddScoped<TniStokService>();
builder.Services.AddScoped<TniPerintahKerjaService>();
builder.Services.AddScoped<TniScanService>();
builder.Services.AddScoped<TniBoxService>();
builder.Services.AddScoped<TniBoxPdfService>();
builder.Services.AddScoped<TniLaporanPersonelPdfService>();   // Prompt 89
builder.Services.AddScoped<TniPembatalanService>();
builder.Services.AddScoped<TniDashboardService>();
// Perangkat TNI tanpa login (pairing, seperti stasiun) + petugas per sesi.
builder.Services.AddScoped<TniPerangkatService>();
builder.Services.AddScoped<TniKomplainService>();
builder.Services.Configure<TniOptions>(builder.Configuration.GetSection("Tni"));
// Audit log lokal TNI (file di Tni:AuditLog:Folder): jurnal request tulis +
// snapshot/diff berkala yang menandai perubahan TANPA LOG.
builder.Services.Configure<TniAuditLogOptions>(builder.Configuration.GetSection("Tni:AuditLog"));
builder.Services.AddSingleton<TniAuditJurnal>();
builder.Services.AddHostedService<TniAuditSnapshotService>();
// Prompt 70: absensi RFID. GateService dipakai perangkat gate (tanpa login, X-Gate-Api-Key),
// AttendanceService dipakai halaman admin /attendance (JWT + module HR_ATTENDANCE).
builder.Services.AddScoped<GateService>();
builder.Services.AddScoped<AttendanceService>();
// Prompt 71-77: module Stok Benang (schema SQL `inv`), module INV_THREAD.
builder.Services.AddScoped<ThreadStockService>();
builder.Services.AddScoped<ThreadMovementService>();
builder.Services.AddScoped<ThreadOpnameService>();
builder.Services.AddScoped<ThreadReportService>();
// Prompt 78-80: module Cutting (stok bundle dari hamparan), module CUTTING.
builder.Services.AddScoped<CuttingService>();
// Prompt 83: output manual (module MANUAL_OUTPUT + tab OUT stasiun) & Rekap Gajian
// (module PAYROLL_REKAP -- harga lock item + finalisasi periode).
builder.Services.AddScoped<ManualOutputService>();
builder.Services.AddScoped<PayrollRekapService>();
// Prompt 91-94: module CCTV (schema SQL `cctv`). Semua video lewat API (proxy ke MediaMTX
// di 127.0.0.1) -- browser tidak pernah menghubungi MediaMTX langsung.
builder.Services.Configure<CctvOptions>(builder.Configuration.GetSection("Cctv"));
builder.Services.AddOptions<CctvOptions>().PostConfigure<ILoggerFactory>((o, lf) =>
    CctvOptions.ApplyFallbackHost(o, lf.CreateLogger<CctvOptions>()));
builder.Services.AddHttpClient<CctvMediaMtxClient>(c => c.Timeout = TimeSpan.FromSeconds(5));
builder.Services.AddScoped<CctvCameraService>();
// Catatan kejadian di rekaman (Playback) -- tabel cctv.camera_notes.
builder.Services.AddScoped<CctvNoteService>();
// Prompt 97: kualitas rekaman per kamera -- status sinkron di memori + cek ulang berkala
// (Cctv:QualitySyncSeconds) karena perubahan lewat API MediaMTX hilang saat MediaMTX restart.
builder.Services.AddSingleton<CctvQualitySync>();
builder.Services.AddHostedService<CctvQualitySyncHostedService>();
// Prompt 92: token stream (HMAC, terikat path) + proxy HLS. Client proxy TANPA timeout total
// (stream live / rekaman bisa lama), tapi koneksi ke MediaMTX dibatasi 5 detik; redirect
// tidak diikuti otomatis -- CctvProxyService hanya mengikuti redirect ke host yang sama
// (cookieCheck HLS MediaMTX), tujuan tetap base URL konfigurasi.
builder.Services.AddSingleton<CctvStreamTokenService>();
builder.Services.AddSingleton<CctvProxyService>();
builder.Services.AddHttpClient(CctvProxyService.HttpClientName, c => c.Timeout = Timeout.InfiniteTimeSpan)
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler
    {
        ConnectTimeout = TimeSpan.FromSeconds(5),
        AllowAutoRedirect = false,
        UseCookies = false,
        PooledConnectionLifetime = TimeSpan.FromMinutes(5)
    });
builder.Services.Configure<GateServiceOptions>(builder.Configuration.GetSection("GateService"));
builder.Services.Configure<GateOptions>(builder.Configuration.GetSection("Gate"));
builder.Services.Configure<StationOptions>(builder.Configuration.GetSection("Station"));
builder.Services.Configure<AppOptions>(builder.Configuration.GetSection("App"));
builder.Services.Configure<PrintServiceOptions>(builder.Configuration.GetSection("PrintService"));
builder.Services.AddScoped<IFileStorageService, LocalFileStorageService>();
builder.Services.AddScoped<ImageCompressionService>();
builder.Services.Configure<ImageCompressionOptions>(builder.Configuration.GetSection("ImageCompression"));

builder.Services.AddCors(options =>
{
    // Origin diizinkan lewat pengecekan host, bukan AllowAnyOrigin, karena auth pakai Bearer
    // token (tidak butuh AllowCredentials): host *.terakarsa.id (akses publik via Cloudflare
    // Tunnel) atau localhost/IP privat LAN (device lain di pabrik, IP berubah-ubah), atau
    // Tailscale (nama server tanpa titik mis. TKA001, *.ts.net, IP 100.64.0.0/10).
    options.AddPolicy("AllowBlazor", policy =>
        policy.SetIsOriginAllowed(origin => IsAllowedOrigin(origin))
              .AllowAnyHeader()
              .AllowAnyMethod()
              // Client beda origin (port lain) -- tanpa ini header Content-Disposition
              // tidak terbaca JS, sehingga nama file unduhan (Excel/PDF) jatuh ke
              // nama default di client. Location: sesi WebRTC dari proxy WHEP (CctvWhepController).
              .WithExposedHeaders("Content-Disposition", "Location"));
});

var app = builder.Build();

// Prompt 92: Cctv:StreamTokenSecret wajib di luar Development -- dibuat SEKARANG supaya API
// menolak start (pesan jelas di log) daripada gagal saat token pertama diminta.
app.Services.GetRequiredService<CctvStreamTokenService>();

// Cloudflared berjalan di mesin yang sama (koneksi dari loopback) sehingga
// KnownProxies/KnownNetworks default (loopback) sudah cukup untuk memercayainya --
// supaya RemoteIpAddress dan Request.Scheme mencerminkan klien asli, bukan 127.0.0.1/http.
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});

app.UseCors("AllowBlazor");
app.UseAuthentication();
// Setelah Authentication (user JWT terbaca), sebelum Authorization (401/403 ikut tercatat).
app.UseMiddleware<TniAuditJurnalMiddleware>();
app.UseAuthorization();
app.UseRateLimiter();
app.MapControllers();
app.Run();

static bool IsAllowedOrigin(string origin)
{
    if (!Uri.TryCreate(origin, UriKind.Absolute, out var uri))
        return false;

    var host = uri.Host;

    if (host.EndsWith("terakarsa.id", StringComparison.OrdinalIgnoreCase))
        return true;

    if (host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
        return true;

    // Nama DNS LAN (static DNS MikroTik), mis. terakarsa.lan
    if (host.EndsWith(".lan", StringComparison.OrdinalIgnoreCase))
        return true;

    // Tailscale: nama server tanpa titik (mis. TKA001, MagicDNS pendek) atau FQDN *.ts.net.
    if (host.EndsWith(".ts.net", StringComparison.OrdinalIgnoreCase))
        return true;

    var isIp = System.Net.IPAddress.TryParse(host, out var ip);
    if (!isIp && !host.Contains('.'))
        return true;

    if (!isIp || ip is null)
        return false;

    var b = ip.GetAddressBytes();
    if (b.Length != 4)
        return false;

    if (b[0] == 10)
        return true;
    if (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
        return true;
    if (b[0] == 192 && b[1] == 168)
        return true;
    // Tailscale (CGNAT 100.64.0.0/10), mis. 100.124.15.85
    if (b[0] == 100 && b[1] >= 64 && b[1] <= 127)
        return true;

    return false;
}