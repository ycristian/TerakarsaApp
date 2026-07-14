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
    [string]$ApiPhysicalPath = "C:\inetpub\TerakarsaApp.API",
    [string]$ClientPhysicalPath = "C:\inetpub\wwwroot\TerakarsaApp.Client",
    [string]$FileStorageBasePath = "D:\TerakarsaFiles"
)

Install-WindowsFeature -Name Web-Server, Web-Common-Http, Web-Default-Doc, Web-Static-Content, `
    Web-Http-Errors, Web-Http-Logging, Web-Request-Monitor, Web-Stat-Compression, `
    Web-Filtering, Web-Mgmt-Console -IncludeManagementTools

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

Write-Host "Selesai."
Write-Host "  API site    : http://$ServerIp`:$ApiPort  -> $ApiPhysicalPath"
Write-Host "  Client site : http://$ServerIp`:$ClientPort  -> $ClientPhysicalPath"
Write-Host "Publish aplikasi lalu copy hasil publish ke folder di atas (lihat deploy/DEPLOY-LOCAL-IIS.md)."
