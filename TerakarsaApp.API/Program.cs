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
builder.Services.AddScoped<WorkflowLogService>();
builder.Services.AddScoped<BundleService>();
builder.Services.AddScoped<PackService>();
builder.Services.AddScoped<PrintJobService>();
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
    // Tunnel) atau localhost/IP privat LAN (device lain di pabrik, IP berubah-ubah).
    options.AddPolicy("AllowBlazor", policy =>
        policy.SetIsOriginAllowed(origin => IsAllowedOrigin(origin))
              .AllowAnyHeader()
              .AllowAnyMethod());
});

var app = builder.Build();

// Cloudflared berjalan di mesin yang sama (koneksi dari loopback) sehingga
// KnownProxies/KnownNetworks default (loopback) sudah cukup untuk memercayainya --
// supaya RemoteIpAddress dan Request.Scheme mencerminkan klien asli, bukan 127.0.0.1/http.
app.UseForwardedHeaders(new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
});

app.UseCors("AllowBlazor");
app.UseAuthentication();
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

    if (!System.Net.IPAddress.TryParse(host, out var ip))
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

    return false;
}