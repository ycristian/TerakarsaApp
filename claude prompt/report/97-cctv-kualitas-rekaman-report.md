# Laporan Prompt 97 — CCTV: kualitas rekaman per kamera (Sub ↔ Main)

## Ringkasan

Dari form Ubah Kamera (halaman `/cctv/kamera` **dan** popup "Ubah kamera" di CCTV Live) user
memilih **Sub** atau **Main**. Pilihan disimpan di `cctv.cameras.record_quality` (sumber kebenaran),
lalu API langsung mencoba mengganti `source` path kamera di MediaMTX lewat API kontrol
(`PATCH /v3/config/paths/patch/{path}`). Background service mencocokkan ulang semua kamera tiap
30 detik (dua arah, PATCH hanya kalau berbeda), sehingga setelah MediaMTX restart (kembali ke
`mediamtx.yml` = sub) kamera Main dipulihkan otomatis. `mediamtx.yml` tidak disentuh sama sekali.

### Alur
1. **Simpan** → `cctv.SIS_Camera_Manage @Action='UPDATE', @RecordQuality=...` → sukses → baca ulang
   nilai dari DB → `CctvQualitySync.ApplyAsync`: GET config path → tukar dua digit akhir → PATCH kalau
   berbeda. Gagal/MediaMTX mati **tidak** menggagalkan simpan; status jadi "menunggu sinkron".
2. **Background** (`CctvQualitySyncHostedService`, tiap `Cctv:QualitySyncSeconds`, default 30, minimal 5):
   ambil semua kamera hidup (`SIS_Camera_List @OnlyVisible=0`) → `ApplyAsync` per kamera.
   Kalau MediaMTX tak terjangkau di satu tick, kamera sisanya ditandai tanpa menunggu timeout per kamera.
3. **Status sinkron** di memori (singleton `CctvQualitySync`), disajikan lewat `GET api/cctv/cameras`
   dan `GET api/cctv/cameras/{id}` sebagai `QualitySyncStatus`:
   `SESUAI` / `MENUNGGU` / `TIDAK_DIDUKUNG` / `PATH_TIDAK_ADA` / `null` (belum dicek).
4. Simpan & background memakai satu kunci (`SemaphoreSlim`) → tidak pernah PATCH ganda bersamaan.

### Keamanan kredensial
- URL source hanya ada di variabel lokal selama GET → tukar → PATCH. Tidak disimpan di field,
  DB, konfigurasi, maupun DTO; tidak pernah dikirim ke browser.
- `CctvMtxSourceResult` / `CctvSourceSwap` meng-override `ToString()` supaya source tidak bocor
  kalau objeknya tidak sengaja di-log (diuji unit test).
- Satu-satunya log yang memuat URL (source tidak berpola) memakai `MaskCredentials` →
  `rtsp://***@192.168.8.75:554/...`.
- Log HttpClient (`System.Net.Http.HttpClient.CctvMediaMtxClient`) diturunkan ke Warning — isinya
  hanya URL API MediaMTX, tetapi tanpa ini log banjir (4 baris × kamera × 30 detik).

### Log tidak membanjiri
- MediaMTX mati: satu Warning saat mulai gagal, satu Information saat tersambung kembali.
- Path tidak ada / source tidak didukung / MediaMTX menolak: Warning hanya saat status path berubah.
- PATCH berhasil: satu Information per pergantian ("Kualitas rekaman path X diganti SUB -> MAIN").
- Database gagal dibaca: satu Warning sampai pulih.

## File dibuat / diubah

**SQL (jalankan manual, urut):**
1. `sql/cctv/alter_97_cctv_record_quality.sql` — **baru**: kolom `record_quality` (varchar(4), NOT NULL,
   default `SUB`, CHECK `SUB|MAIN`), `record_quality_updated_at`, `record_quality_updated_by` (int tanpa FK,
   sama seperti `updated_by` di schema cctv). Idempotent.
2. `sql/cctv/sp_91_cctv_camera.sql` — diubah: `SIS_Camera_Manage` (parameter `@RecordQuality`; CREATE
   default SUB; UPDATE `NULL` = tidak diubah; jejak updated_at/by hanya diisi kalau nilainya berubah;
   validasi pesan Indonesia), `SIS_Camera_List` & `SIS_Camera_Get` membawa `RecordQuality`.
   `CREATE OR ALTER` — aman dijalankan ulang (SP Lookup di file yang sama ikut dibuat ulang, tanpa perubahan).
- `sql/cctv/create_schema_cctv.sql` — canonical schema cctv diperbarui (kolom di CREATE TABLE + blok ADD
  idempotent untuk DB lama).

**API**
- `TerakarsaApp.API/Services/CctvMediaMtxClient.cs` — `GetPathSourceAsync`, `PatchPathSourceAsync`,
  fungsi murni `SwapQuality`, `MaskCredentials`, helper auth bersama, opsi `QualitySyncSeconds`.
- `TerakarsaApp.API/Services/CctvQualitySyncService.cs` — **baru**: `CctvQualitySync` (singleton, status +
  penerapan) dan `CctvQualitySyncHostedService`.
- `TerakarsaApp.API/Services/CctvCameraService.cs` — kolom baru di baca/simpan, terapkan setelah UPDATE,
  `GetQualityTargetsAsync`.
- `TerakarsaApp.API/Program.cs` — registrasi singleton + hosted service.
- `TerakarsaApp.API/appsettings.json` — `Cctv:QualitySyncSeconds: 30`, filter log HttpClient.

**Shared**
- `TerakarsaApp.Shared/Cctv/CctvCameraModels.cs` — `CctvRecordQuality`, `CctvQualitySyncStatus`,
  `RecordQuality`/`QualitySyncStatus`/`IsMain` di DTO, `RecordQuality` (nullable) di save request.

**Client**
- `TerakarsaApp.Client/Pages/Cctv/Shared/CctvQualityField.razor` — **baru**: pilihan "Kualitas rekaman"
  + teks bantu + peringatan status.
- `TerakarsaApp.Client/Pages/Cctv/Kamera.razor` — field kualitas di form, badge `HD`, teks abu
  "menunggu sinkron" di baris.
- `TerakarsaApp.Client/Pages/Cctv/Shared/CctvCameraEditModal.razor` — field kualitas di popup Ubah kamera (Live).
- `TerakarsaApp.Client/Pages/Cctv/Live.razor` — badge `HD` di kartu kamera.
- `TerakarsaApp.Client/wwwroot/css/cctv.css` — `.cc-badge-hd`, `.cc-sync-wait`.

**Test**
- `TerakarsaApp.API.Tests/` — **baru** (xUnit): `CctvQualitySwapTests.cs`. Ditambahkan ke `TerakarsaApp.slnx`.
  Tidak ikut `deploy/publish-to-tka001.ps1` (script itu publish per project API/Client).

## Endpoint MediaMTX yang dipakai

| Keperluan | Endpoint | Catatan |
|---|---|---|
| Baca source | `GET {Cctv:MtxApiBaseUrl}/v3/config/paths/get/{path}` | 200 → JSON konfigurasi path, field `source`; 404 → `PATH_TIDAK_ADA` |
| Ganti source | `PATCH {Cctv:MtxApiBaseUrl}/v3/config/paths/patch/{path}` body `{"source":"..."}` | 2xx = sukses |

Sama dengan bentuk di prompt; alamat & Basic Auth (`MtxApiUser/MtxApiPassword`) memakai konfigurasi yang sudah
dipakai `CctvMediaMtxClient`. **Belum diverifikasi terhadap MediaMTX yang sedang jalan**: dari PC dev,
`192.168.8.233:9997` dan `127.0.0.1:9997` tidak terjangkau, dan `TKA001:9997` menjawab `401 authentication error`
(kredensial dev ada di user-secrets, sengaja tidak saya baca). Saya juga sengaja tidak memanggil
`config/paths/get` path kamera sungguhan dari terminal karena jawabannya memuat user & kode RTSP.

## Hasil uji terima

| # | Uji | Hasil |
|---|---|---|
| 1 | Ubah ke Main → ±15 dtk 1920×1080, badge HD | **Belum diuji** — perlu SQL dijalankan + API dideploy di server. Penerapan langsung saat simpan, jadi seharusnya beberapa detik saja. |
| 2 | `mediamtx.yml` tidak berubah | **Lulus secara kode** — tidak ada kode yang membuka/menulis file itu; hanya API. Perlu dicek di server. |
| 3 | Restart MediaMTX → kembali 1080p ≤ 60 dtk | **Belum diuji** — tick 30 dtk (+5 dtk jeda awal API), jadi maksimum ±30 dtk setelah MediaMTX siap. |
| 4 | Ubah ke Sub → 768×432, badge hilang | **Belum diuji**. |
| 5 | MediaMTX mati → simpan Main berhasil + "menunggu sinkron" → nyala → 1080p ≤ 60 dtk | **Belum diuji** — perilaku sudah ditangani (simpan tetap OK, status `MENUNGGU`). Catatan: kalau API **dan** MediaMTX di mesin yang sama dan port tertutup, koneksi ditolak instan; kalau host tak terjangkau, simpan menunggu timeout 5 dtk. |
| 6 | Rekaman satu folder `cam8_75`, playback melewati titik ganti | **Belum diuji** — nama path tidak diubah, jadi folder rekaman tetap sama. Segmen saat ganti resolusi perlu dicek di playback. |
| 7 | Log tanpa user/kode RTSP | **Lulus secara kode** + unit test `ToString_tidak_membocorkan_source`. Perlu dicek di log server. |
| 8 | Unit test penukar URL | **Lulus** — `dotnet test TerakarsaApp.API.Tests` 13/13: `102/→101/`, `101→102`, `1002→1001`, URL tidak cocok (pola lain, `103`, `02`, ada query string, kosong, null) → tidak didukung, kualitas tak dikenal, masking. |

Build: `dotnet build TerakarsaApp.slnx -c Release` sukses. Build Debug gagal **hanya** karena `TerakarsaApp.API.exe`
(PID 17460) sedang jalan dan mengunci `bin\Debug` — tidak ada error kompilasi.

## Penyimpangan dari prompt

1. **Kolom path = `mtx_path`, bukan `name`.** Prompt menyebut kolom `name` = nama path MediaMTX; di schema yang
   ada `name` adalah nama tampil dan path MediaMTX ada di `mtx_path`. Sinkron memakai `mtx_path`.
2. **"Kamera aktif"** = semua baris `cctv.cameras` dengan `deleted_at IS NULL` (tampil maupun tidak di grid),
   karena tidak ada kolom aktif; kamera yang disembunyikan dari grid tetap direkam.
3. **Field kualitas juga ada di popup Ubah kamera di CCTV Live** (`CctvCameraEditModal`), bukan hanya di
   `/cctv/kamera`, karena popup itu juga form edit kamera dan memakai endpoint simpan yang sama.
   Dipakai satu komponen bersama `CctvQualityField`.
4. **`RecordQuality` di request simpan boleh null = tidak diubah.** Fitur seret-urutan di Live memanggil
   endpoint UPDATE yang sama untuk banyak kamera tanpa membawa kualitas; dengan null, urutan tidak mereset
   kualitas dan tidak memicu panggilan ke MediaMTX.
5. **Tambah kamera manual** (CREATE) menyimpan kualitas, tetapi penerapannya ditunggu tick background
   berikutnya (≤ 30 dtk), bukan langsung — prompt hanya mewajibkan penerapan langsung di Edit Kamera.
6. **Status saat MediaMTX mati:** kamera `MAIN` → "menunggu sinkron"; kamera `SUB` → tanpa status, karena saat
   MediaMTX menyala lagi path otomatis kembali ke sub dari `mediamtx.yml`. Ini menghindari semua kamera
   ditandai "menunggu sinkron" setiap kali MediaMTX mati.
7. **Teks "menunggu sinkron" juga tampil (abu) di form edit**, selain dua peringatan yang diminta.
8. **Proyek test baru** `TerakarsaApp.API.Tests` (belum ada proyek test di solusi) untuk uji terima 8.
9. **Filter log** `System.Net.Http.HttpClient.CctvMediaMtxClient: Warning` di `appsettings.json` — ikut
   menurunkan log Information HttpClient untuk panggilan `paths/list` dan playback `/list` yang sudah ada.

## Temuan / risiko yang perlu diputuskan Ivander

1. **API dev ikut menjalankan background sinkron.** `appsettings.Development.json` mengarah ke MediaMTX
   192.168.8.233 (fallback `TKA001`) dan DB yang sama dengan produksi, jadi API dev juga akan PATCH MediaMTX
   produksi. Karena DB-nya sama, targetnya sama dan tidak saling berebut — tetapi kalau suatu saat dev memakai
   DB lain, dua API akan saling membalik kualitas. Opsi: tambah flag `Cctv:QualitySyncEnabled` dan matikan di dev.
2. **Izin user API MediaMTX.** Endpoint `config/paths/*` butuh permission `api`. Produksi memanggil dari
   127.0.0.1 (biasanya diizinkan); untuk dev lewat Basic Auth, pastikan user di `MtxApiUser` punya permission
   `api` — kalau tidak, status jadi "menunggu sinkron" dengan peringatan "MediaMTX menolak ...".
3. **Endpoint belum diverifikasi live** (lihat bagian endpoint). Kalau v1.21 ternyata berbeda, yang perlu
   disesuaikan hanya dua method di `CctvMediaMtxClient`.
4. **`cam8_85` (H8c)**: tidak ada logika khusus. Kalau di-set Main dan main stream-nya H.265, live view bisa
   bergantung pada path `_h264` (ffmpeg) yang sudah ada; belum diuji.
5. **`runOnReady` ffmpeg (`<path>_h264`)** ikut tersambung ulang saat PATCH karena path sumbernya diganti;
   wajar, tetapi live view kamera H265 akan hilang beberapa detik lebih lama.
6. **Deploy langkah 4** (hapus `cam8_75_main` & `tes_nvr4` dari `mediamtx.yml`) tetap dikerjakan Ivander.
