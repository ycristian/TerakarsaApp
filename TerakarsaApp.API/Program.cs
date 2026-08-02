using Microsoft.AspNetCore.Authentication.JwtBearer;
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
    // AllowAnyOrigin aman di sini karena auth pakai Bearer token di header (bukan cookie),
    // jadi tidak butuh AllowCredentials -- perlu supaya device lain di LAN (IP berubah-ubah)
    // bisa mengakses API ini.
    options.AddPolicy("AllowBlazor", policy =>
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod());
});

var app = builder.Build();

app.UseCors("AllowBlazor");
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapControllers();
app.Run();