# Ringkasan Seri Prompt 71–77 — Module Stok Benang + App Android

Dikerjakan 14–15 Okt 2026. Semua prompt (71, 72, 73, 74, 75, 76, 77) selesai, masing-masing
satu commit: `ce0e097`, `508d094`, `5d175b7`, `38d0e7a`, `e19a96c`, `2b906a8`, `a876eeb`.

Target database (dikonfirmasi dari `TerakarsaApp.API/appsettings.json`):
**server `AGS\SQLEXPRESS` (192.168.8.233), database `TerakarsaDB`**.

> **Semua script SQL di bawah SUDAH DIJALANKAN ke database itu** dan hasilnya diverifikasi.
> Tidak ada data uji yang tertinggal (semua skrip uji memakai transaksi + ROLLBACK;
> dicek ulang: `inv.thread_items` = 0 baris, `inv.thread_movements` = 0 baris,
> `inv.thread_opname_sessions` = 0 baris, `print_jobs` job THREAD_* = 0 baris).

---

## Cara buka module

| Siapa | Cara |
|---|---|
| Owner / Admin | menu **Gudang → Stok Benang** (module `INV_THREAD`), atau langsung `/gudang/benang` |
| Admin gudang | login `gudang` / `gudang123` → otomatis masuk ke `/gudang/benang` |
| Admin printer | menu **Sistem → Printer & Routing** (`/admin/printer`, module `PRINT_ADMIN`) |

**Ganti password user `gudang` setelah login pertama.**

---

## Prompt 71 — Schema `inv`, module & role, master SKU + lokasi, landing

**SQL (sudah dijalankan, urut):**
`sql/inv/create_71_inv_thread.sql` · `sql/inv/sp_71_ThreadMaster.sql` ·
`sql/inv/seed_71_inv_thread.sql` · `sql/inv/seed_71_inv_thread_module.sql` ·
`sql/inv/alter_71_home_route.sql` · `sql/inv/seed_71_user_gudang.sql` ·
`sql/inv/verify_71_thread.sql` (read-only, semua baris OK)

- 8 tabel `inv.*` + view `inv.v_thread_item_stock` + fungsi `inv.fn_ThreadAlnum`
- 10 SP master (type/brand/location/item)
- Module `INV_THREAD` (Gudang, `gudang/benang`), role `WAREHOUSE` ("Admin Gudang")
- Kolom `dbo.Users.home_route` + `SIS_User_GetByUsername`/`SIS_RefreshToken_Manage`
  mengembalikan `HomeRoute`

**Kode:** `TerakarsaApp.Shared/Inv/ThreadMasterModels.cs`,
`TerakarsaApp.API/Services/ThreadStockService.cs`,
`TerakarsaApp.API/Controllers/ThreadStockController.cs` + `ThreadPhotoController.cs`,
`TerakarsaApp.Client/Layout/BenangLayout.razor`,
`TerakarsaApp.Client/Pages/Gudang/Benang/` (Beranda, SkuDetail, SkuForm, Lokasi, Master,
Shared/*), `TerakarsaApp.Client/Services/ThreadStockApiService.cs`,
`wwwroot/css/benang.css`, `wwwroot/js/benang.js`.
Diubah: `AuthService.cs` (claim `home_route`), `ImageCompressionService.cs` (override
800px/80), `IFileStorageService`/`LocalFileStorageService` (`Delete`), `Login.razor`,
`UserManagement.razor` (opsi role "Admin Gudang"), `index.html`, kedua `Program.cs`.

## Prompt 72 — Movement + scan

**SQL:** `sql/inv/sp_72_ThreadMovement.sql` · uji `sql/inv/test_72_movement.sql`
(5 blok, semua OK: RECEIVE 10 → ISSUE 6 → RETURN 420 g → ISSUE_SPLIT → RETURN_SPLIT 300 g
→ MOVE 2, saldo akhir benar; penolakan "Isi project atau keterangan.", "Stok di rak ZZ4
hanya 3 kones.", "Berat kembali lebih besar dari berat terakhir" terbukti)

- `inv.SIS_ThreadMovement_Manage` 8 action (+ 2 lagi di Prompt 74), satu transaksi/mutasi,
  saldo tidak boleh minus
- SP baca: split cone by code/id, stok per rak, 20 movement terakhir, lookup line & project

**Kode:** `ThreadMovementModels.cs`, `ThreadMovementService.cs`,
halaman `Scan/Ambil/Kembali/KembaliSplit/Terima/Pindah.razor`,
`Shared/ThreadSkuMini.razor` + `ThreadMovementList.razor`.

## Prompt 73 — Label 30×20 mm

**SQL:** `sql/inv/sp_73_ThreadLabel.sql` · `sql/inv/seed_73_thread_label_jobs.sql`
(route `THREAD_SKU_LABEL` & `THREAD_SPLIT_LABEL` → device `LABEL`)

- `TsplBuilder.BuildThreadLabel` (`SIZE 30 mm, 20 mm`, `GAP 2 mm,0`), job type baru
  masuk daftar LABEL di `Worker.cs`
- Tombol cetak + preview label di detail SKU, halaman Kembali, dan hasil scan split

**Hasil DryRun** (dua file `.tspl`, dirender dari payload asli SP):

```
SIZE 30 mm, 20 mm
GAP 2 mm, 0
DIRECTION 1
CLS
BITMAP 8,26,12,92,0,<bitmap QR 92x92 dot>
TEXT 108,14,"3",0,1,1,"2041"
TEXT 108,44,"2",0,1,1,"MERAH CABE"
TEXT 108,70,"1",0,1,1,"ASTRA POLY"
TEXT 108,88,"1",0,1,1,"SP-000001"
TEXT 108,106,"2",0,1,1,"420 g"
TEXT 109,106,"2",0,1,1,"420 g"
PRINT 1,1
```

(label SKU sama tanpa dua baris terakhir, `TEXT ...,"BESAR"`, `PRINT 1,3` untuk 3 copy)

## Prompt 74 — Stock opname

**SQL:** `sql/inv/create_74_inv_thread_opname.sql` · `sql/inv/sp_74_ThreadOpname.sql` ·
uji `sql/inv/test_74_opname.sql` (5 blok, semua OK)

- 4 tabel opname + FK `inv.thread_movements.opname_line_id`
- `inv.SIS_ThreadOpname_Manage`: OPEN / ADD_LINE / COUNT / LOCATION_DONE /
  PREVIEW_CLOSE / CLOSE / CANCEL + 4 SP baca + `SIS_ThreadReasonCode_List`
- Action `ADJUST` & `ADJUST_SPLIT` di SP movement — **hanya boleh lahir dari opname**
- Halaman `/gudang/benang/opname` (+ `/rak/{id}`, `/tutup`, `/riwayat`, `/riwayat/{id}`)

Hasil uji skenario prompt: A1 18 / B5 10 → usulan **MOVE 2 tanpa ADJUST**, saldo akhir
A1=18 B5=10; A1 18 / B5 8 → usulan **ADJUST −2** dan CLOSE tanpa alasan **ditolak**;
CLOSE dengan alasan HILANG → saldo 18 + movement ADJUST menunjuk baris opname;
ADJUST di luar opname **ditolak**; stok awal lewat ADD_LINE + alasan `STOK_AWAL` masuk 25.

## Prompt 75 — Riwayat, ringkasan landing, export

**SQL:** `sql/inv/sp_75_ThreadReport.sql` (4 SP baca, tidak ada SP tulis)

- Halaman `/gudang/benang/riwayat` (filter tanggal/tipe/alasan/rak/line/project, detail,
  link ke sesi opname, Export Excel) dan `/gudang/benang/pemakaian`
- Kartu ringkasan Whole / Split / Dipakai di line + "hari ini" di landing (HP: di atas
  daftar SKU; tablet: panel kanan saat belum ada SKU dipilih)
- "Isi rak sekarang" di halaman lokasi

Terverifikasi dengan memanggil `ThreadReportService` langsung (data uji dibuat lalu
di-rollback): filter ADJUST menampilkan alasan **"Hilang"** + sesi **SO26-0001**, dua
file `.xlsx` valid (7.059 & 6.822 byte).

## Prompt 76 — App Android: shell, login, pilih tujuan, WebView

**Project baru `TerakarsaApp.Mobile`** (`net10.0-android`, `id.terakarsa.app`, min API 26).
Satu-satunya perubahan di API: `GET api/health` (anonymous).

- Login native (endpoint & DTO sama dengan web), token di SecureStorage
- Pilih tujuan per module: Dashboard Utama / Admin Gudang / PO TNI (satu tujuan → langsung)
- WebView dibuka **sudah login** (token disuntik ke `localStorage` `authToken`/`refreshToken`)
- Dua alamat server + mode Auto (cek `api/health` 1,5 detik), badge "Lokal"/"Internet"
- Pinning fingerprint SHA-256 sertifikat server lokal (HttpClient **dan** WebView)
- Kamera (scan QR) & `<input type=file>` diteruskan ke web

## Prompt 77 — Print service Bluetooth

**SQL:** `sql/inv/alter_77_print_devices_mobile.sql` · `sql/inv/seed_77_print_admin_module.sql`

- Library baru **`TerakarsaApp.Printing`** — `TsplBuilder` dipindah dari PrintService;
  dipakai bersama PrintService Windows & app Android
- `print_devices` + `transport` / `device_token` / `last_seen_at` / `last_seen_info`;
  SP RegisterMobile, ListMobile, ListAll, ByToken, PrintJobRoute_List/_Manage
- `SIS_PrintJob_Claim` & `SIS_PrintJob_Report` dapat `@DeviceId` **opsional**
- API: filter `RequirePrintAuth` (API key **atau** `X-Print-Device-Token`, tidak boleh
  dicampur) + `PrintAdminController`
- Web: `/admin/printer` (module `PRINT_ADMIN`) — pindah job_type antar device tanpa SQL
- Mobile: Setting → Print Service (pilih printer pairing, daftarkan HP, switch Aktif,
  test print, log 50 baris) + foreground service `connectedDevice`

**Bukti layout label tidak berubah**: `BUNDLE_LABEL` dirender dari payload yang sama
dengan `TsplBuilder` versi sebelum pemindahan dan versi sesudahnya →
`diff` **kosong**, MD5 identik (`a3ebd243263db4574e7bde1a7fa80b94`, 3.803 byte).

---

## Keputusan yang saya ambil sendiri

1. **Landing per role** = kolom `dbo.Users.home_route` + claim JWT `home_route`. Fallback
   role→route ditegakkan **di SP** (`CASE WHEN Role='WAREHOUSE' THEN '/gudang/benang'`),
   jadi user baru dari halaman User Management langsung benar tanpa mengisi kolom.
2. **Foto SKU disajikan `ThreadPhotoController` tanpa `[Authorize]`** — `<img src>` tidak
   bisa mengirim header Authorization dan daftar SKU penuh thumbnail. Nama file GUID acak;
   path traversal & nama non-GUID ditolak. (`[AllowAnonymous]` per-action TIDAK cukup di
   controller ber-`[RequireModule]` — filter itu tetap jalan.)
3. **`sku_code` tidak di-regenerate saat edit SKU** — label QR sudah tertempel di kones.
4. **Alamat di app Android = alamat WEB, bukan API.** Prompt menulis
   `GET {LocalBaseUrl}/api/health`, tapi WebView butuh alamat web sedangkan API ada di port
   lain; app menurunkan alamat API dengan aturan yang sama seperti `TerakarsaApp.Client`.
5. **QR label benang dirender QRCoder jadi BITMAP**, bukan command `QRCODE` bawaan printer
   seperti teks prompt — firmware TSC TTP-244 Pro salah merendernya (alasan sama dengan
   BUNDLE_LABEL/PACK_LABEL, sudah jadi keputusan lama di repo ini).
6. **Kolom teks label 30×20 mulai x=108, bukan 125** (QR ternyata hanya 92 dot), dan nama
   warna turun ke font kecil kalau tidak muat — supaya "MERAH CABE" tidak terpotong jadi
   "MERAH ...".
7. **Resolusi opname untuk kones split** (`MOVE_SPLIT` / `ADJUST_SPLIT` di
   `@ResolutionsJson`) adalah tambahan atas skema prompt — tanpa itu kones split tidak bisa
   diselesaikan saat tutup sesi.
8. **Action `CLOSE` tidak boleh dipanggil lewat `INSERT ... EXEC`** (INSERT-EXEC tidak bisa
   bersarang). Dicatat di SP; API & skrip uji memakai EXEC biasa.
9. **`TerakarsaApp.Mobile` TIDAK didaftarkan di `TerakarsaApp.slnx`** supaya
   `dotnet build TerakarsaApp.slnx -v q` (perintah harian di CLAUDE.md) tidak gagal/lambat
   di mesin tanpa workload Android. Build terpisah: `dotnet build TerakarsaApp.Mobile -v q`.
   `TerakarsaApp.Printing` **ikut** di slnx (dibutuhkan PrintService).
10. **Model payload label tetap di `TerakarsaApp.Shared`**, tidak dipindah ke
    `TerakarsaApp.Printing` — API & Client juga memakainya.
11. **UI app Android code-only (tanpa XAML)** — hanya 4 layar utilitas; tampilan sebenarnya
    tetap di web.
12. **Pemindai QR `/gudang/benang/scan` memakai ulang `window.tniScanner`** (perilakunya
    identik: kamera menyala terus, dedupe 3 detik, bunyi, wake lock) daripada menduplikasi
    ~100 baris JS. Dicatat di `tniScanner.js`.
13. **Module `PRINT_ADMIN` baru di-seed** (sebelumnya routing printer hanya lewat SQL).
14. Workload `maui-android` **tidak berhasil dipasang** (butuh elevasi + mesin menunggu
    reboot), tapi ternyata **tidak diperlukan**: paket `android` + `maui-windows` yang sudah
    ada cukup untuk build `net10.0-android`.

## Penyimpangan yang perlu Anda tahu

- **Pinning sertifikat di WebView hanya berlaku Android 10+** (`SslCertificate.X509Certificate`
  baru ada di API 29). Di Android 8/9, pasang sertifikat server lokal ke trust store
  perangkat. Pemanggilan API (login) tetap ter-pinning di semua versi.
- **Pengujian perangkat belum dilakukan**: tidak ada emulator Android maupun printer
  XP-P323B di mesin ini. Build sukses, tapi login di HP, WebView, Bluetooth, dan cetak
  fisik perlu Anda uji.
- **Label 30×20 belum pernah dicetak di atas kertas.** Owner perlu mengganti roll printer
  TSC ke 30×20 mm (atau memindahkan route ke HP) sebelum menekan Cetak.

---

## Langkah uji manual (owner)

### A. Master & stok awal
1. Login `admin` → menu **Gudang → Stok Benang**.
2. **Kelola rak**: buat rak sesuai gudang (mis. A1, B5, S1 "Rak split").
3. **Jenis & merk**: jenis sudah ada (Poly/Cotton/Spun/Nylon); tambah merk (mis. Astra).
4. **+ SKU baru**: jenis, merk, warna, kode warna, jenis kones, foto (boleh belakangan).
   Perhatikan kode SKU yang dibuat sistem, mis. `BN-POL-AST-2041-B`.
5. **Stok awal**: Opname → Mulai opname (pilih semua rak) → buka rak → **Scan SKU
   berikutnya** (ketik `TB:<sku_code>` lalu Enter) → isi jumlah fisik → Selesaikan rak →
   **Tutup sesi** → pilih alasan **Stok awal** → Posting.
6. Cek saldo di landing & detail SKU.

### B. Operasional harian
1. **Terima**: Terima benang masuk → pilih SKU, jumlah, rak → Simpan.
2. **Ambil**: Scan → hasil SKU → Ambil → pilih rak, jumlah, line, project (atau keterangan)
   → tombol menunjukkan "Simpan · 6 kones dari A1".
3. **Kembali**: Scan label SKU → Kembali (timbang) → berat netto tanpa tube, line asal,
   rak simpan → Simpan → muncul kode kones `SP-xxxxxx` → **Cetak label**.
4. **Scan kones split** (`TS:SP-xxxxxx`): Ambil split / Timbang ulang / Pindah / Habis /
   Cetak ulang label.
5. **Riwayat**: filter tipe **Penyesuaian** → kolom alasan tampil tebal; **Export Excel**.

### C. Login admin gudang
1. Logout → login `gudang` / `gudang123` → harus **langsung** ke `/gudang/benang`.
2. Ganti password di halaman User Management (lewat akun admin).

### D. App Android
1. `dotnet publish TerakarsaApp.Mobile -c Release -f net10.0-android -p:AndroidPackageFormat=apk`
   (isi `signing.local.json` dulu — lihat `TerakarsaApp.Mobile/README.md`).
2. Install di HP (izinkan "unknown sources").
3. Pengaturan server: alamat lokal `https://192.168.8.233` (alamat WEB), mode Auto,
   **Ambil fingerprint dari server lokal** → Percayai → Simpan → **Uji koneksi**.
4. Login → pilih **Admin Gudang** → halaman harus terbuka sudah login.
5. Coba scan QR dari dalam app (izin kamera) dan ganti foto SKU (pemilih berkas).

### E. Print service Bluetooth
1. Pairing XP-P323B di pengaturan Bluetooth Android.
2. App → Pengaturan → **Buka Print Service** → Muat daftar printer → pilih printer →
   **Daftarkan HP ini**.
3. Web (admin) → **Sistem → Printer & Routing** → pindahkan `THREAD_SKU_LABEL` dan
   `THREAD_SPLIT_LABEL` ke device HP.
4. App → switch **Aktif** (terima permintaan hemat baterai) → **Test print**.
5. Dari web di app: Kembali & Timbang → Simpan → **Cetak label** → label keluar dari
   printer HP dalam ±3 detik; statusnya berubah "Tercetak".
