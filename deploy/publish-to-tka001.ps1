<#
  Publish API / Client langsung ke server TKA001 lewat share \\TKA001\inetpub.

  Syarat (sekali saja, sudah dilakukan 2026-11-11):
    - Di TKA001: C:\inetpub di-share sebagai "inetpub", akun developer.cvsam@outlook.com
      punya izin Share Full Control + NTFS Modify.
    - Di PC dev: cmdkey /add:TKA001 /user:MicrosoftAccount\developer.cvsam@outlook.com /pass

  Contoh:
    .\deploy\publish-to-tka001.ps1                  # build + deploy API dan Client
    .\deploy\publish-to-tka001.ps1 -Only Client     # hanya Client
    .\deploy\publish-to-tka001.ps1 -SkipBuild       # kirim hasil publish yang sudah ada
    .\deploy\publish-to-tka001.ps1 -Full            # abaikan catatan, kirim semua file

  Hanya file yang ISINYA berubah yang dikirim: hash tiap file yang sudah terkirim dicatat di
  publish\.deployed-<Server>-<Nama>.json (dotnet publish selalu memberi tanggal baru ke semua
  file, jadi membandingkan tanggal seperti robocopy membuat semua file ikut terkirim).
  appsettings*.json TIDAK pernah dikirim (config server diedit manual).
  File lama di server tidak dihapus.
#>
param(
    [ValidateSet('API', 'Client')]
    [string[]]$Only = @('API', 'Client'),
    [switch]$SkipBuild,
    [switch]$Full,
    [string]$Server = 'TKA001'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$share = "\\$Server\inetpub"

$targets = @{
    API    = @{ Project = 'TerakarsaApp.API\TerakarsaApp.API.csproj';       Local = 'publish\API';    Remote = "$share\TerakarsaApp.API" }
    Client = @{ Project = 'TerakarsaApp.Client\TerakarsaApp.Client.csproj'; Local = 'publish\Client'; Remote = "$share\wwwroot\TerakarsaApp.Client" }
}

if (-not (Test-Path $share)) {
    throw "Share $share tidak bisa diakses. Cek Tailscale/LAN dan 'cmdkey /list:$Server'."
}

function Get-Hashes($root) {
    $map = @{}
    Get-ChildItem $root -Recurse -File |
        Where-Object { $_.Name -notlike 'appsettings*.json' } |
        ForEach-Object { $map[$_.FullName.Substring($root.Length + 1)] = (Get-FileHash $_.FullName -Algorithm SHA1).Hash }
    return $map
}

function Send-Changed($name, $local, $remote, $hashes, [scriptblock]$before, [scriptblock]$after) {
    $manifest = Join-Path $repo "publish\.deployed-$Server-$name.json"
    $sent = @{}
    if (-not $Full -and (Test-Path $manifest)) {
        (Get-Content $manifest -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $sent[$_.Name] = $_.Value }
    }
    $changed = @($hashes.Keys | Where-Object { $sent[$_] -ne $hashes[$_] } | Sort-Object)
    if ($changed.Count -eq 0) { Write-Host "  tidak ada file yang berubah"; return }

    Write-Host "  $($changed.Count) dari $($hashes.Count) file berubah"

    # Kumpulkan file yang berubah di folder sementara, lalu kirim sekaligus dengan robocopy
    # multi-thread (kirim satu per satu lambat sekali lewat Tailscale).
    $stage = Join-Path $env:TEMP "tmos-deploy-$name"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    foreach ($rel in $changed) {
        $dst = Join-Path $stage $rel
        New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null
        Copy-Item (Join-Path $local $rel) $dst
        Write-Host "    $rel"
    }

    if ($before) { & $before }
    try {
        robocopy $stage $remote /E /IS /IT /MT:32 /R:3 /W:3 /NP /NFL /NDL /NJH | Out-Host
        if ($LASTEXITCODE -ge 8) { throw "robocopy gagal (exit $LASTEXITCODE) ke $remote" }
        foreach ($rel in $changed) { $sent[$rel] = $hashes[$rel] }
        $sent | ConvertTo-Json | Set-Content $manifest -Encoding UTF8
    }
    finally {
        if ($after) { & $after }
        Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}

foreach ($name in $Only) {
    $t = $targets[$name]
    $local = Join-Path $repo $t.Local
    Write-Host "`n=== $name ===" -ForegroundColor Cyan

    if (-not $SkipBuild) {
        dotnet publish (Join-Path $repo $t.Project) -c Release -o $local --nologo -v q
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish $name gagal" }
    }

    # Jangan sampai appsettings lokal ikut tersalin (juga kalau folder dicopy manual).
    Get-ChildItem $local -Recurse -Filter 'appsettings*.json' | Remove-Item

    $hashes = Get-Hashes $local
    if ($name -eq 'API') {
        # app_offline.htm membuat IIS menghentikan API supaya DLL tidak terkunci.
        $offline = Join-Path $t.Remote 'app_offline.htm'
        Send-Changed $name $local $t.Remote $hashes `
            { Set-Content $offline '<h1>TMOS sedang diperbarui, coba lagi sebentar.</h1>' -Encoding UTF8; Start-Sleep -Seconds 3 } `
            { Remove-Item $offline -ErrorAction SilentlyContinue }
    }
    else {
        Send-Changed $name $local $t.Remote $hashes $null $null
    }

    Write-Host "$name selesai -> $($t.Remote)" -ForegroundColor Green
}
