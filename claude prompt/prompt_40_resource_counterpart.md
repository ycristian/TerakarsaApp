# Prompt 40 — Counterpart Resource: Penerima Auto-Receive + Auto-Login Operator dari Bundle

## Prasyarat

Wajib setelah Prompt 34 (`auto_receive`). Menyentuh `SIS_WorkflowLog_Manage`,
`SIS_Bundle_ScanInfo`, `SIS_Station_Operations` — jalankan berurutan, jangan paralel
dengan prompt lain yang menyentuh SP yang sama.

## Konteks

Prompt 34 mengisi `received_by_resource_id` dengan resource **pengirim**. Itu salah
secara data: baris tersebut `target_division_id`-nya divisi lain, jadi kolom penerima
berisi resource milik divisi asal — laporan produksi (Prompt 30) yang mengelompokkan
per divisi + resource jadi salah atribusi.

Perbaikannya bertingkat:

1. Setiap resource pengirim menunjuk **counterpart** — pasangannya di divisi
   berikutnya (Line Sewing 3 → Trim A3). Auto-receive mengisi penerima dari sana.
2. Bila counterpart tidak ada, operator pengirim **wajib memilih** penerima dari
   dropdown resource divisi tujuan. Step ber-`auto_receive` memang dirancang tanpa
   serah terima manual, jadi penerima harus sudah pasti saat hasil dikirim.
3. Karena `received_by_resource_id` kini selalu berisi resource divisi tujuan yang
   benar, kolom itu dipakai untuk **auto-login operator** saat bundle discan di
   stasiun tujuan.

Hasil akhirnya: satu baris log sudah menjawab "siapa yang bertanggung jawab setelah
ini" tanpa melihat tabel master lain.

## 1. Skema — `sql/alter_40_resource_counterpart.sql` (idempotent)

```
ALTER TABLE resources ADD counterpart_resource_id int null
  constraint FK_resources_counterpart foreign key references resources(resource_id);
```

Perbarui juga `sql/create_tables_tmos_final.sql`.

**Definisi "counterpart valid"** (dipakai konsisten di seluruh prompt ini):
`counterpart_resource_id` terisi, resource-nya `deleted_at IS NULL` **dan**
`is_active = 1`, **dan** `division_id`-nya sama dengan divisi tujuan yang sedang
diperiksa. Salah satu tidak terpenuhi → diperlakukan **tidak punya counterpart**
(bukan error).

## 2. `SIS_Resource_Manage` — parameter & validasi

- Tambah `@CounterpartResourceId INT = NULL` (tanda tangan tetap kompatibel).
- Validasi saat CREATE/UPDATE bila diisi:
  1. Counterpart harus resource hidup — 'Counterpart tidak ditemukan.'
  2. Bukan dirinya sendiri — 'Counterpart tidak boleh resource itu sendiri.'
  3. `division_id` counterpart harus **berbeda** dari divisi resource ini —
     'Counterpart harus resource dari divisi lain.'
- Bila divisi resource diubah sehingga sama dengan divisi counterpart-nya →
  kosongkan `counterpart_resource_id`, jangan gagalkan UPDATE.
- Tidak ada validasi rantai/siklus.

`SIS_Resource_GetAll` / `GetById`: tambah `CounterpartResourceId`,
`CounterpartResourceName`, `CounterpartDivisionName` (LEFT JOIN, filter
`deleted_at IS NULL` **di ON clause**).

## 3. `SIS_WorkflowLog_Manage` — CREATE

Tambah parameter `@AutoReceiveResourceId INT = NULL`.

Ganti logika auto-receive Prompt 34 dengan urutan berikut, dijalankan **hanya** bila
step tujuan ber-`auto_receive = 1` dan `target_division_id` tidak NULL:

1. **Counterpart valid** terhadap `target_division_id` → pakai counterpart.
   `@AutoReceiveResourceId` **diabaikan total** — tidak boleh menimpa.
2. Counterpart tidak valid dan `@AutoReceiveResourceId` NULL → **tolak CREATE**:
   'Penerima wajib dipilih karena step tujuan menerima otomatis.'
3. Counterpart tidak valid dan `@AutoReceiveResourceId` terisi → validasi resource
   itu hidup + `is_active = 1` + `division_id = target_division_id`
   ('Penerima bukan resource aktif di divisi tujuan.'), lalu pakai.

Pengisian: `received_at = SYSDATETIME()`, `received_by_resource_id` = hasil di atas,
`received_remark` seperti Prompt 34.

Bila `auto_receive = 0` → tidak ada pemeriksaan counterpart maupun
`@AutoReceiveResourceId` sama sekali; `@AutoReceiveResourceId` yang terlanjur dikirim
diabaikan diam-diam.

`received_by_resource_id` **tidak boleh lagi** diisi resource pengirim dalam kondisi
apa pun.

## 4. SP read

### `SIS_Bundle_ScanInfo` — result set 3 (aksi)

**A. Info penerima untuk form kirim hasil** (dipakai saat aksi = COMPLETE):

- `NextAutoReceive` (bit) — `auto_receive` step tujuan.
- `NextTargetDivisionId`, `NextTargetDivisionName`.
- `NextCounterpartResourceId`, `NextCounterpartResourceName` — counterpart dari
  resource yang akan mencatat baris (operator sesi, `@ResourceId`), valid terhadap
  `NextTargetDivisionId`. NULL bila tidak ada.
- `ReceiverPickerRequired` (bit) = 1 hanya bila `NextAutoReceive = 1` **dan**
  counterpart NULL.

**B. Saran operator untuk auto-login** — `SuggestedResourceId`,
`SuggestedResourceName`, `SuggestedResourceSource`. Semua kandidat wajib resource
hidup + `is_active = 1` + `division_id = @DivisionId`; kandidat pertama yang lolos
dipakai:

| Urutan | Sumber | Asal nilai |
|---|---|---|
| 1 | `LINE_BUNDLE` | `bundles.resource_id` — **hanya** bila aksi = COMPLETE pada step ber-bundle pertama |
| 2 | `PENERIMA` | `received_by_resource_id` baris bundle ini yang `target_division_id = @DivisionId` dan `received_at` terisi (baris terbaru) |
| 3 | `COUNTERPART` | counterpart dari `resource_id` baris masuk yang `target_division_id = @DivisionId` dan `received_at IS NULL` |
| 4 | `RIWAYAT` | `resource_id` baris hidup terakhir bundle ini yang `division_id = @DivisionId` |
| — | NULL | tidak ada yang cocok |

`LINE_BUNDLE` didahulukan pada kasusnya karena `SIS_WorkflowLog_Manage` memang menolak
resource selain `bundles.resource_id` di step ber-bundle pertama — saran lain hanya
berujung error.

`@DivisionId` NULL (halaman publik `/b/{serial}`) → semua kolom di §4A dan §4B NULL.

### `SIS_Station_PendingReceives`

Tambah `SuggestedReceiverResourceId` + `SuggestedReceiverResourceName`: counterpart
dari `resource_id` baris pengirim yang valid terhadap `@DivisionId`. NULL bila tidak
ada. Dipakai sebagai penerima default pada penerimaan manual.

### `SIS_Station_ReceiverOptions` (SP baru, di `sp_Station_Operations.sql`)

Param `@ArticleWorkflowId`, `@BundleId`. Mengembalikan resource hidup + aktif milik
divisi tujuan step berikutnya (`ResourceId`, `ResourceName`), urut nama. Dipakai
mengisi dropdown penerima.

## 5. API

- DTO di `TerakarsaApp.Shared`: tambah semua field baru di atas ke DTO scan &
  pending-receives; `ResourceCreateRequest`/`UpdateRequest`/`ResourceDto` tambah
  `CounterpartResourceId` (+ nama & divisi di DTO baca).
- `StationCompleteRequest`: tambah `AutoReceiveResourceId` (nullable), diteruskan
  apa adanya ke SP. **Jangan** validasi ulang di API — SP satu-satunya penjaga.
- Endpoint baru: `GET api/station/receiver-options?articleWorkflowId=&bundleId=`
  → `SIS_Station_ReceiverOptions`. `[RequireStationToken]`.
- `EffectiveResourceId` **tidak berubah**: stasiun terkunci tetap dipaksa ke
  `default_resource_id`.

## 6. Client

### Halaman master Resource

- Form: dropdown **"Counterpart (Divisi Berikutnya)"**, opsional, `SearchableSelect`
  berisi resource hidup **di luar divisi yang sedang dipilih**; dikosongkan otomatis
  bila divisi diganti.
- List: kolom "Counterpart" → `{Nama} ({Divisi})`, "-" bila kosong.

### `StationDevice.razor` — form kirim hasil (kartu scan)

- `ReceiverPickerRequired = 1` → tampilkan dropdown **"Diterima Oleh ({divisi
  tujuan})"**, isi dari `receiver-options`, **wajib** (tombol simpan disabled selama
  kosong, pesan 'Penerima wajib dipilih.'). Pilihan **tidak** disimpan sebagai
  counterpart dan **tidak** sticky antar bundle — sekali pakai per pengiriman.
- `NextAutoReceive = 1` dan counterpart ada → **tidak ada dropdown**. Tampilkan teks
  informatif saja: "Otomatis diterima oleh {NextCounterpartResourceName}". Tidak bisa
  ditimpa.
- `NextAutoReceive = 0` → tidak ada dropdown maupun teks; alur serah terima manual
  seperti sekarang.

### `StationDevice.razor` — auto-login operator saat scan

- Stasiun **tidak terkunci** (`AllowResourceChange = 1`): bila `SuggestedResourceId`
  terisi dan berbeda dari operator sesi → set operator sesi ke resource itu, **sticky**
  (simpan ke localStorage seperti pemilihan manual, bertahan sampai scan bundle lain
  atau diganti manual). Badge kecil di kartu scan: **"Operator otomatis: {nama}"**.
  Tombol "Ganti Operator" tetap ada dan menang atas saran.
- `SuggestedResourceId` NULL → pertahankan operator sesi, jangan dikosongkan.
- Stasiun **terkunci**: operator tidak pernah berubah. Bila `SuggestedResourceId`
  terisi dan **berbeda** dari `DefaultResourceId` stasiun → lihat §7.

### Tab "Menunggu Diterima"

- Kartu menampilkan penerima yang akan dicatat: `SuggestedReceiverResourceName` bila
  ada, selain itu operator sesi aktif.
- Terima borongan: tiap baris memakai penerima default masing-masing, bukan satu
  operator untuk semua.
- Operator sesi yang diganti manual menang atas default.

## 7. Penerima mengikat pelaksana

Aturan inti: **bila sebuah bundle sudah diterima Trim A1 di divisi ini, hanya Trim A1
yang boleh mengirim hasilnya.** Berlaku universal — stasiun terkunci maupun tidak,
operator sesi hasil auto-login maupun dipilih manual.

**Penegakan di `SIS_WorkflowLog_Manage` CREATE (wajib, bukan sekadar UI):** bila baris
masuk bundle ini di divisi pencatat sudah punya `received_by_resource_id` terisi dan
berbeda dari `@ResourceId` → tolak dengan
'Bundle ini atas nama {NamaPenerima}. Batalkan penerimaan dulu bila salah orang.'

**Di `SIS_Bundle_ScanInfo`:** kondisi yang sama menghasilkan aksi `NONE` dengan pesan
tersebut, sehingga kartu scan tidak menampilkan tombol aksi sama sekali.

Konsekuensi per jenis stasiun:

- **Tidak terkunci** → auto-login (§6) sudah menyetel operator sesi ke Trim A1, jadi
  aksi berjalan normal. Penolakan hanya terjadi bila operator sengaja menggantinya ke
  resource lain.
- **Terkunci ke Trim A1** → normal.
- **Terkunci ke resource lain** → selalu ditolak. Perangkat itu memang bukan miliknya.

Jalan keluar bila salah orang: divisi penerima membatalkan penerimaan lewat UNRECEIVE
(Prompt 15) selama belum ada hasil di step berikutnya, lalu diterima ulang oleh resource
yang benar. Kalimat kedua di pesan error sudah mengarahkan ke sana.

Penegakan ini **hanya** berlaku untuk `SuggestedResourceSource = PENERIMA` — bukan
`LINE_BUNDLE`, `COUNTERPART`, atau `RIWAYAT` — karena hanya penerima yang berarti
"sudah ada yang memegang pertanggungjawaban". Saran dari sumber lain tetap sekadar
saran dan boleh ditimpa operator.

## 8. Perbaikan data lama — `sql/repair_40_received_by.sql`

Baris yang sudah terlanjur auto-receive dengan aturan Prompt 34 punya
`received_by_resource_id` berisi resource pengirim. Setelah §7 aktif, baris-baris itu
**buntu permanen**: penerimanya resource divisi lain, jadi tidak ada operator di divisi
tujuan yang bisa memenuhi syarat kirim hasil.

Skrip ini sudah dibuat (lampiran terpisah). Ringkasnya:

- **Penanda baris bermasalah:** divisi dari `received_by_resource_id` `<>`
  `target_division_id`. Struktural, tidak bergantung isi `received_remark`.
- **Prioritas perbaikan:** counterpart resource pengirim → resource tunggal di divisi
  tujuan → kalau tetap tidak bisa ditentukan, `received_at` dan
  `received_by_resource_id` dikosongkan sehingga baris kembali ke "Menunggu Diterima".
- `received_at` **tidak diubah** pada baris yang penerimanya berhasil dikoreksi —
  waktu terima historis tetap utuh agar laporan periode lama tidak bergeser.
- Berisi tiga bagian: pratinjau, eksekusi (dalam blok komentar, dibuka manual setelah
  pratinjau diperiksa), dan verifikasi yang harus mengembalikan 0 baris.
- Idempotent.

Jalankan **setelah** counterpart diisi (langkah 4 urutan deploy), supaya sebanyak
mungkin baris tertangani jalur counterpart dan bukan jatuh ke reset manual.

## Aturan tetap berlaku

Soft delete, filter `deleted_at IS NULL`, prefix SP `SIS_`, pola `@Action` untuk
mutasi, UI bahasa Indonesia, LEFT JOIN dengan filter deleted di ON clause, SQL
dijalankan manual.

## Yang TIDAK boleh dilakukan

- Jangan buat tabel mapping counterpart terpisah — cukup satu kolom di `resources`.
- Jangan pernah lagi mengisi `received_by_resource_id` dengan resource pengirim.
- Jangan izinkan pemilihan manual menimpa counterpart yang valid.
- Jangan menyimpan pilihan manual operator menjadi `counterpart_resource_id` — master
  data hanya diubah admin.
- Jangan munculkan dropdown penerima saat `auto_receive = 0`.
- Jangan terapkan dropdown penerima maupun auto-login di `/workflow-input` (Hasil
  Cutting) — prompt ini khusus stasiun.
- Jangan terapkan auto-login operator pada stasiun terkunci.
- Jangan longgarkan aturan §7 jadi sekadar peringatan — penolakan wajib di SP, bukan
  hanya menyembunyikan tombol di UI.
- Jangan sentuh `employee_id` — auto-login hanya menyetel resource, bukan penjahit.
- Jangan ubah `RECEIVE` / `UNRECEIVE` / `UPDATE` / `CANCEL_HANDOVER` di luar
  penambahan kolom saran.

## Urutan deploy

1. `alter_40_resource_counterpart.sql`
2. `sp_Resource_Manage.sql`, `sp_Resource_Select.sql`, `sp_WorkflowLog_Manage.sql`,
   `sp_Station_Operations.sql`, `sp_Bundle_ScanInfo.sql`
3. Deploy API + Client
4. Isi counterpart lewat UI untuk resource yang sudah aktif auto-receive
5. Jalankan `repair_40_received_by.sql` — pratinjau dulu, periksa pemetaannya
   (Line A1 → Trim A1 dst), baru buka blok eksekusi
6. Langkah 4 boleh dilewati untuk resource yang belum aktif auto-receive — tanpa
   counterpart, operator tinggal memilih penerima di form. Tapi lakukan sebelum jam
   produksi supaya operator tidak kaget ada dropdown wajib yang tiba-tiba muncul.

## Verifikasi

1. `dotnet build` sukses.
2. Skenario manual:
   - Line Sewing A punya counterpart Trim A1 → kirim hasil: tidak ada dropdown, teks
     "Otomatis diterima oleh Trim A1", `received_by_resource_id` = Trim A1.
   - Line Sewing B tanpa counterpart → dropdown penerima muncul dan wajib; simpan
     tanpa memilih ditolak SP.
   - Counterpart di-nonaktifkan (`is_active = 0`) → dropdown muncul lagi.
   - Step tujuan `auto_receive = 0` → tidak ada dropdown, alur manual utuh.
   - Counterpart dipasang ke resource satu divisi → ditolak SP.
   - Stasiun Trim tidak terkunci, scan bundle yang diterima Trim A1 → operator sesi
     otomatis jadi Trim A1, badge tampil.
   - Stasiun Trim terkunci ke Trim A2, scan bundle yang diterima Trim A1 → aksi
     ditolak dengan pesan §7; dicoba paksa lewat API pun tetap ditolak SP.
   - Stasiun terkunci ke Trim A1, scan bundle yang diterima Trim A1 → normal.
   - Stasiun tidak terkunci, scan bundle yang diterima Trim A1 lalu operator diganti
     manual ke Trim A5 → kirim hasil ditolak dengan pesan yang sama.
   - Setelah UNRECEIVE lalu diterima ulang Trim A5 → Trim A5 bisa kirim hasil.
   - Bundle tanpa jejak apa pun di divisi ini → operator sesi tidak berubah.
   - Laporan produksi (Prompt 30) menampilkan hasil Buang Benang atas nama resource
     Buang Benang, bukan line Sewing.
3. Di akhir: daftar file dibuat/diubah + daftar script SQL yang harus dijalankan manual.
