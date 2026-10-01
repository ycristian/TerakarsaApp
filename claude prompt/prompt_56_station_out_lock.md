# Prompt 56 — Lock & Request Unlock di Tab OUT Stasiun

## Prasyarat

Prompt 55 selesai dan semua script SQL-nya sudah dijalankan (tabel lock, periode gajian,
`SIS_WorkflowLock_Manage`, `SIS_UnlockRequest_Manage`, guard `LOCKED|`).

## Konteks

Tab OUT di stasiun (`StationDevice.razor`) sudah menampilkan hasil per artikel per
tanggal kirim: kartu artikel (Bundle · Qty · Reject), bisa dibuka untuk melihat baris per
line + penjahit, dengan tombol print/edit/hapus per baris. Baca dulu implementasi tab OUT
yang ada sekarang — prompt ini MENAMBAH lock di atasnya, bukan membangun ulang.

Tujuan: PIC mengunci (lock) hasil kerjanya sendiri setelah dicocokkan dengan kondisi
lapangan, dan menentukan hasil itu masuk periode gajian mana. Baris yang sudah di-lock
hanya bisa dibuka lewat pengajuan unlock yang disetujui admin (halaman admin di Prompt 57).

## 1. Baris non-bundle ikut tab OUT

Baris step non-bundle (`bundle_id IS NULL`, mis. Cutting) tampil di kartu artikel yang
sama dengan pola yang sama. Bedanya hanya:
- tidak ada nomor bundle — kolom pertama menampilkan **size**;
- **tidak ada tombol print**;
- edit, hapus, checkbox, dan ikon lock tetap ada;
- aturan edit/hapus sama persis dengan baris bundle (belum lock + saldo tidak minus,
  ditegakkan SP dari Prompt 55).
Kalau tab OUT sekarang belum memuat baris non-bundle, tambahkan ke SP read-nya.

## 2. SP read (di `sql/sp_Station_Operations.sql` atau file SP OUT yang dipakai sekarang)

a. **SP daftar OUT** yang sudah dipakai tab ini: tambah kolom per baris
   `LockId`, `IsLocked` (bit), `HasPendingUnlock` (bit — baris ada di request yang masih
   menunggu). Hapus filter/kolom yang masih berbasis jendela 1 jam / H+1 / "sudah
   diterima" untuk menentukan boleh edit/hapus — sekarang: `CanEdit = CanDelete =
   (IsLocked = 0)`. Validasi saldo tetap di SP tulis, UI tidak menghitungnya.

b. **`SIS_Station_UnlockedDates`** (@DivisionId): tanggal (basis tanggal yang sama dengan
   filter "Tanggal Kirim") yang masih punya baris hidup divisi ini dengan `lock_id IS NULL`,
   plus jumlah barisnya. Urut tanggal naik. Dipakai chip pengingat.

c. **`SIS_Station_Counts`**: tambah `OutUnlockedCount` (baris OUT divisi ini yang belum
   lock, semua tanggal).

d. **`SIS_PayrollPeriod_Options`** (@DefaultAt datetime2): periode hidup,
   `finalized_at IS NULL`, dari periode sebelum periode `@DefaultAt` sampai satu periode
   setelah periode berjalan. Kolom: `PayrollPeriodId`, `PeriodCode`, `PeriodStart`,
   `PeriodEnd`, `IsDefault` (periode yang memuat `@DefaultAt`).

e. **`SIS_Bundle_ScanInfo`**: guard H+1 dan jendela 1 jam untuk menawarkan tombol
   Edit/Hapus diganti `lock_id IS NULL`.

## 3. API (`StationDeviceController`, X-Station-Token)

- GET `api/station/out/unlocked-dates` → 2b.
- GET `api/station/payroll-periods?defaultAt=` → 2d.
- POST `api/station/locks` body `{ workflowLogIds: int[], payrollPeriodId, resourceId }`
  → `SIS_WorkflowLock_Manage LOCK`. `@DivisionId`/`@StationId` dari token, `@UserId`
  user sistem station.
- POST `api/station/unlock-requests` body `{ workflowLogIds: int[], reason, resourceId }`
  → `SIS_UnlockRequest_Manage CREATE`.
- Pesan error SP diteruskan apa adanya. Error berprefix `LOCKED|` → client menampilkan
  bagian setelah `|` lalu memuat ulang daftar.

## 4. UI tab OUT

### a. Baris filter
`Tanggal Kirim [date]   ☑ Penjahit   [ Lock | Unlock ]`
- **Segmented toggle Lock/Unlock** sejajar checkbox Penjahit. Default **Lock**.
- Di bawahnya, **chip merah tanggal belum lock** dari 2b: `Belum lock: 27/09 (3) · 28/09 (5)`.
  Tap chip → filter tanggal pindah ke tanggal itu. Tanggal yang sedang dipilih tidak
  perlu dijadikan chip. Kalau lebih dari 6 tanggal, tampilkan 6 terlama + "+n lagi".
  Tidak ada chip = semua beres, jangan tampilkan apa pun.

### b. Kartu artikel
- Sejajar Bundle · Qty · Reject tambahkan kolom keempat status lock:
  - masih ada baris belum lock → ikon `bi-unlock` + angka jumlahnya, **merah**;
  - semua sudah lock → ikon `bi-lock-fill` **hijau**.
- **Urutan kartu**: kartu yang masih punya baris belum lock di atas; kartu yang sudah
  lock semua di bawah dan tampil pudar (opacity ± 0.6). Urutan dalam kelompok mengikuti
  urutan yang sekarang.
- **Checkbox "pilih semua" di header kartu** (bisa dipakai tanpa membuka kartu): memilih
  semua baris kartu itu yang bisa dipilih pada mode aktif. Tidak muncul kalau kartu tidak
  punya baris yang bisa dipilih pada mode itu.

### c. Baris dalam kartu
- **Belum lock**: tombol print (bundle saja) / edit / hapus seperti sekarang.
- **Sudah lock**: tombol edit & hapus **hilang**, diganti ikon `bi-lock-fill` **hijau** di
  posisi yang sama. Tombol print tetap (bundle saja).
- **Menunggu approval unlock**: ikon jam pasir kuning (`bi-hourglass-split`) +
  teks kecil "menunggu approval". Tidak bisa dipilih di mode mana pun.
- **Checkbox per baris** muncul sesuai mode:
  - mode **Lock** → hanya di baris belum lock;
  - mode **Unlock** → hanya di baris sudah lock yang tidak sedang menunggu approval.
- Tap di area baris (selain tombol aksi) juga mencentang/menghapus centang; baris
  terpilih diberi latar biru muda.

### d. Bar aksi bawah
- Muncul hanya saat tab OUT aktif. `position: sticky; bottom: 0` di dalam wadah tab
  (jangan `fixed` — halaman stasiun bisa berada di panel). Tambah
  `padding-bottom: env(safe-area-inset-bottom)` dan ruang bawah di daftar supaya kartu
  terakhir tidak tertutup.
- Isi kiri: `n baris · x pcs · reject y` (dari baris terpilih).
- Satu tombol sesuai mode:
  - mode Lock → **LOCK (n)**, warna netral/primer;
  - mode Unlock → **AJUKAN UNLOCK (n)**, bar berlatar kuning muda.
- Tombol nonaktif kalau belum ada yang dipilih.

### e. Modal konfirmasi LOCK
- Ringkasan per artikel dari baris terpilih: artikel, jumlah baris, pcs, reject.
- Dropdown **Periode Gajian** dari 2d, `defaultAt` = `created_at` terbaru di antara baris
  terpilih; tampilkan kode + rentang (mis. `2026-P40 · 26 Sep 10:00 – 3 Okt 10:00`).
- Kalau baris terpilih berasal dari lebih dari satu periode default, tampilkan peringatan
  kuning: "Baris yang dipilih berasal dari dua periode. Semua akan masuk periode yang
  dipilih. Lock terpisah kalau perlu dibagi."
- Operator = operator sesi aktif (tampilkan namanya, tidak bisa diganti di modal).
- Tombol: **"Ya, data sudah sesuai — Lock"** dan "Batal".

### f. Modal AJUKAN UNLOCK
- Daftar baris terpilih (artikel, bundle/size, qty, periode lock-nya).
- Textarea **alasan** wajib (min 5 karakter).
- Tombol **"Ajukan"** (bukan "Unlock") + teks kecil "Baris baru bisa diedit setelah
  disetujui admin."

### g. Kotak OUT di header
Di bawah angka OUT tambahkan teks kecil merah `n belum lock` dari `OutUnlockedCount`;
sembunyikan kalau 0.

### h. State pilihan
Kosongkan pilihan saat: mode diganti, tanggal diganti, pindah tab, dan setelah lock/ajukan
berhasil. Setelah berhasil: toast singkat ("7 baris di-lock ke 2026-P40" /
"Pengajuan unlock terkirim"), muat ulang daftar, chip, dan counts.

## Yang TIDAK boleh dilakukan

- Jangan ubah SP tulis dari Prompt 55 (`SIS_WorkflowLock_Manage`,
  `SIS_UnlockRequest_Manage`, guard di `SIS_WorkflowLog_Manage`/`SIS_Bundle_Manage`).
- Jangan tambah lock di tab IN — penerimaan tidak dikunci.
- Jangan ubah tab Settlement (dipakai untuk print kartu kerja).
- Jangan buat halaman admin approval (Prompt 57).
- Jangan hitung saldo di client — cukup tampilkan pesan error dari SP.

Setelah selesai: daftar file dibuat/diubah + script SQL yang harus dijalankan manual,
masing-masing sebagai markdown link.
