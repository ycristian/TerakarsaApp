# Laporan Eksekusi — Prompt 91–94 (Module CCTV)

> Diisi oleh Claude Code. Dibaca oleh Claude di claude.ai.
> Aturan isi: tulis fakta, bukan rencana. Yang gagal / dilewati / tidak diuji **harus**
> tertulis. Jangan ubah judul bagian. Jangan menulis password, kode verifikasi kamera,
> token, atau isi `StreamTokenSecret`.

## Ringkasan

| | Isi |
|---|---|
| Tanggal eksekusi | 16–17 Nov 2026 |
| Server + database target | `TKA001` (`@@SERVERNAME` = `DESKTOP-5Q3C1EA\SQLEXPRESS`) / `TerakarsaDB`, dari `TerakarsaApp.API/appsettings.json` |
| Commit (hash + pesan) per prompt | `ff51686` Prompt 91 — CCTV: schema, module, master kamera · `7489372` Prompt 92 — CCTV: proxy stream + grid live · `b2d1c31` Prompt 93 — CCTV: playback rekaman · Prompt 94 — CCTV: lihat rekaman dari transaksi (commit terakhir, bersama laporan ini) |
| Status akhir | SELESAI SEBAGIAN — semua kode & SQL selesai dan build sukses; tahap WebRTC dibatalkan; seluruh jalur video **belum diuji** karena MediaMTX tidak terjangkau dari mesin development |
| Build terakhir | sukses (`dotnet build TerakarsaApp.slnx -v q`, 0 error; warning yang ada bukan dari file CCTV) |

Status tiap prompt:

| Prompt | Status | Catatan satu baris |
|---|---|---|
| 91 Schema + master kamera | selesai | SQL dijalankan 2× & diuji di level SP; sync/status MediaMTX tidak teruji |
| 92 Proxy stream + live | selesai, belum diuji | token + proxy HLS + grid live; stream tidak bisa diuji dari sini |
| 92 tahap WebRTC LAN | dibatalkan | HLS belum terbukti jalan (MediaMTX tidak terjangkau) → tidak ada kode WHEP |
| 93 Playback | selesai, belum diuji | list/range/get/download lewat proxy; format MediaMTX belum dicocokkan |
| 94 Dari transaksi | selesai, video belum diuji | SP ForEvent diuji 3 kasus; 2 kolom ditambah di akhir timeline Riwayat |

## Hasil inspeksi

Tulis temuan nyata, bukan asumsi.

- MediaMTX terjangkau dari mesin ini? (ya/tidak, alamat yang dipakai)
  **Tidak.** `curl -m 5 http://192.168.8.233:9997/v3/paths/list` dan
  `http://192.168.8.233:8888/cam8_83/index.m3u8` dari mesin development → timeout
  (exit 28 / HTTP 000) pada 16 Nov 2026. Semua hal yang bergantung pada MediaMTX
  **tidak bisa diuji dari sini**.
- Jawaban `/v3/paths/list` (jumlah path, contoh 1 item): tidak bisa dipanggil (lihat di atas).
  Parser di `CctvMediaMtxClient` dibuat toleran: membaca `items[].name`, `items[].ready`,
  codec video dari `tracks` (array string) **atau** `tracks2[].codec`, dan mengikuti
  `pageCount` (`?page=&itemsPerPage=100`). Bentuk nyata v1.21 belum dicocokkan.
- Bentuk playlist HLS (bertingkat? LL-HLS? nama segmen): **tidak bisa dicek** —
  `http://192.168.8.233:8888/cam8_83/index.m3u8` timeout dari mesin ini. Proxy dibuat
  tidak bergantung pada nama file: semua `{path}/{**file}` diteruskan apa adanya (nama file
  hanya divalidasi huruf/angka/`_`/`-`/`.`), query asli (mis. `_HLS_msn`/`_HLS_part` LL-HLS)
  ikut diteruskan selain `t`. Cara Client memuat JS pihak ketiga: file lokal di
  `wwwroot/lib/<nama>/` + `<script>` di `index.html` (pola `lib/html5-qrcode`). Unduhan file
  besar di API memakai `return File(stream, ...)`; tidak ada middleware yang mem-buffer response
  untuk `/api/cctv` (`TniAuditJurnalMiddleware` hanya menyentuh `/api/tni` & `/api/public/tni`).
- Jawaban `/list` server playback (contoh 1 item): **tidak bisa dipanggil** (port 9996 di
  192.168.8.233 tidak terjangkau dari sini; dokumentasi v1.21 juga tidak bisa dicocokkan dari
  mesin ini). Parser dibuat toleran terhadap bentuk yang diketahui dari dokumentasi MediaMTX
  versi sebelumnya: array `[{ "start": "<RFC3339>", "duration": <detik, angka atau string>,
  "url": ... }]`; 404 dianggap "tidak ada rekaman". API mengirim filter `start`/`end` (RFC3339
  +07:00) **dan** tetap memotong hasil ke batas hari sendiri, jadi tetap benar kalau server
  mengabaikan filter.
- `/get`: content type, dukungan `format=mp4`, dukungan Range: **tidak bisa dicek dari sini.**
  Putar memakai format bawaan (fMP4) ke `<video src>` dengan header `Range` diteruskan;
  unduhan meminta `format=mp4`. Kalau server menolak `format=mp4`, API menjawab 502
  "Server rekaman menolak permintaan (HTTP xxx)" — perlu dicek owner (langkah uji).
- Kategori menu yang dipakai untuk module `CCTV`: **`Sistem`** (SortOrder 870, di atas
  `PRINT_ADMIN` 880). Kategori yang ada di DB: `Production`, `Order`, `Gudang`, `Setting`
  (+ SubCategory `Master Data`), `Sistem`; `Order` juga punya SubCategory `TNI Siliwangi`.
  Pola seed mengikuti `sql/inv/seed_71_inv_thread_module.sql` (kolom `Code, Name, Category,
  SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt`) **tanpa** blok assign ke Admin.
- Tabel/kolom `resources` dan `divisions` yang dipakai: `dbo.resources(resource_id,
  resource_name, division_id, is_active, deleted_at)` dan `dbo.divisions(division_id,
  division_name, deleted_at)`. Tabel user bernama `Users` (`Id`).
- Pola controller/service/DTO module ber-schema: mengikuti module benang `inv`
  (`ThreadOpnameController` + `ThreadOpnameService`): `[Authorize]` + `[RequireModule]`,
  SP dipanggil lewat `SqlQueryRaw` dengan nama schema lengkap, mutasi mengembalikan kolom
  `Value`, `SqlException.Message` diteruskan sebagai 400. SP multi-result-set dibaca dengan
  `SqlCommand` + `NextResultAsync` (pola `CuttingService.GetSpreadDetailAsync`).
- SP timeline Laporan Bundle yang disentuh (kalau ada) + kolom yang ditambah:
  `dbo.SIS_Report_BundleHistory` result set ke-2 (timeline) sebelumnya hanya membawa nama
  (`PelaksanaName`, `DivisionName`) tanpa id. Ditambah di **akhir** SELECT:
  `awl.resource_id AS ResourceId`, `awl.division_id AS DivisionId`. Tanpa perubahan logika.
  Komponen timeline = daftar `<li>` di `Pages/ReportBundle.razor` (tab Riwayat); waktu selesai
  step = `CreatedAt`. Cara Client mengecek module: claim `module` pada `AuthenticationState`
  (pola `BenangTopBar.razor`).

## Prompt 91

- File dibuat/diubah (markdown link):
  - SQL: [create_schema_cctv.sql](../../sql/cctv/create_schema_cctv.sql),
    [sp_91_cctv_camera.sql](../../sql/cctv/sp_91_cctv_camera.sql),
    [seed_91_cctv_module.sql](../../sql/cctv/seed_91_cctv_module.sql),
    [create_tables_tmos_final.sql](../../sql/create_tables_tmos_final.sql) (catatan pointer schema `cctv` saja; file itu canonical dbo)
  - Shared: [CctvCameraModels.cs](../../TerakarsaApp.Shared/Cctv/CctvCameraModels.cs)
  - API: [CctvMediaMtxClient.cs](../../TerakarsaApp.API/Services/CctvMediaMtxClient.cs) (+ `CctvOptions`),
    [CctvCameraService.cs](../../TerakarsaApp.API/Services/CctvCameraService.cs),
    [CctvCameraController.cs](../../TerakarsaApp.API/Controllers/CctvCameraController.cs),
    [Program.cs](../../TerakarsaApp.API/Program.cs),
    [appsettings.json](../../TerakarsaApp.API/appsettings.json),
    [appsettings.Development.json](../../TerakarsaApp.API/appsettings.Development.json)
  - Client: [CctvLayout.razor](../../TerakarsaApp.Client/Layout/CctvLayout.razor),
    [CctvTabs.razor](../../TerakarsaApp.Client/Pages/Cctv/Shared/CctvTabs.razor),
    [Kamera.razor](../../TerakarsaApp.Client/Pages/Cctv/Kamera.razor),
    [Live.razor](../../TerakarsaApp.Client/Pages/Cctv/Live.razor) / [Playback.razor](../../TerakarsaApp.Client/Pages/Cctv/Playback.razor) ("Menyusul"),
    [CctvApiService.cs](../../TerakarsaApp.Client/Services/CctvApiService.cs),
    [cctv.css](../../TerakarsaApp.Client/wwwroot/css/cctv.css),
    [Program.cs](../../TerakarsaApp.Client/Program.cs), [index.html](../../TerakarsaApp.Client/wwwroot/index.html)
- Script SQL dieksekusi: ketiga script `sql/cctv/` di atas, ke `TKA001` / `TerakarsaDB`
  (`@@SERVERNAME` = `DESKTOP-5Q3C1EA\SQLEXPRESS`), masing-masing **dua kali** tanpa error.
  Module `CCTV` terbentuk (Id 37, kategori `Sistem`), `UserModules` untuk CCTV = 0 baris.
- Hasil verifikasi 1–4 (lulus / gagal / tidak diuji + alasan):
  1. **Lulus** — build sukses; script aman dijalankan ulang (dua kali, tanpa error/duplikat).
  2. **Lulus di level SP, tidak diuji end-to-end.** Dalam transaksi yang di-ROLLBACK:
     `SYNC_ADD 'zz_test_1'` → 1 (id), ulang → 0, `'bad/path'` → 0 (dilewati). Tombol
     sync lewat API tidak bisa diuji karena MediaMTX tidak terjangkau dari sini.
  3. **Lulus di level SP** (transaksi ROLLBACK): `SET_LINKS` resource 3 + divisi 1, lalu
     resource 3,1 + divisi kosong → `SIS_Camera_Get` mengembalikan 2 tautan resource, tautan
     divisi ter-soft-delete; `SIS_Camera_List` menampilkan "Cutting Team, Line A1 (Heru)".
     Lewat UI tidak diuji (API/Client tidak dijalankan — aturan repo: developer yang menjalankan).
  4. **Tidak diuji runtime.** Secara kode: controller memakai `[RequireModule("CCTV")]` → 403
     untuk user tanpa module; menu sidebar dibangun dari module milik user (`NavMenu.razor`),
     jadi tidak muncul tanpa module.
  Catatan: baris uji di-ROLLBACK, tetapi IDENTITY `cctv.cameras` sudah sempat terpakai, jadi
  kamera nyata pertama akan mendapat `camera_id` 2 (tidak berpengaruh apa pun).
- Menyimpang dari prompt? Apa dan kenapa:
  - `cctv.SIS_Camera_Lookup` mengembalikan **satu** result set dengan kolom `Kind`
    (`RESOURCE`/`DIVISION`), bukan dua result set — lebih sederhana dibaca EF `SqlQueryRaw`.
  - Status kamera ditambah info codec (`VideoCodec` dari MediaMTX). Kamera ONLINE dengan
    H265 ditampilkan "H265 — tidak tampil di browser" (warna peringatan), sesuai mockup;
    nilai `Status` tetap `ONLINE`/`OFFLINE`/`UNKNOWN`.
  - `created_by` dkk tanpa FK ke `Users` — mengikuti konvensi tabel `inv`/`tni`/dbo yang ada.
  - Path ditolak di SP kalau berisi selain huruf/angka/`_`/`-` (selain CHECK constraint);
    `SYNC_ADD` melewati path seperti itu tanpa error.
  - Layout `/cctv` tanpa sidebar admin (seperti `/gudang/benang`, `/cutting`) mengikuti mockup
    layar penuh; ada ikon ke menu utama di kanan bar tab.
  - Tombol **Hapus** (konfirmasi dua klik) ditambahkan di form ubah, memakai endpoint `DELETE`.

## Prompt 92

- File dibuat/diubah:
  - API: [CctvStreamTokenService.cs](../../TerakarsaApp.API/Services/CctvStreamTokenService.cs) (+ `CctvPathRules`),
    [CctvProxyService.cs](../../TerakarsaApp.API/Services/CctvProxyService.cs),
    [CctvHlsController.cs](../../TerakarsaApp.API/Controllers/CctvHlsController.cs) (+ `CctvRateLimit`),
    [CctvCameraController.cs](../../TerakarsaApp.API/Controllers/CctvCameraController.cs) (endpoint `stream-token`),
    [Program.cs](../../TerakarsaApp.API/Program.cs) (service, HttpClient `cctv-proxy`, rate limit `cctv-stream`, cek secret saat start)
  - Shared: [CctvStreamModels.cs](../../TerakarsaApp.Shared/Cctv/CctvStreamModels.cs)
  - Client: [Live.razor](../../TerakarsaApp.Client/Pages/Cctv/Live.razor),
    [cctvPlayer.js](../../TerakarsaApp.Client/wwwroot/js/cctvPlayer.js),
    [CctvApiService.cs](../../TerakarsaApp.Client/Services/CctvApiService.cs),
    [index.html](../../TerakarsaApp.Client/wwwroot/index.html),
    [lib/hls.js/](../../TerakarsaApp.Client/wwwroot/lib/hls.js/)
- Versi hls.js + lokasi file: **1.7.4** (`npm pack hls.js@1.7.4`, `dist/hls.min.js`, lisensi
  Apache-2.0) → `TerakarsaApp.Client/wwwroot/lib/hls.js/hls.min.js` (+ `LICENSE`, `VERSION.txt`).
  Dimuat lokal dari `index.html`, tidak dari CDN.
- Hasil verifikasi 1–5:
  1. **Lulus** — build sukses.
  2. **Tidak diuji runtime** (API tidak dijalankan dari sini — aturan repo). Secara kode:
     tanpa token / token rusak / tanda tangan salah / kedaluwarsa → 401; token path lain → 403
     (`CctvStreamTokenService.Validate` + `CctvRateLimit.TokenResult`).
  3. **Tidak diuji runtime.** Secara kode: `{path}` wajib `^[A-Za-z0-9_-]{1,50}$`, tiap bagian
     `{file}` wajib `^[A-Za-z0-9_.-]+$` tanpa `.`/`..`/bagian kosong (`//`), maks 4 tingkat →
     selain itu 400 sebelum token dicek. Catatan: `..` di URL umumnya sudah dinormalisasi
     browser/Kestrel sebelum sampai routing.
  4. **Tidak diuji** — MediaMTX tidak terjangkau dari mesin ini, jadi tidak ada stream untuk
     diamati di tab Network. Secara kode: `Restart()` memanggil `cctvPlayer.stopAll()` (hls.js
     `destroy()` + `video.src` dikosongkan) sebelum halaman/area/tampilan baru dimulai; generasi
     dinaikkan sehingga token yang datang terlambat untuk halaman lama dibuang. Maks 12 stream
     (`Take(12)`).
  5. **Tidak diuji** dari `https://app.terakarsa.id` — masuk langkah uji owner.
- Perilaku di Safari/iOS (diuji? hasil): **tidak diuji.** Kode: kalau `Hls.isSupported()`
  (termasuk iOS 17.1+ yang punya ManagedMediaSource) → hls.js dengan token di tiap request.
  Kalau tidak (iOS lama tanpa MSE/MMS) → `video.src = index.m3u8?t=...` langsung; playlist
  turunan & segmen **tidak** membawa `?t=` sehingga kemungkinan besar 401 → "Tidak ada sinyal"
  setelah 5 percobaan. Isi playlist tidak ditulis ulang (dilarang prompt).
- Tahap WebRTC LAN: hasil, atau alasan dibatalkan: **Tidak dikerjakan (dibatalkan).** Prompt
  mensyaratkan tahap ini dikerjakan *setelah HLS terbukti jalan*; HLS belum bisa dibuktikan
  karena MediaMTX tidak terjangkau dari mesin development. Membuat proxy WHEP + fallback tanpa
  bisa diuji sama dengan kode setengah jadi, jadi tidak ada kode WHEP di repo. Live = HLS saja.
- Menyimpang dari prompt? Apa dan kenapa:
  - `StreamTokenSecret` juga ditolak kalau < 32 karakter (sejalan aturan `JwtSettings:Key`).
    **Konsekuensi penting:** API Production **tidak mau start** sampai secret diisi — isi dulu
    sebelum deploy.
  - Token kedaluwarsa/rusak/tanpa token → 401, token kamera lain → 403.
  - Rate limit `cctv-stream`: 6000 request/menit per IP (fixed window) — angka diambil sendiri.
  - Kamera ONLINE dengan codec H265 tidak diminta stream-nya (tampil "H265 — tidak tampil di
    browser"), sama seperti kamera OFFLINE — hemat beban, toh tidak bisa diputar.
  - Teks "terakhir online 13:05" di mockup tidak dibuat: MediaMTX hanya memberi `ready`, tidak
    ada riwayat waktu online yang disimpan.
  - Kamera tanpa area dikelompokkan di chip "Tanpa area".

## Prompt 93

- File dibuat/diubah:
  - API: [CctvPlaybackController.cs](../../TerakarsaApp.API/Controllers/CctvPlaybackController.cs),
    [CctvMediaMtxClient.cs](../../TerakarsaApp.API/Services/CctvMediaMtxClient.cs) (`ListRecordingsAsync`, `CctvTime`),
    [CctvCameraService.cs](../../TerakarsaApp.API/Services/CctvCameraService.cs) (`GetNameByPathAsync`)
  - Shared: [CctvStreamModels.cs](../../TerakarsaApp.Shared/Cctv/CctvStreamModels.cs) (`CctvRecordingSpanDto`, `CctvRecordingRangeDto`)
  - Client: [Playback.razor](../../TerakarsaApp.Client/Pages/Cctv/Playback.razor),
    [CctvWaktu.cs](../../TerakarsaApp.Client/Services/CctvWaktu.cs),
    [CctvApiService.cs](../../TerakarsaApp.Client/Services/CctvApiService.cs),
    [cctvPlayer.js](../../TerakarsaApp.Client/wwwroot/js/cctvPlayer.js) (`playClip`, `seekTo`, `download`, `clickRatio`, dst.)
- Hasil verifikasi 1–5:
  1. **Lulus** — build sukses.
  2. **Tidak diuji** — tidak ada rekaman yang bisa diambil dari mesin ini. Secara kode: stempel =
     awal potongan + `currentTime` (dibaca tiap 0,5 detik), ditulis dalam WIB lewat `CctvWaktu`
     (tidak bergantung zona waktu perangkat).
  3. **Tidak diuji runtime.** Secara kode: garis waktu hanya biru di rentang yang dikembalikan
     `/list`; jam setelah sekarang tidak punya rekaman sehingga abu.
  4. **Tidak diuji runtime.** Secara kode: `duration` < 1 atau > 600 (mis. 601) → 400 "Durasi
     wajib 1–600 detik."; MediaMTX 404 → 404 "Tidak ada rekaman pada jam itu"; di UI, klik jam
     kosong / jam mulai tanpa rekaman → pesan "Tidak ada rekaman pada jam itu" (dicek ke rentang
     `/list` sebelum meminta video).
  5. **Tidak diuji** — lihat format di bawah.
- Format file hasil "Unduh klip": **belum diketahui** — API meminta `format=mp4` ke MediaMTX dan
  memberi nama `<namaKamera>_<yyyyMMdd_HHmmss>.mp4` (+ `Content-Disposition: attachment`).
  Apakah v1.21 menerima `format=mp4` belum bisa dicek dari sini.
- Menyimpang dari prompt? Apa dan kenapa:
  - Endpoint tambahan `GET api/cctv/playback/{path}/range?t=` → `{ oldest, newest }` untuk teks
    "Rekaman paling lama" (diambil dari `/list` tanpa filter; bukan dihitung dari 30 hari).
  - Potongan berikutnya dimulai dari akhir potongan sebelumnya; kalau ada celah rekaman,
    lompat ke awal rentang berikutnya di hari yang sama. Potongan juga dipotong di akhir rentang
    (tidak meminta video melewati celah).
  - −/+ 10 dtk: kalau posisi tujuan ada di potongan yang sedang diputar dan sudah bisa dicari
    (`seekable`/`buffered`) → seek biasa; selain itu minta potongan baru mulai dari posisi itu
    (berjaga-jaga kalau MediaMTX tidak mendukung Range).
  - Parameter `start` dengan spasi (tanda `+` tidak di-escape) dikembalikan jadi `+` sebelum parse.
  - Area punya pilihan "Semua area"; kamera tampil sebagai "Nama · path".

## Prompt 94

- File dibuat/diubah:
  - SQL: [sp_94_cctv_camera_for_event.sql](../../sql/cctv/sp_94_cctv_camera_for_event.sql),
    [alter_94_report_bundle_history.sql](../../sql/cctv/alter_94_report_bundle_history.sql),
    [sp_Report_Bundle.sql](../../sql/sp_Report_Bundle.sql) (2 kolom di akhir SELECT timeline)
  - Shared: [CctvCameraModels.cs](../../TerakarsaApp.Shared/Cctv/CctvCameraModels.cs) (`CctvEventCameraDto`, `CctvForEventResponse`),
    [ReportBundleModels.cs](../../TerakarsaApp.Shared/Reports/ReportBundleModels.cs) (`ResourceId`, `DivisionId` di `BundleHistoryTimelineDto`)
  - API: [CctvCameraController.cs](../../TerakarsaApp.API/Controllers/CctvCameraController.cs) (`for-event`),
    [CctvCameraService.cs](../../TerakarsaApp.API/Services/CctvCameraService.cs) (`GetForEventAsync`),
    [ReportBundleService.cs](../../TerakarsaApp.API/Services/ReportBundleService.cs) (baca 2 kolom baru)
  - Client: [CctvEventButton.razor](../../TerakarsaApp.Client/Pages/Cctv/Shared/CctvEventButton.razor),
    [ReportBundle.razor](../../TerakarsaApp.Client/Pages/ReportBundle.razor) (tombol per baris timeline),
    [CctvApiService.cs](../../TerakarsaApp.Client/Services/CctvApiService.cs),
    [cctv.css](../../TerakarsaApp.Client/wwwroot/css/cctv.css) (kelas `.cc-scope` + panel), [index.html](../../TerakarsaApp.Client/wwwroot/index.html) (versi css)
- Script SQL dieksekusi: `sql/cctv/sp_94_cctv_camera_for_event.sql` dan
  `sql/cctv/alter_94_report_bundle_history.sql`, masing-masing dua kali tanpa error, ke
  `TKA001`/`TerakarsaDB`. Sebelum diubah, definisi `SIS_Report_BundleHistory` di DB dicocokkan
  dengan `sql/sp_Report_Bundle.sql` → identik (selain baris komentar kepala), jadi tidak ada
  perubahan DB yang tertimpa.
- Hasil verifikasi 1–5:
  1. **Lulus** — build sukses.
  2. **Lulus di level SP, video tidak diuji.** Transaksi ROLLBACK: kamera tertaut resource 3 →
     `SIS_Camera_ForEvent @ResourceId=3, @DivisionId=1` mengembalikan kamera itu (`RESOURCE`) +
     kamera lain di area yang sama di result set 2. Pemutaran rekaman & posisi penanda tidak
     bisa diuji (MediaMTX tidak terjangkau). Penanda oranye ada di 30/90 = 33,3% bar.
  3. **Lulus di level SP:** resource 1 tanpa tautan, divisi 1 tertaut → kamera divisi (`DIVISION`).
  4. **Lulus di level SP:** tanpa tautan sama sekali → kedua result set kosong → panel menampilkan
     "Belum ada kamera untuk station ini" + tautan `/cctv/kamera` (UI tidak dijalankan).
  5. **Tidak diuji runtime.** Secara kode: `CctvEventButton` tidak merender apa pun (termasuk
     margin) kalau claim `module`=`CCTV` tidak ada; satu-satunya perubahan markup Riwayat adalah
     elemen komponen itu sendiri. `SIS_Report_BundleHistory` hanya dipakai
     `ReportBundleService` yang membaca kolom **berdasarkan nama** (dicek di kode dan
     `sys.sql_modules`: tidak ada SP lain / `INSERT…EXEC` yang memakainya), jadi 2 kolom baru
     tidak mengubah tampilan lama.
- Menyimpang dari prompt? Apa dan kenapa:
  - Sebelum memutar, panel mengecek `/list` tanggal itu; kalau tidak ada rekaman yang
    beririsan dengan 90 detik tsb → "Tidak ada rekaman pada jam itu" (bukan galat video).
  - Dropdown "Kamera lain di area ini" berisi kamera tertaut **dan** kamera lain di area yang
    sama (result set 2 tidak mengulang kamera result set 1).
  - Waktu `CreatedAt` dari DB (tanpa zona) dianggap WIB.
  - Kejadian < 15 detik: pesan "Rekaman belum tersedia, coba beberapa saat lagi", video tidak
    diminta, tombol Unduh mati; "Buka di Playback" tetap ada.
  - Panel memakai elemen `position:fixed` sendiri (bukan offcanvas Bootstrap JS) supaya tidak
    bergantung pada JS Bootstrap; di layar ≤ 600px lebarnya penuh.
  - Diizinkan prompt tetapi menyentuh objek di luar schema `cctv`: `dbo.SIS_Report_BundleHistory`
    (hanya 2 kolom di akhir SELECT timeline: `ResourceId`, `DivisionId`).

## Objek baru

| Jenis | Nama |
|---|---|
| Tabel | `cctv.cameras`, `cctv.camera_links` (schema baru `cctv`); baris module `CCTV` di `Modules` |
| Stored procedure | `cctv.SIS_Camera_Manage`, `cctv.SIS_Camera_List`, `cctv.SIS_Camera_Get`, `cctv.SIS_Camera_Lookup`, `cctv.SIS_Camera_ForEvent`; diubah: `dbo.SIS_Report_BundleHistory` (+2 kolom akhir) |
| Endpoint API | `GET/POST api/cctv/cameras`, `GET/PUT/DELETE api/cctv/cameras/{id}`, `PUT api/cctv/cameras/{id}/links`, `POST api/cctv/cameras/sync`, `GET api/cctv/cameras/lookup`, `GET api/cctv/cameras/{id}/stream-token`, `GET api/cctv/cameras/for-event`, `GET api/cctv/hls/{path}/{**file}?t=`, `GET api/cctv/playback/{path}/list?date=&t=`, `GET api/cctv/playback/{path}/range?t=`, `GET api/cctv/playback/{path}/get?start=&duration=&t=`, `GET api/cctv/playback/{path}/download?start=&duration=&t=` |
| Route halaman | `/cctv` (Live), `/cctv/playback`, `/cctv/kamera`; komponen `CctvEventButton` di `/report-bundle` tab Riwayat |
| Konfigurasi (`appsettings`) | section `Cctv`: `MtxApiBaseUrl`, `MtxHlsBaseUrl`, `MtxWebRtcBaseUrl` (belum dipakai — WebRTC dibatalkan), `MtxPlaybackBaseUrl`, `StreamTokenSecret` (kosong di repo), `StreamTokenMinutes`; override `appsettings.Development.json` ke `192.168.8.233`. Rate limit policy `cctv-stream`, HttpClient `cctv-proxy` |
| File JS/CSS | `wwwroot/css/cctv.css`, `wwwroot/js/cctvPlayer.js`, `wwwroot/lib/hls.js/hls.min.js` (1.7.4) |

## Keputusan yang diambil sendiri

Satu baris per keputusan: apa yang diputuskan — alasannya — bagian mana yang
terpengaruh.

1. Module `CCTV` di kategori `Sistem`, SortOrder 870 — paling cocok untuk alat owner, bukan produksi — menu sidebar.
2. Layout `/cctv` tanpa sidebar + ikon ke menu utama — mockup layar penuh, pola `/gudang/benang` — semua halaman CCTV.
3. `StreamTokenSecret` < 32 karakter juga ditolak saat start — sejalan aturan JwtSettings:Key — start API Production.
4. Token rusak/kedaluwarsa/tidak ada → 401, token kamera lain → 403 — membedakan "tidak berizin" vs "salah kamera" — rute hls/playback.
5. Rate limit `cctv-stream` 6000/menit per IP — LL-HLS 12 kamera bisa puluhan request/detik — rute hls/playback.
6. Kamera ONLINE ber-codec H265 tidak di-stream & ditandai peringatan — tidak bisa diputar browser, hemat beban — Live, Kamera.
7. WebRTC (tahap 4) tidak dikerjakan — HLS belum terbukti jalan karena MediaMTX tidak terjangkau — Live hanya HLS; `MtxWebRtcBaseUrl` tidak dipakai.
8. Endpoint tambahan `playback/{path}/range` — teks "Rekaman paling lama" harus dari data nyata — Playback.
9. Playback & panel transaksi mengecek `/list` sebelum memutar — pesan jelas "Tidak ada rekaman pada jam itu" — Playback, CctvEventButton.
10. `cctv.SIS_Camera_Lookup` satu result set ber-`Kind` — sederhana dibaca EF — form Kamera.
11. Perubahan `SIS_Report_BundleHistory` disimpan sebagai script khusus `sql/cctv/alter_94_report_bundle_history.sql` (hanya SP itu) + `sql/sp_Report_Bundle.sql` ikut diperbarui — menjalankan seluruh `sp_Report_Bundle.sql` akan ikut membuat ulang SP lain — DB.
12. Semua waktu dihitung WIB (+07:00) di klien & API, tidak memakai zona waktu perangkat — owner bisa membuka dari luar — Playback, panel transaksi.
13. File prompt `claude prompt/cctv/` ikut di-commit bersama Prompt 91 — dokumen acuan seri ini.

## Masalah yang belum selesai

Satu baris per masalah: gejala — dugaan penyebab — yang sudah dicoba.

1. Seluruh jalur video (sync kamera, status online, live HLS, playback, unduh, panel transaksi) belum pernah diuji — MediaMTX 192.168.8.233 tidak terjangkau dari mesin development (mesin ini mencapai TKA001 lewat `100.124.15.85`, tampaknya VPN, bukan LAN pabrik) — sudah dicoba `curl` ke port 9997 & 8888 (timeout).
2. **API Production kemungkinan tidak di mesin yang sama dengan MediaMTX** — `deploy/publish-to-tka001.ps1` mem-publish API ke `\\TKA001\inetpub`; `TKA001` = `DESKTOP-5Q3C1EA`, sedangkan MediaMTX ada di `192.168.8.233` (CLAUDE.md menyebut 192.168.8.233 = `AGS`). Kalau benar berbeda, nilai bawaan `127.0.0.1` salah — belum bisa dipastikan dari sini (lihat bagian owner).
3. Bentuk JSON `/v3/paths/list` & `/list`, nama file HLS, dukungan `format=mp4` dan Range di MediaMTX v1.21 belum dicocokkan — server tidak terjangkau — parser dibuat toleran (lihat Hasil inspeksi).
4. Safari/iOS lama tanpa MSE/ManagedMediaSource kemungkinan gagal memutar live (playlist turunan tanpa `?t=`) — keterbatasan desain token-di-query tanpa menulis ulang playlist — belum diuji.
5. API & Client tidak dijalankan sama sekali (aturan repo) — verifikasi 401/403/400, regresi Riwayat, dan UI hanya lewat review kode + uji SP di DB.

## Yang harus dikerjakan owner

Centang yang berlaku, tambah kalau ada.

- [ ] Isi `Cctv:StreamTokenSecret` di `appsettings` server (nilai acak panjang).
      **WAJIB sebelum deploy API**: `deploy/publish-to-tka001.ps1` tidak pernah mengirim
      `appsettings*.json`, jadi section `Cctv` harus ditambah manual di `appsettings.json`
      server. Tanpa secret (≥ 32 karakter) API Production **menolak start**.
- [ ] **Pastikan alamat MediaMTX dari mesin API.** Kalau API (TKA001) bukan mesin yang sama
      dengan MediaMTX (192.168.8.233), isi di `appsettings.json` server:
      `MtxApiBaseUrl` `http://192.168.8.233:9997`, `MtxHlsBaseUrl` `http://192.168.8.233:8888`,
      `MtxPlaybackBaseUrl` `http://192.168.8.233:9996` (dan pastikan firewall 192.168.8.233
      mengizinkan TKA001 ke port itu). Kalau satu mesin, nilai `127.0.0.1` sudah benar.
- [ ] Deploy API + Client ke server.
- [ ] Centang module `CCTV` untuk akun owner di kelola user (lalu login ulang supaya claim module terbaca).
- [ ] Buka `/cctv/kamera` → **Ambil kamera baru dari server**, lalu isi nama, area, dan
      station tiap kamera.
- [ ] Perubahan `mediamtx.yml` yang diperlukan (tulis persis baris yang diubah, atau
      "tidak ada"): **tidak ada yang wajib** (API, HLS, playback sudah aktif menurut dokumen
      desain). Opsional pengamanan: kalau API satu mesin dengan MediaMTX, batasi port ke
      loopback supaya video tidak bisa dibuka langsung di LAN tanpa lewat API —
      `hlsAddress: 127.0.0.1:8888`, `playbackAddress: 127.0.0.1:9996`,
      `apiAddress: 127.0.0.1:9997` (jangan lakukan kalau API ada di mesin lain).
- [ ] `cam8_85` diubah ke H.264 di aplikasi EZVIZ.
- [ ] (Opsional) Jalankan ulang script SQL kalau DB produksi bukan `TKA001/TerakarsaDB`:
      `sql/cctv/create_schema_cctv.sql`, `sql/cctv/sp_91_cctv_camera.sql`,
      `sql/cctv/seed_91_cctv_module.sql`, `sql/cctv/sp_94_cctv_camera_for_event.sql`,
      `sql/cctv/alter_94_report_bundle_history.sql` (semua sudah dijalankan ke TKA001).

## Langkah uji manual untuk owner

Urut, singkat, bisa diikuti di HP. Sertakan uji dari luar pabrik
(`https://app.terakarsa.id`).

1. Setelah deploy, cek API hidup (buka aplikasi, login). Kalau gagal start, lihat log: pesan `Cctv:StreamTokenSecret ...`.
2. Kelola user → centang `CCTV` di akun owner → logout/login. Menu **Sistem → CCTV** muncul. Login sebagai user lain tanpa CCTV: menu tidak ada, buka `/cctv/kamera` → daftar kosong (API 403).
3. `/cctv/kamera` → **Ambil kamera baru dari server** → toast "27 kamera baru ditambahkan". Klik lagi → "0 kamera baru ditambahkan". Kalau muncul banner "Server rekaman tidak terjangkau", alamat MediaMTX di appsettings server salah (lihat bagian owner).
4. Ubah satu kamera: nama, area, 1 station + 1 divisi → Simpan → buka Ubah lagi, tautan masih ada; kolom "Station terkait" terisi.
5. `/cctv` (di LAN): 12 kotak tampil, lencana LIVE muncul dalam ±10 detik. Ganti halaman "Berikutnya" → di DevTools Network (PC), request `index.m3u8`/segmen kamera halaman lama berhenti. Pindah tab browser lalu kembali → stream mulai lagi. Klik video → layar penuh.
6. Biarkan `/cctv` terbuka > 10 menit → video tetap jalan (token diperbarui otomatis).
7. Dari HP dengan data seluler (luar pabrik) buka `https://app.terakarsa.id/cctv` → ulangi langkah 5. Ulangi di iPhone (Safari) dan catat hasilnya.
8. Dari kartu live klik ikon putar ulang → `/cctv/playback` dengan kamera terpilih. Pilih jam 1 jam lalu → **Putar**: gambar muncul, stempel jam sama dengan jam dinding (WIB). Coba −10/+10 dtk, Jeda, 2×/4×.
9. Garis waktu hari ini: bagian setelah jam sekarang abu. Klik bagian abu → "Tidak ada rekaman pada jam itu".
10. **Unduh klip (MP4)** → 1 menit → file `<nama>_<tanggal_jam>.mp4` terunduh dan bisa dibuka di pemutar biasa (VLC/HP). Kalau gagal dengan pesan "Server rekaman menolak permintaan", catat — kemungkinan `format=mp4` tidak didukung.
11. Uji tolakan (PC, tab baru): buka URL `.../api/cctv/playback/cam8_83/get?start=...&duration=601&t=<token>` → 400; hapus `t=` → 401; pakai token kamera lain → 403.
12. `/report-bundle` → tab Riwayat → cari bundle yang pernah di-scan di line yang sudah ditautkan kamera → tombol **Lihat** → panel memutar 30 dtk sebelum s.d. 60 dtk sesudah scan, penanda oranye di posisi scan. Baris yang hanya divisinya tertaut → memakai kamera divisi. Baris tanpa tautan → "Belum ada kamera untuk station ini".
13. Login sebagai user tanpa module CCTV → tab Riwayat tampil sama seperti sebelumnya (tanpa tombol Lihat).

## Pertanyaan untuk Claude (claude.ai)

Hal yang butuh keputusan desain sebelum lanjut.

1. API Production (TKA001) dan MediaMTX (192.168.8.233) tampaknya mesin berbeda. Dokumen desain mengasumsikan proxy ke `127.0.0.1`. Tetap proxy lintas mesin di LAN (cukup ubah appsettings server), atau MediaMTX dipindah / API dipasang di mesin MediaMTX?
2. WebRTC LAN (jeda < 1 detik) dibatalkan karena HLS belum terbukti. Perlu dijadwalkan sebagai prompt tersendiri setelah owner mengonfirmasi live HLS jalan?
3. Untuk iPhone lama tanpa ManagedMediaSource, live via `?t=` di query tidak akan jalan tanpa menulis ulang playlist. Perlu dukungan (mis. token di path URL sehingga URI relatif ikut membawanya), atau cukup iOS 17.1+?
4. Rate limit `cctv-stream` 6000 request/menit per IP dipilih tanpa data. Kalau semua akses luar lewat Cloudflare dan IP klien asli terbaca (ForwardedHeaders), angka ini aman; perlu ditinjau setelah ada data nyata?
