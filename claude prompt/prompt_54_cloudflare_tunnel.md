# Prompt XX — Akses Publik via Cloudflare Tunnel (app.terakarsa.id / api.terakarsa.id)

> Ganti `XX` dengan nomor prompt berikutnya. Independen dari prompt lain; tidak menyentuh SQL.

## Konteks

Client dan API sekarang bisa diakses dari internet lewat Cloudflare Tunnel yang berjalan di server pabrik:

| Hostname publik | Tunnel → origin | IIS site |
|---|---|---|
| `https://app.terakarsa.id` | `http://localhost:80` | TerakarsaClient (binding hostname `app.terakarsa.id`) |
| `https://api.terakarsa.id` | `http://localhost:5281` | TerakarsaAPI (binding hostname `api.terakarsa.id`) |

Akses lokal di pabrik **tidak berubah**: Client `http://192.168.8.233`, API `http://192.168.8.233:5281`. Station/kiosk tetap memakai alamat lokal.

Masalah saat ini: `TerakarsaApp.Client/Program.cs` merakit base URL API dari host halaman + port 5281/7130. Saat dibuka di `https://app.terakarsa.id`, hasilnya `https://app.terakarsa.id:7130/` → "Failed to fetch". Selain itu API perlu membaca IP asli klien dari header proxy.

## 1. Client — `TerakarsaApp.Client/Program.cs`

Ganti logika penentuan `apiBaseUrl`:

1. Ambil `clientUri = new Uri(builder.HostEnvironment.BaseAddress)`.
2. Bila `clientUri.Host` berakhiran `terakarsa.id` (case-insensitive) → `apiBaseUrl = "https://api.terakarsa.id/"`.
3. Selain itu → pertahankan logika lama persis (host sama, port 7130 untuk https / 5281 untuk http).

Tulis sebagai satu helper kecil (mis. `static string ResolveApiBaseUrl(Uri clientUri)`) dengan komentar yang menjelaskan dua mode: akses publik via Cloudflare Tunnel vs akses LAN. Semua `HttpClient` yang ada (`AuthAPI`, `API`, `StationDeviceApiService`) tetap memakai `apiBaseUrl` yang sama — tidak ada perubahan lain di file ini.

## 2. API — `TerakarsaApp.API/Program.cs`

### a. Forwarded headers
Tambahkan `app.UseForwardedHeaders(...)` **sebelum** `UseCors`/`UseAuthentication`, dengan `ForwardedHeaders = XForwardedFor | XForwardedProto`. Cloudflared berjalan di mesin yang sama (koneksi dari loopback), jadi `KnownProxies`/`KnownNetworks` default (loopback) sudah cukup — jangan dikosongkan. Tujuannya: `HttpContext.Connection.RemoteIpAddress` dan `Request.Scheme` mencerminkan klien asli, bukan `127.0.0.1`/`http`.

### b. CORS
Ganti policy `AllowBlazor` dari `AllowAnyOrigin()` menjadi `SetIsOriginAllowed(origin => ...)` yang mengizinkan:
- origin dengan host berakhiran `terakarsa.id`, dan
- origin dengan host `localhost` atau IP privat (`10.*`, `172.16–31.*`, `192.168.*`).

Tetap `AllowAnyHeader().AllowAnyMethod()`. Tidak perlu `AllowCredentials` (auth pakai bearer JWT, bukan cookie).

## 3. Konfigurasi yang TIDAK diubah (keputusan sadar)

- `PublicBaseUrl` di appsettings API tetap alamat lokal. Nilai ini dipakai untuk link pairing station dan `qr_content` label bundle — perangkat yang memindai berada di LAN, jadi harus tetap mengarah ke server lokal. Kalau nanti klien/partner perlu memindai QR dari luar, itu dibahas di prompt terpisah.
- Mekanisme `X-Station-Token`, `RequireStationTokenAttribute`, dan endpoint `api/station-device/*` tidak disentuh. Pemblokiran endpoint tersebut dari internet dilakukan di WAF Cloudflare, bukan di kode.

## Yang TIDAK boleh dilakukan

- Jangan hardcode `api.terakarsa.id` di service lain selain helper di `Program.cs` Client.
- Jangan ubah port IIS, `launchSettings.json`, atau `web.config` Client.
- Jangan tambah rate limiting / IP allowlist di kode — ditangani Cloudflare.
- Jangan refactor middleware lain di `Program.cs` API.

## Verifikasi

1. `dotnet build` sukses.
2. Publish Client & API ke IIS seperti biasa.
3. Dari luar jaringan pabrik (HP, data seluler): `https://app.terakarsa.id` → login berhasil, satu halaman list memuat data.
4. Dari LAN: `http://192.168.8.233` → login berhasil (mode lama tetap jalan); halaman `/station` di kiosk tetap normal.
5. Di log API, IP request dari luar tercatat sebagai IP publik klien, bukan `127.0.0.1`.
6. Di akhir: daftar file diubah. Tidak ada script SQL.
