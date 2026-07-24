<#
Setup satu kali IIS di server tujuan (jalankan sebagai Administrator, DI SERVER, bukan di PC dev).
Idempotent -- aman dijalankan ulang.

Prasyarat manual (download dulu, tidak bisa di-script tanpa akses internet server):
  1. ".NET 10.0 - Hosting Bundle" (Windows)   https://dotnet.microsoft.com/download/dotnet/10.0
  2. "URL Rewrite Module 2.1" untuk IIS       https://www.iis.net/downloads/microsoft/url-rewrite
  Install keduanya SEBELUM menjalankan script ini, lalu restart server atau `iisreset`.
#>

param(
    [string]$ServerIp = "192.168.8.233",
    [int]$ApiPort = 5281,
    [int]$ClientPort = 80,
    [int]$ApiHttpsPort = 7130,     # harus sama dengan hardcode di Client Program.cs (scheme https -> port 7130)
    [int]$ClientHttpsPort = 443,
    [string]$ApiPhysicalPath = "C:\inetpub\TerakarsaApp.API",
    [string]$ClientPhysicalPath = "C:\inetpub\wwwroot\TerakarsaApp.Client",
    [string]$FileStorageBasePath = "D:\TerakarsaFiles",
    [string]$CertExportPath = "C:\inetpub\tmos-lan-cert.cer"
)

if (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue) {
    # Windows Server -- ServerManager module tersedia.
    Install-WindowsFeature -Name Web-Server, Web-Common-Http, Web-Default-Doc, Web-Static-Content, `
        Web-Http-Errors, Web-Http-Logging, Web-Request-Monitor, Web-Stat-Compression, `
        Web-Filtering, Web-Mgmt-Console -IncludeManagementTools
} else {
    # Windows client (10/11 Pro/Home) -- tidak ada ServerManager, IIS diaktifkan lewat
    # optional features (DISM). AGS ternyata client OS, bukan Windows Server.
    $clientFeatures = @(
        "IIS-WebServerRole", "IIS-WebServer", "IIS-CommonHttpFeatures", "IIS-DefaultDocument",
        "IIS-StaticContent", "IIS-HttpErrors", "IIS-HttpLogging", "IIS-LoggingLibraries",
        "IIS-RequestMonitor", "IIS-HttpCompressionStatic", "IIS-Security", "IIS-RequestFiltering",
        "IIS-Performance", "IIS-WebServerManagementTools", "IIS-ManagementConsole"
    )
    Enable-WindowsOptionalFeature -Online -FeatureName $clientFeatures -All -NoRestart | Out-Null
}

Import-Module WebAdministration

New-Item -ItemType Directory -Force -Path $ApiPhysicalPath | Out-Null
New-Item -ItemType Directory -Force -Path $ClientPhysicalPath | Out-Null
New-Item -ItemType Directory -Force -Path $FileStorageBasePath | Out-Null

# Default Web Site biasanya bind ke *:80 (semua IP) -- matikan supaya tidak bentrok
# dengan site Client yang mau kita bind ke $ServerIp:$ClientPort.
if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
    Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
}

foreach ($poolName in @("TerakarsaApiPool", "TerakarsaClientPool")) {
    if (-not (Test-Path "IIS:\AppPools\$poolName")) {
        New-WebAppPool -Name $poolName | Out-Null
    }
    # "No Managed Code" -- ASP.NET Core Module V2 & static file serving tidak butuh CLR pipeline IIS.
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name managedRuntimeVersion -Value ""
}

if (-not (Get-Website -Name "TerakarsaAPI" -ErrorAction SilentlyContinue)) {
    New-Website -Name "TerakarsaAPI" -PhysicalPath $ApiPhysicalPath -ApplicationPool "TerakarsaApiPool" `
        -Port $ApiPort -IPAddress $ServerIp | Out-Null
}
if (-not (Get-Website -Name "TerakarsaClient" -ErrorAction SilentlyContinue)) {
    New-Website -Name "TerakarsaClient" -PhysicalPath $ClientPhysicalPath -ApplicationPool "TerakarsaClientPool" `
        -Port $ClientPort -IPAddress $ServerIp | Out-Null
}

# App pool identity API butuh Modify di folder upload foto/attachment.
icacls $FileStorageBasePath /grant "IIS AppPool\TerakarsaApiPool:(OI)(CI)M" /T | Out-Null

New-NetFirewallRule -DisplayName "TMOS API $ApiPort" -Direction Inbound -Protocol TCP -LocalPort $ApiPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TMOS Client $ClientPort" -Direction Inbound -Protocol TCP -LocalPort $ClientPort -Action Allow -ErrorAction SilentlyContinue | Out-Null

# HTTPS wajib untuk scan QR lewat kamera (getUserMedia) -- browser memblokir kamera di origin
# HTTP selain localhost, dan kiosk mengakses lewat IP LAN ($ServerIp) via HTTP biasa. Sertifikat
# self-signed untuk $ServerIp, dipasang sekali di sini lalu di-trust manual di tiap device kiosk
# (lihat DEPLOY-LOCAL-IIS.md langkah 6) -- LAN tertutup, tidak perlu CA publik/Let's Encrypt.
$certFriendlyName = "TMOS LAN Self-Signed ($ServerIp)"
$cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object { $_.FriendlyName -eq $certFriendlyName -and $_.NotAfter -gt (Get-Date) } |
    Select-Object -First 1
if (-not $cert) {
    $cert = New-SelfSignedCertificate -DnsName $ServerIp -CertStoreLocation "Cert:\LocalMachine\My" `
        -FriendlyName $certFriendlyName -NotAfter (Get-Date).AddYears(5) -KeyExportPolicy Exportable
}
Export-Certificate -Cert $cert -FilePath $CertExportPath | Out-Null

function Set-TmosHttpsBinding {
    param([string]$SiteName, [string]$IPAddress, [int]$Port, $Cert)

    if (-not (Get-WebBinding -Name $SiteName -Protocol https -Port $Port -ErrorAction SilentlyContinue)) {
        New-WebBinding -Name $SiteName -IPAddress $IPAddress -Port $Port -Protocol https | Out-Null
    }
    $bindingPath = "IIS:\SslBindings\$IPAddress!$Port"
    if (-not (Test-Path $bindingPath)) {
        New-Item -Path $bindingPath -Value $Cert -ErrorAction Stop | Out-Null
    }
}

Set-TmosHttpsBinding -SiteName "TerakarsaAPI" -IPAddress $ServerIp -Port $ApiHttpsPort -Cert $cert
Set-TmosHttpsBinding -SiteName "TerakarsaClient" -IPAddress $ServerIp -Port $ClientHttpsPort -Cert $cert

New-NetFirewallRule -DisplayName "TMOS API HTTPS $ApiHttpsPort" -Direction Inbound -Protocol TCP -LocalPort $ApiHttpsPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
New-NetFirewallRule -DisplayName "TMOS Client HTTPS $ClientHttpsPort" -Direction Inbound -Protocol TCP -LocalPort $ClientHttpsPort -Action Allow -ErrorAction SilentlyContinue | Out-Null

Write-Host "Selesai."
Write-Host "  API site    : http://$ServerIp`:$ApiPort (dan https://$ServerIp`:$ApiHttpsPort)  -> $ApiPhysicalPath"
Write-Host "  Client site : http://$ServerIp`:$ClientPort (dan https://$ServerIp)  -> $ClientPhysicalPath"
Write-Host "  Sertifikat  : $CertExportPath (copy ke tiap device kiosk & trust manual, lihat DEPLOY-LOCAL-IIS.md langkah 6)"
Write-Host "Publish aplikasi lalu copy hasil publish ke folder di atas (lihat deploy/DEPLOY-LOCAL-IIS.md)."
