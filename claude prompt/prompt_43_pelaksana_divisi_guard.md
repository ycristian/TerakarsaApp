# Prompt 43 — Guard Divisi Pelaksana/Penerima (SP) + Auto-Login Operator (Client + SP)

## Prasyarat

Setelah Prompt 40 (`resource_counterpart` + "penerima mengikat pelaksana").
Menyentuh `SIS_WorkflowLog_Manage`, `SIS_Bundle_ScanInfo`, `BundleService.cs`,
dan `BundleScanPublic.razor` — beberapa perbaikan independen untuk temuan yang
sama, jangan paralel dengan prompt lain yang menyentuh salah satunya.

## Konteks

Ditemukan lewat bundle uji Q-1 (`B26-001152`): operator login di stasiun Steam &
Pack, tapi baris hasil step "Steam & Packing" tercatat pelaksananya "Trim A1
(Heru)" — resource yang jelas bukan milik divisi Steam & Pack. Ditelusuri sampai
ke step-step sebelumnya (Trim → Press DTF → Steam & Pack), resource yang sama
menempel di semua step itu meski divisinya berbeda-beda.

Ada TIGA lubang independen yang sama-sama berkontribusi, ditambal semuanya di
prompt ini (plus satu bug mapping yang menyembunyikan gejalanya saat
pengujian). **Bagian C adalah akar masalah sebenarnya** — dikonfirmasi lewat
query langsung ke database produksi (read-only): untuk Q-1 di divisi Steam &
Pack, `SIS_Bundle_ScanInfo` mengembalikan `SuggestedResourceId = 17` (Trim A1
Heru, divisi 9) lewat sumber `RIWAYAT`, padahal `@DivisionId` yang diminta = 5
(Steam & Pack). Bagian A dan B tetap valid dan tetap ditambal (jaring pengaman
+ kebersihan restore sesi), tapi tanpa Bagian C, auto-login akan terus
menyarankan resource yang salah divisi berapa kali pun sesi operator
diperbaiki.

**A. Client — `BundleScanPublic.razor` (halaman `/b/{serial}`, dipakai setelah
"Scan QR" dari `/station`) tidak memvalidasi operator yang dipulihkan dari
localStorage milik divisi stasiun yang sedang aktif.** `StationDevice.razor`
(`LoadOperatorSessionAsync`) sudah benar — `savedId` dicocokkan ke `operators`
(daftar resource divisi stasiun ini) sebelum dipakai, jatuh ke
`DefaultResourceId` kalau tidak cocok. `BundleScanPublic.razor` mengklaim
"sama urutan fallback" di komentarnya tapi nyatanya langsung memakai
`stationOperatorId` dari localStorage mentah-mentah tanpa cek keanggotaan
divisi. Akibatnya: operator dari pairing/divisi sebelumnya bisa nyangkut dan
terus terpakai di halaman ini selama `SuggestedResourceId` (auto-login
Prompt 40 §6, kaskade LINE_BUNDLE/PENERIMA/COUNTERPART/RIWAYAT) kebetulan NULL
untuk bundle yang di-scan — "pertahankan operator sesi" jadi mempertahankan
operator yang sudah salah divisi sejak awal.

**B. SP — `SIS_WorkflowLog_Manage` tidak pernah memvalidasi bahwa resource
pelaksana/penerima benar-benar milik divisi step-nya**, di dua action yang
paling sering dipakai (jaring pengaman kalau (A) tetap lolos, atau dipanggil
langsung lewat API tanpa lewat UI):

- **CREATE** (kirim hasil) — `@ActingDivisionId` (stasiun) divalidasi harus sama
  dengan `@DivisionId` (divisi step), tapi `@ResourceId` (pelaksana) sendiri
  tidak pernah dicek `division_id`-nya.
- **RECEIVE** (terima manual) — `@ActingDivisionId` divalidasi harus sama dengan
  `target_division_id`, tapi `@ReceivedByResourceId` yang di-`UPDATE` ke
  `received_by_resource_id` tidak pernah dicek `division_id`-nya harus sama
  dengan divisi tujuan.

Guard ini **sudah ada** di dua action lain pada SP yang sama — pola yang harus
ditiru persis:

- `REVISE_HANDOVER`: `IF @ResourceId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM
  resources WHERE resource_id = @ResourceId AND division_id = @RevDivisionId
  AND deleted_at IS NULL) → RAISERROR('Penjahit bukan milik divisi ini.', 16, 1)`.
- `ADJUST`: `IF @ResourceId IS NULL OR NOT EXISTS (... division_id =
  @AdjDivisionId ...) → RAISERROR('Operator bukan milik divisi ini.', 16, 1)`.

Karena CREATE dan RECEIVE tidak punya guard ini, satu resource dari divisi salah
bisa lolos jadi `resource_id` atau `received_by_resource_id`. Sekali itu terjadi,
aturan Prompt 40 §7 "penerima mengikat pelaksana" mengunci SEMUA step berikutnya
untuk bundle itu ke resource yang sama — jadi kesalahan satu baris menular ke
seluruh sisa timeline bundle (persis pola yang terlihat di Q-1).

Ini murni menambal lubang validasi yang konsisten dengan pola yang sudah ada di
file yang sama — bukan mengubah desain counterpart Prompt 40.

**C. SP — `SIS_Bundle_ScanInfo`, kandidat auto-login ke-4 (`RIWAYAT`) tidak
memfilter `r.division_id = @DivisionId`.** Tiga kandidat lain (`LINE_BUNDLE`,
`PENERIMA`, `COUNTERPART`) semuanya benar menyaratkan resource-nya sendiri
`division_id = @DivisionId`, sesuai komentar pembuka blok ("kandidat WAJIB
resource hidup + aktif + division_id = @DivisionId"). Kandidat `RIWAYAT` cuma
menyaratkan `t.DivisionId = @DivisionId` (baris LOG-nya ada di divisi ini) tapi
tidak mensyaratkan resource pelaksana baris itu SENDIRI juga milik divisi yang
sama — jadi begitu ada baris lama yang pelaksananya sudah salah divisi (lubang
Bagian B tanpa guard, sebelum prompt ini), `RIWAYAT` malah menyarankan ulang
resource yang salah itu sebagai operator sesi berikutnya. Ini penyebab
"Trim A1 (Heru)" terus menular ke Press DTF lalu Steam & Pack — akar masalah
yang memicu keseluruhan investigasi Q-1.

**Bug tambahan yang ditemukan bersamaan (independen, bukan penyebab tapi
menyembunyikan gejalanya saat pengujian):** `BundleService.cs`
(`GetScanInfoAsync`) memetakan `SuggestedResourceId` dari reader tapi **lupa
memetakan `SuggestedResourceName` dan `SuggestedResourceSource`** — jadi walau
SQL sudah mengembalikan nama yang benar, client selalu menerima nama kosong.
Ini yang membuat badge "Operator otomatis:" tampil tanpa nama di `/b/{serial}`
saat pengujian, sempat mengaburkan diagnosis Bagian C.

## Bagian A — Client: restore operator sesi harus tervalidasi divisi

### A1. `BundleScanPublic.razor` — `LoadBundleAsync`

Urutan sekarang: baca `stationOperatorId` dari localStorage → langsung pakai →
baru fetch `resourceOptions` (`GetResourcesAsync`, khusus dipakai kalau
`!stationScanFailed`) → panggil `ScanAsync`. Ubah urutannya supaya validasi bisa
jalan sebelum `operatorId` dipakai:

1. Setelah `station = await StationApi.GetMeAsync()` dan `stationScanFailed`
   diketahui `false`, fetch `resourceOptions = await StationApi
   .GetResourcesAsync()` LEBIH DULU (dipindah ke atas, sebelum blok penentuan
   `operatorId`) — daftar ini sudah otomatis ter-scope ke divisi stasiun yang
   sedang aktif (endpoint `api/station/resources` pakai `CurrentStation
   .DivisionId`).
2. Baca `savedOperatorId` seperti sekarang, tapi syarat pakai jadi:
   `hasSavedOperator = int.TryParse(savedOperatorId, out var opId) &&
   resourceOptions.Any(o => o.Id == opId)` — persis pola `LoadOperatorSessionAsync`
   di `StationDevice.razor` (`operators.Any(o => o.Id == id)`).
3. Urutan fallback sesudahnya TETAP SAMA (locked → `DefaultResourceId`; tervalidasi
   → operator tersimpan; selain itu → `DefaultResourceId`) — hanya syarat
   "tervalidasi"-nya yang ditambah.
4. Kalau `stationScanFailed = true` (token rusak), `resourceOptions` tidak bisa
   diambil (butuh token valid) — pertahankan perilaku sekarang: operator tidak
   divalidasi dalam kondisi ini (halaman sudah read-only untuk kasus ini).

Efeknya: operator dari divisi/pairing lain tidak pernah lolos jadi `operatorId`
awal halaman ini — kalaupun tersangkut di localStorage, begitu divisi tidak
cocok langsung jatuh ke `DefaultResourceId` (atau tetap `null` kalau stasiun
tidak terkunci dan tidak ada `DefaultResourceId`, memaksa pilih ulang lewat
`/station`).

`ApplyAutoLoginIfNeeded()` (kaskade `SuggestedResourceId`) TIDAK berubah — begitu
`operatorId` awal sudah pasti valid untuk divisi ini, logika "pakai counterpart
kalau ada, kalau tidak pertahankan operator sesi" (Prompt 40 §6) otomatis benar
karena "operator sesi" yang dipertahankan sekarang terjamin milik divisi yang
sedang login.

### A2. Badge "Operator otomatis" ditampilkan di atas baris Operator

Saat ini (`BundleScanPublic.razor` sekitar baris 65-71) badge digabung di baris
yang sama dengan "Operator: {nama}". Ubah jadi baris terpisah DI ATASNYA supaya
lebih menonjol saat auto-login memang terjadi:

```razor
@if (autoLoginApplied)
{
    <p class="mb-1"><span class="badge bg-info">Operator otomatis: @operatorName</span></p>
}
<p class="mb-0 text-muted">
    Operator: <strong class="text-dark">@(operatorName ?? "-")</strong>
</p>
```

Tidak ada perubahan kondisi kapan `autoLoginApplied` di-set — murni penempatan.

## Bagian B — SP: guard divisi di CREATE & RECEIVE

## 1. `SIS_WorkflowLog_Manage` — `CREATE`

Tambahkan guard tepat setelah pengecekan `@ActingDivisionId <> @DivisionId`
("Step ini bukan milik divisi Anda.") dan sebelum validasi qty:

```sql
IF @ResourceId IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM resources WHERE resource_id = @ResourceId AND division_id = @DivisionId AND deleted_at IS NULL
)
BEGIN
    RAISERROR('Pelaksana bukan resource milik divisi ini.', 16, 1);
    RETURN;
END
```

- `@ResourceId` tetap opsional (boleh NULL) — guard hanya aktif kalau diisi,
  sama seperti sifat parameter ini sekarang.
- Berlaku untuk step bundle maupun non-bundle (keduanya pakai `@DivisionId`
  yang sama, sudah di-resolve di awal action).
- Jangan sentuh validasi §7 "penerima mengikat pelaksana" (blok
  `@IncomingReceivedByResourceId`) — guard baru ini independen, berjalan lebih
  dulu.

## 2. `SIS_WorkflowLog_Manage` — `RECEIVE`

Tambahkan guard tepat setelah pengecekan `@ActingDivisionId <>
@RecTargetDivisionId` ("Serah terima ini bukan untuk divisi Anda.") dan sebelum
`BEGIN TRAN`:

```sql
IF @ReceivedByResourceId IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM resources WHERE resource_id = @ReceivedByResourceId AND division_id = @RecTargetDivisionId AND deleted_at IS NULL
)
BEGIN
    RAISERROR('Penerima bukan resource milik divisi ini.', 16, 1);
    RETURN;
END
```

- Jangan tambahkan wajib-tidak-NULL untuk `@ReceivedByResourceId` — di luar
  cakupan temuan ini, API stasiun sudah menjamin operator terisi sebelum
  memanggil endpoint.

## 3. Deteksi data lama — `sql/repair_43_pelaksana_divisi_check.sql`

Berbeda dari `repair_40_received_by.sql`, di sini **tidak ada cara algoritmis
menentukan resource yang benar** untuk baris yang sudah terlanjur salah — jadi
skrip ini HANYA laporan (read-only, tanpa blok eksekusi), bukan perbaikan
otomatis:

- Bagian 1 — baris `article_workflow_logs` hidup yang `resource_id`-nya terisi
  tapi `division_id` resource itu `<>` `division_id` step (`article_workflows`)
  baris tsb. Tampilkan `workflow_log_id`, `serial`, nama step, divisi step,
  nama resource, divisi resource sebenarnya, `created_at`.
- Bagian 2 — baris hidup yang `received_by_resource_id`-nya terisi tapi
  `division_id` resource itu `<>` `target_division_id` baris tsb. Kolom serupa
  ditambah `received_at`.
- Tidak melakukan UPDATE apa pun. Penanganan tiap baris temuan diputuskan
  manual per kasus (mis. UNRECEIVE lalu RECEIVE ulang oleh resource yang benar,
  atau REVISE_HANDOVER untuk baris yang belum diterima) — di luar cakupan
  prompt ini.

## Bagian C — SP: fix kandidat RIWAYAT + mapping SuggestedResourceName/Source

### C1. `SIS_Bundle_ScanInfo` — kandidat 4 (RIWAYAT)

Tambahkan `AND r.division_id = @DivisionId` ke kondisi `WHERE` kandidat RIWAYAT
(section "Prompt 40 §4B saran AUTO-LOGIN operator sesi"), supaya konsisten
dengan 3 kandidat lain di atasnya:

```sql
-- 4. RIWAYAT -- resource_id baris hidup terakhir bundle ini yang division_id = @DivisionId.
IF @SuggestedResourceId IS NULL
BEGIN
    SELECT TOP 1 @SuggestedResourceId = t.ResourceId, @SuggestedResourceName = r.resource_name
    FROM @Timeline t
    INNER JOIN resources r ON r.resource_id = t.ResourceId
    WHERE t.DivisionId = @DivisionId AND r.deleted_at IS NULL AND r.is_active = 1 AND r.division_id = @DivisionId
    ORDER BY t.CreatedAt DESC;
    ...
END
```

- Efeknya: kalau riwayat baris bundle ini di divisi tersebut ternyata dicatat
  oleh resource divisi lain (data lama yang rusak, lihat §3 Bagian B), kandidat
  ini sekarang GAGAL match (bukan malah menyarankan resource yang salah itu) —
  `@SuggestedResourceId` tetap NULL, jatuh ke perilaku "pertahankan operator
  sesi" seperti bundle tanpa saran sama sekali.
- Tidak mengubah 3 kandidat lain (`LINE_BUNDLE`, `PENERIMA`, `COUNTERPART`) —
  sudah benar.

### C2. `BundleService.cs` — `GetScanInfoAsync`

Tambahkan mapping dua kolom yang sudah ada di result set SQL tapi belum pernah
dibaca reader-nya, tepat di bawah baris `SuggestedResourceId = ...`:

```csharp
SuggestedResourceName = reader.IsDBNull(reader.GetOrdinal("SuggestedResourceName")) ? null : reader.GetString(reader.GetOrdinal("SuggestedResourceName")),
SuggestedResourceSource = reader.IsDBNull(reader.GetOrdinal("SuggestedResourceSource")) ? null : reader.GetString(reader.GetOrdinal("SuggestedResourceSource")),
```

Tidak ada perubahan DTO (`SuggestedResourceName`/`SuggestedResourceSource`
sudah ada di `BundleScanBundleDto`, cuma belum pernah diisi).

## Yang TIDAK boleh dilakukan

- Jangan ubah action lain di SP (`UPDATE`, `UNRECEIVE`, `DELETE`,
  `CANCEL_HANDOVER`, `ADJUST`, `REVISE_HANDOVER`) — guard di action itu sudah
  benar.
- Jangan ubah logika counterpart/auto-terima Prompt 39/40 (`ApplyAutoLoginIfNeeded`,
  kaskade `SuggestedResourceId`, §7 "penerima mengikat pelaksana") — perbaikan
  di prompt ini murni validasi identitas/urutan fetch, bukan perubahan alur.
- Jangan sentuh `LoadOperatorSessionAsync`/`SelectOperator`/`ChangeOperator` di
  `StationDevice.razor` — itu sudah benar, jadi acuan pola untuk Bagian A.
- Jangan buat skrip perbaikan otomatis untuk data lama — cukup laporan
  read-only (lihat §3 Bagian B), karena tidak ada sumber kebenaran untuk
  menebak resource yang benar.
- Jangan ubah DTO — `SuggestedResourceName`/`SuggestedResourceSource` di
  `BundleScanBundleDto` sudah ada, Bagian C2 cuma mengisi mapping yang
  terlewat. Bagian A murni reorder + tambah kondisi di Razor, Bagian B murni
  di dalam SP; tidak ada kontrak baru di prompt manapun di sini.
- Jangan ubah 3 kandidat lain (`LINE_BUNDLE`/`PENERIMA`/`COUNTERPART`) di
  `SIS_Bundle_ScanInfo` — sudah benar, hanya kandidat `RIWAYAT` yang bolong.
- Jangan longgarkan pesan galat SP ini jadi warning — tetap RAISERROR keras
  seperti pola existing di REVISE_HANDOVER/ADJUST.

## Urutan deploy

1. `sp_WorkflowLog_Manage.sql` (dua guard baru, Bagian B) dan
   `sp_Bundle_ScanInfo.sql` (fix kandidat RIWAYAT, Bagian C1) — boleh
   bersamaan, keduanya independen.
2. Deploy API (`BundleService.cs`, Bagian C2) + Client (`BundleScanPublic.razor`,
   Bagian A).
3. Jalankan `repair_43_pelaksana_divisi_check.sql` (read-only) untuk melihat
   baris/bundle yang sudah terlanjur salah, termasuk Q-1 (`B26-001152`), lalu
   koreksi manual satu per satu.

## Verifikasi

1. `dotnet build` sukses (tidak ada perubahan kontrak DTO, jadi API tidak
   terpengaruh).
2. Skenario manual — Bagian C (paling kritis, akar masalah):
   - Bundle yang riwayatnya di divisi ini SUDAH tercatat oleh resource divisi
     lain (data lama rusak, mis. Q-1 di Steam & Pack) → `SuggestedResourceId`
     sekarang NULL (bukan lagi menyarankan resource yang salah itu), badge
     "Operator otomatis" tidak muncul, operator sesi dipertahankan.
   - Bundle dengan riwayat bersih (resource pencatat sebelumnya benar-benar
     milik divisi ini) → RIWAYAT tetap menyarankan resource itu seperti biasa
     (regresi negatif dicek: kandidat ini jangan sampai jadi tidak pernah
     match untuk kasus normal).
   - Badge "Operator otomatis: {nama}" sekarang tampil dengan NAMA terisi
     (bukan kosong) setiap kali salah satu dari 4 kandidat match.
3. Skenario manual — Bagian A:
   - Pairing device sebagai stasiun divisi X, pilih operator, lalu (simulasi)
     re-pairing device yang sama sebagai stasiun divisi Y tanpa logout bersih
     → buka `/b/{serial}` bundle divisi Y → operator TIDAK ikut jadi resource
     divisi X; jatuh ke `DefaultResourceId` divisi Y atau kosong.
   - Bundle dengan `SuggestedResourceId` valid (mis. counterpart) → badge
     "Operator otomatis: {nama}" tampil DI ATAS baris "Operator:", operator
     sesi berubah ke resource itu.
   - Bundle tanpa `SuggestedResourceId` tapi operator sesi sudah valid untuk
     divisi ini → operator sesi dipertahankan seperti biasa, tidak ada badge.
4. Skenario manual — Bagian B:
   - Kirim hasil (CREATE) di stasiun divisi A dengan `@ResourceId` milik divisi
     B (paksa lewat API/Postman) → ditolak 'Pelaksana bukan resource milik
     divisi ini.'
   - Kirim hasil dengan `@ResourceId` NULL (step non-bundle tanpa pelaksana
     wajib, kalau ada alurnya) → tetap lolos seperti semula.
   - RECEIVE manual dengan `@ReceivedByResourceId` milik divisi lain (paksa
     lewat API) → ditolak 'Penerima bukan resource milik divisi ini.'
   - Alur normal (operator sesuai divisinya di kedua action) → tidak ada
     regresi, berjalan seperti sebelumnya.
   - `repair_43_pelaksana_divisi_check.sql` menampilkan Q-1 sebagai salah satu
     baris bermasalah.
5. Di akhir: daftar file dibuat/diubah + daftar script SQL yang harus
   dijalankan manual.
