# Prompt 85 — Station: kode login terkunci, peringatan ambil alih, login ulang otomatis

Lanjutan Prompt 20 (pairing) dan Prompt 84 (token hanya dihapus pada 401 — harus sudah
terpasang). Prompt ini mencakup SQL + API + web. App Android ada di Prompt 86.

**Syarat utama: diimplementasikan saat stasiun sedang dipakai. Tidak ada perangkat yang
sedang login boleh tertendang karena deploy ini** (lihat §9).

## Prasyarat — kerjakan di atas perubahan `alter_87` (allow_all_divisions)

Saat prompt ini ditulis ada perubahan lain yang belum di-commit di file-file stasiun yang
sama: `sql/alter_87_station_allow_all_divisions.sql` (flag `stations.allow_all_divisions`,
header `X-Station-Division`, `SIS_Station_GetByToken` + `GetByTokenAsync(token, divisionId)`,
`StationTokenHandler.DivisionKey`). Baca keadaan file **terkini** sebelum mengubah apa pun,
dan pertahankan logika divisi itu utuh — terutama di `RequireStationTokenAttribute`,
`StationTokenHandler`, `sp_Station_Select.sql`, dan `sp_Station_Manage.sql`. "Tidak
mengubah `SIS_Station_GetByToken`" di bawah berarti tidak mengubahnya **lagi** di prompt ini.

## 0. Latar

1 stasiun = 1 perangkat tetap. Sekarang setiap kali token hilang dari perangkat
(storage dibersihkan, origin berubah, dsb.) operator harus minta kode pairing baru ke
admin. Yang diinginkan:

- Stasiun bisa diberi **kode login terkunci**: permanen, bisa dipakai berulang. Disimpan
  di Pengaturan app Android (Prompt 86) supaya perangkat bisa login ulang sendiri.
- Login dari perangkat lain tetap "saling tendang" (token dirotasi), tapi **selalu lewat
  peringatan** yang menyebut perangkat yang sedang memakai stasiun. Tidak pernah ada
  perebutan diam-diam → tidak ada looping saling tendang.
- Kode terkunci bisa di-refresh admin kalau bocor.

## 1. Aturan kode

| | Tidak terkunci (perilaku Prompt 20) | Terkunci (baru) |
|---|---|---|
| Format | 5 huruf besar, tanpa `I`/`O` | 10 karakter huruf besar + angka, tanpa `0 O 1 I L` |
| Masa berlaku | 15 menit, sekali pakai | permanen, bisa dipakai berulang |
| Generate/refresh | ganti kode saja | ganti kode saja (+ konfirmasi) |
| Login dari perangkat lain | peringatan `DIPAKAI\|` | peringatan `DIPAKAI\|` |

- Kode digenerate di API (`StationService`), sama seperti sekarang. Charset lama
  `PairingCodeCharset` diganti dua charset di atas.
- **Generate/refresh tidak pernah merotasi `station_token`** — baik lock maupun non-lock.
  Token hanya berganti saat ada yang klaim (saling tendang) atau "Putuskan Perangkat".
  Alasannya: satu stasiun hanya punya satu token hidup; kalau pemegang kode bocor sudah
  klaim, perangkat asli pasti sudah tertendang, dan klaim berikutnya dengan kode baru
  menendang si pemegang kode bocor.
- Kolom `pairing_code varchar(10)` sudah cukup panjang; unique filtered index
  `UX_stations_pairing_code` tetap berlaku untuk kedua jenis kode.

## 2. SQL — `sql/alter_88_station_login_code_lock.sql` (baru, idempotent)

Tambah kolom ke `stations` dengan `ALTER TABLE ... ADD` (**tanpa** recreate table,
`station_token` tidak disentuh):

- `pairing_code_locked bit not null` + default constraint `0`
- `paired_device_id varchar(64) null` — ID perangkat yang terakhir klaim
- `paired_device_name nvarchar(100) null`
- `last_seen_at datetime2 null` — terakhir perangkat pemegang token memanggil API

Perbarui juga blok `stations` di `sql/create_tables_tmos_final.sql`.

## 3. SP — `sql/sp_Station_Manage.sql` (`SIS_Station_Manage`)

Parameter baru, semuanya opsional: `@DeviceId VARCHAR(64) = NULL`,
`@DeviceName NVARCHAR(100) = NULL`, `@Force BIT = 0`.

**`CLAIM_PAIRING`** (ditulis ulang, tetap satu aksi):

- Dalam transaksi, baca baris stasiun dengan `WITH (UPDLOCK, HOLDLOCK)`:
  `UPPER(pairing_code) = UPPER(@PairingCode)` (supaya kode campuran besar-kecil buatan
  sebelum deploy tetap cocok), `is_active = 1`, `deleted_at IS NULL`, dan
  (`pairing_code_locked = 1` **atau** `pairing_code_expires_at > SYSDATETIME()`).
- Tidak ketemu → pesan lama `Kode pairing tidak valid atau sudah kedaluwarsa.`
- **Peringatan ambil alih** — hanya kalau `@DeviceId IS NOT NULL` (untuk `NULL` lihat §9):
  kalau `paired_at IS NOT NULL` (ada perangkat pemegang token) **dan**
  (`paired_device_id IS NULL` **atau** `paired_device_id <> @DeviceId`) **dan**
  `@Force = 0` → rollback lalu error
  `DIPAKAI|<paired_device_name, atau "Perangkat lama" kalau NULL>|<ISNULL(last_seen_at, paired_at) format 126, atau kosong>`.
  `paired_device_id IS NULL` berarti perangkat lama yang belum teradopsi — **bukan**
  stasiun bebas.
- Perangkat yang sama (`paired_device_id = @DeviceId`) → lolos tanpa peringatan.
- Lolos → `station_token = @NewToken`, `paired_at = last_seen_at = SYSDATETIME()`,
  `paired_device_id = @DeviceId`, `paired_device_name = @DeviceName`,
  `pairing_code`/`pairing_code_expires_at` di-NULL-kan **hanya kalau tidak terkunci**,
  `updated_at` diisi seperti sekarang. `SELECT StationId` seperti sekarang.
- `RAISERROR` dengan pesan dinamis memakai bentuk `RAISERROR('%s', 16, 1, @Msg)` supaya
  nama perangkat yang mengandung `%` tidak merusak format.

**`GENERATE_PAIRING`**: kalau stasiun terkunci → `Kode login stasiun ini terkunci. Buka
kunci dulu untuk membuat kode pairing sekali pakai.` Selain itu tetap.

**`LOCK_CODE`** (baru, dipakai untuk kunci **dan** refresh): validasi stasiun hidup &
aktif; `pairing_code = @PairingCode`, `pairing_code_expires_at = NULL`,
`pairing_code_locked = 1`, `updated_at/by`. `SELECT @PairingCode AS PairingCode`. Tidak
menyentuh token maupun kolom `paired_*`.

**`UNLOCK_CODE`** (baru): `pairing_code = NULL`, `pairing_code_expires_at = NULL`,
`pairing_code_locked = 0`, `updated_at/by`. Tidak menyentuh token — perangkat yang sedang
jalan tetap jalan.

**`UNPAIR`**: seperti sekarang + `paired_device_id`, `paired_device_name`,
`last_seen_at` di-NULL-kan. **Perbaikan:** `pairing_code`/`pairing_code_expires_at` hanya
di-NULL-kan kalau **tidak terkunci** — kode terkunci tidak boleh hilang karena tombol
"Putuskan Perangkat" atau "Sambungkan ulang".

**`TOUCH`** (baru): `last_seen_at = SYSDATETIME()`; adopsi perangkat lama:
`paired_device_id` diisi `@DeviceId` hanya kalau masih `NULL`; `paired_device_name` diisi
`@DeviceName` kalau `paired_device_id` masih `NULL` atau sama dengan `@DeviceId`.
**Tidak** mengubah `updated_at`/`updated_by` (telemetri, bukan perubahan data).

Aksi `CREATE`/`UPDATE`/`DELETE` tidak diubah.

## 4. SP — `sql/sp_Station_Select.sql`

`SIS_Station_GetAll` (aksi `LIST`) dan `SIS_Station_GetById` menambah kolom:
`PairingCodeLocked`, `LoginCode` (`CASE WHEN pairing_code_locked = 1 THEN pairing_code END`
— kode sekali pakai tetap tidak dikembalikan), `PairedDeviceName`, `LastSeenAt`.
Cek dulu semua SP yang dipetakan ke `StationDto` — EF menuntut setiap properti DTO ada
sebagai kolom.

`SIS_Station_GetByToken` **tidak diubah**, dan `StationMeDto` **tidak** mendapat kode login
(perangkat tidak boleh bisa membaca kode dari API).

## 5. API

**Admin (`StationController`, JWT + `STATION_MANAGE`)**

- `POST api/station/{id}/login-code/lock` → generate kode 10 karakter, `LOCK_CODE`, retry
  saat bentrok unique index (pola `GeneratePairingCodeAsync`). Dipakai juga untuk refresh.
  Respons DTO baru `StationLoginCodeResult { Code, Link }`, `Link` =
  `{PublicBaseUrl}/station/{Code}` (format sama dengan link pairing sekarang).
- `POST api/station/{id}/login-code/unlock` → `UNLOCK_CODE`.
- `GeneratePairingCodeAsync` memakai charset 5 huruf baru.
- `StationDto` + `PairingCodeLocked`, `LoginCode`, `PairedDeviceName`, `LastSeenAt`.

**Perangkat (`StationClaimController`)**

- `StationClaimRequest` + `DeviceId`, `DeviceName`, `Force`.
- Validasi kode: `^[A-Za-z0-9]{5}$` atau `^[A-Za-z0-9]{10}$`, lalu `ToUpperInvariant()`.
  Aturan "huruf saja" hanya berlaku saat *membuat* kode — kode berangka buatan sebelum
  deploy tetap bisa diklaim sampai hangus.
- `DeviceName`: buang karakter `|`, trim, maks 100. `DeviceId`: maks 64. `DeviceId`
  kosong → diteruskan sebagai `NULL` (client lama, §9).
- Rate limit policy baru `station-claim` (pola policy `auth` di `Program.cs`): fixed
  window 10 / menit / IP, dipasang hanya di `claim`. Catatan: kalau API diakses lewat
  proxy publik dan `RemoteIpAddress` berisi IP proxy, batasnya jadi bersama — laporkan
  kondisinya, jangan ubah konfigurasi forwarded headers di prompt ini.
- `logout` tidak berubah.

**Kehadiran perangkat**

- Client mengirim header `X-Station-Device-Id` dan `X-Station-Device-Name`
  (URI-escaped) di semua request stasiun (§6).
- `RequireStationTokenAttribute`: setelah stasiun ditemukan, panggil `TOUCH` lewat
  singleton baru (mis. `StationPresenceTracker`, `ConcurrentDictionary<int, DateTime>`)
  — **paling sering sekali per 60 detik per stasiun**, supaya polling tidak menulis ke DB
  di setiap request. Header boleh tidak ada (client lama). Kegagalan `TOUCH` ditelan +
  di-log, tidak boleh menggagalkan request.

## 6. Web — halaman stasiun (`StationDevice.razor`, `StationTokenHandler`, `StationDeviceApiService`)

**Identitas perangkat (localStorage)**

- `stationDeviceId` — GUID `"N"`, dibuat sekali kalau belum ada.
- `stationDeviceName` — kalau belum ada, diturunkan dari user agent lewat fungsi JS kecil
  (mis. `Chrome · Android`, `Edge · Windows`). Di app Android kedua key ini disuntik app
  (Prompt 86).
- `StationTokenHandler` menambahkan kedua header di §5.
- `ClaimAsync` mengirim `DeviceId`, `DeviceName`, `Force`.

**Peringatan ambil alih**

Error yang diawali `DIPAKAI|` → modal: *"Stasiun ini sedang dipakai oleh {nama} (aktif
{waktu relatif}). Ambil alih? Perangkat itu akan keluar dari stasiun."* → `Ambil alih`
mengulang klaim dengan `Force = true`. Waktu relatif: `baru saja` / `N menit lalu` /
`N jam lalu` / `dd MMM HH:mm`; kosong → `tidak diketahui`.

**Klaim dulu, logout belakangan** (perbaikan jalur `/station/{kode}` saat sudah punya token)

Sekarang `OnInitializedAsync` memanggil `LogoutAsync` + `ReleaseToken` **sebelum** klaim;
kalau kodenya hangus, token lama ikut mati dan perangkat yatim. Urutan baru:

1. `GetMeAsync` dengan token lama untuk tahu stasiun lamanya (401 → anggap tidak ada).
2. Klaim kode baru.
3. Gagal → token lama tetap, tampilkan error, lanjut memakai stasiun lama seperti biasa.
4. Sukses → kalau stasiun lama ada **dan berbeda** dari `StationId` hasil klaim, panggil
   `LogoutAsync` **sebelum** token baru ditulis (handler masih membaca token lama). Stasiun
   yang sama → jangan logout (UNPAIR akan mematikan token yang baru didapat). Lalu simpan
   token baru.

**Token ditolak saat halaman sedang jalan**

- `StationTokenHandler` melapor ke notifier **singleton** baru (handler HttpClientFactory
  punya scope DI sendiri, jadi service scoped tidak sampai ke komponen) setiap kali
  request yang membawa token dijawab 401 — kecuali `logout`.
- Halaman berlangganan: hentikan polling, tampilkan kartu *"Perangkat ini sudah keluar dari
  stasiun — diambil perangkat lain atau diputus admin."* Tombolnya: mode browser →
  `Masukkan kode pairing` (`ReleaseToken`, ke layar setup); mode app → `Sambungkan ulang`
  (klaim dengan kode terkunci; bisa memunculkan `DIPAKAI|`).
- **Tidak ada klaim otomatis di sini.** Klaim otomatis hanya terjadi saat halaman dimuat
  (aturan mode app di bawah). Ini yang mencegah looping saling tendang.

**Mode app (localStorage `stationLockCode` terisi — disuntik app Android)**

- Saat halaman dimuat: kalau belum punya token, atau `stationLockCodeUsed` ≠
  `stationLockCode` (kode di Pengaturan app diganti) → klaim otomatis dengan
  `stationLockCode` (pakai urutan "klaim dulu, logout belakangan" kalau ada token lama).
  Sukses → simpan `stationLockCodeUsed = stationLockCode`.
- `GetMeAsync` → 401 saat dimuat → hapus token → klaim otomatis sekali.
- Input kode pairing manual disembunyikan.
- Klaim gagal bukan `DIPAKAI|` → *"Kode stasiun di Pengaturan app tidak berlaku. Minta kode
  terbaru ke admin lalu perbarui di Pengaturan app."* + tombol `Coba lagi`. Server tidak
  terjangkau → layar "mencoba lagi" Prompt 84 (yang dicoba ulang klaimnya). Dua pesan ini
  harus berbeda.
- Tombol `Keluar` diganti `Sambungkan ulang` (tanpa konfirmasi): `LogoutAsync` → hapus
  token saja (pilihan operator, `stationLockCode*`, `stationDevice*` tetap) → klaim
  otomatis. Setelah UNPAIR stasiun bebas, jadi tidak muncul peringatan.

Mode browser (tanpa `stationLockCode`): tombol `Keluar` + konfirmasinya tetap seperti
sekarang.

## 7. Web — Kelola Stasiun (`TerakarsaApp.Client/Pages/Station.razor`)

- Daftar: badge `Kode terkunci`; kalau `PairedAt` terisi tampilkan
  `Dipakai: {PairedDeviceName ?? "Perangkat lama"} · aktif {waktu relatif LastSeenAt}`.
- Stasiun **tidak terkunci**: tombol `Buat Kode Pairing` tetap + tombol baru
  `Kunci Kode Login` (tanpa konfirmasi — tidak menendang siapa pun) → modal kode login.
- Stasiun **terkunci**: `Buat Kode Pairing` disembunyikan; tombol `Kode Login` membuka
  modal: QR (`qrCodeRenderer.render`, isi = link), kode besar monospace, salin link,
  tombol `Refresh Kode` dan `Buka Kunci`. Modal dibuka dari `LoginCode` di daftar tanpa
  generate ulang (link dirakit di client dengan aturan yang sama, atau tambahkan
  `LoginLink` di `StationDto` — pilih salah satu, konsisten).
- Konfirmasi `Refresh Kode` (pola `ConfirmDeleteModal`): *"Kode lama langsung tidak
  berlaku. Perangkat yang sedang jalan tetap jalan, tapi kode di app Android harus diganti.
  Kalau tidak, perangkat tidak bisa masuk lagi begitu ter-logout."*
- Konfirmasi `Buka Kunci`: *"Kode login dihapus. Perangkat yang sedang jalan tetap jalan,
  tapi app Android tidak bisa login ulang otomatis sampai stasiun dikunci lagi dan kodenya
  diperbarui."*
- Konfirmasi `Putuskan Perangkat` untuk stasiun terkunci ditambah kalimat: *"Perangkat
  dengan kode login terkunci bisa masuk lagi memakai kode yang sama — refresh kode kalau
  ingin menutup aksesnya."*

## 8. Yang TIDAK boleh dilakukan

- Recreate tabel `stations`, mengubah format/isi `station_token` di script SQL, atau
  apa pun yang membuat perangkat yang sedang login kehilangan token.
- Merotasi token saat generate/refresh/kunci/buka kunci kode.
- Mengubah `SIS_Station_GetByToken`, aksi `CREATE`/`UPDATE`/`DELETE`, atau menambahkan kode
  login ke `StationMeDto`.
- Klaim otomatis di luar saat halaman dimuat (polling, handler 401, timer).
- Menyentuh tab-tab stasiun (IN/OUT/WIP/Packing/Absen/Rekap) atau alur operator.
- Mengerjakan app Android (Prompt 86).

## 9. Kompatibilitas deploy (stasiun sedang dipakai)

Urutan: Prompt 84 sudah terpasang → SQL → API → client Prompt 85.

- **SQL dulu**: hanya `ADD COLUMN` + `CREATE OR ALTER` SP; schema lock sesaat di tabel
  kecil. API lama memanggil `CLAIM_PAIRING` tanpa `@DeviceId` → `NULL` → **perilaku lama**
  (tanpa peringatan), jadi jendela SQL→API aman. Pastikan API lama tetap jalan dengan
  kolom tambahan di `SIS_Station_GetAll`/`GetById` (EF mengabaikan kolom berlebih —
  verifikasi; kalau ternyata tidak, laporkan dan tulis bahwa SQL + API harus dipasang
  bersamaan).
- **API**: client lama tidak mengirim header perangkat → `TOUCH` hanya memperbarui
  `last_seen_at`; klaim dari client lama (`DeviceId` kosong) → perilaku lama.
- **Client 85**: perangkat lama teradopsi diam-diam lewat `TOUCH` begitu memuat client baru
  (`paired_device_id` terisi, tanpa login ulang).
- Selama perangkat lama belum teradopsi, perangkat lain yang klaim tetap kena
  `DIPAKAI|Perangkat lama|...`.
- Perangkat browser yang storage-nya terhapus kehilangan `stationDeviceId` juga → dianggap
  perangkat lain → peringatan menyebut dirinya sendiri. Wajar; operator tinggal ambil alih.

## 10. Verifikasi

- `dotnet build TerakarsaApp.slnx -v q` lolos.
- Telusuri skenario berikut di kode (dan tulis hasilnya di laporan):
  1. Perangkat yang sedang login sebelum deploy tetap login setelah SQL, API, dan client
     baru terpasang; `paired_device_id` terisi ≤ 1 menit setelah memuat client baru.
  2. Perangkat lain klaim stasiun itu → `DIPAKAI|Perangkat lama|...`.
  3. Perangkat yang sama klaim ulang → tanpa peringatan.
  4. Kode terkunci dipakai dua kali → dua-duanya berhasil; kode sekali pakai dipakai dua
     kali → yang kedua gagal.
  5. Refresh kode terkunci → kode lama ditolak; perangkat yang sedang jalan tetap jalan.
  6. `UNPAIR` / `Sambungkan ulang` pada stasiun terkunci → kode tetap ada.
  7. Klaim ke-11 dalam 1 menit dari IP yang sama → 429.
  8. Scan `/station/{kode hangus}` di perangkat yang sudah login → tetap login di stasiun lama.
- Akhiri dengan daftar file + script SQL yang harus dijalankan manual (urutan: alter_88,
  sp_Station_Manage, sp_Station_Select).
