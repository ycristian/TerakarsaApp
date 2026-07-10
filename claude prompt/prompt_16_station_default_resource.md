# Prompt 16 — Default Resource per Stasiun (1 Device = 1 Resource)

## Prasyarat

Setelah Prompt 15. Perubahan kecil, tidak menyentuh SP log.

## Konteks

Asumsi operasional: satu perangkat stasiun dipakai satu resource. Operator tidak
perlu memilih nama tiap sesi — stasiun membawa resource bawaannya. Tetap bisa
diganti di layar untuk kasus darurat (device dipinjam, operator digantikan).

## 1. Skema

- `sql/alter_16_station_default_resource.sql` (idempotent):
  ALTER TABLE stations ADD
  - default_resource_id int null
    + FK `FK_stations_default_resource` → resources(resource_id)
  - allow_resource_change bit not null default 1
    (1 = operator boleh ganti resource di layar; 0 = terkunci ke resource bawaan).
- Perbarui `sql/create_tables_tmos_final.sql`.
- Validasi di SP manage stasiun:
  - default_resource_id (bila diisi) harus resource hidup milik division_id
    stasiun tsb ('Resource bukan milik divisi stasiun ini.').
  - allow_resource_change = 0 mengharuskan default_resource_id terisi
    ('Stasiun terkunci wajib punya resource bawaan.').
  - Bila division_id stasiun diubah dan default_resource_id tidak lagi sesuai
    divisinya: kosongkan default_resource_id dan set allow_resource_change = 1.

## 2. Admin — halaman kelola stasiun

- Form tambah/edit stasiun: dropdown "Resource Bawaan (opsional)"
  (SearchableSelect, terisi resource divisi terpilih) + checkbox
  "Kunci ke resource bawaan" (hanya aktif bila resource bawaan dipilih).
- Kolom daftar stasiun: nama resource bawaan ("-" bila kosong) + ikon gembok
  bila terkunci.

## 3. Halaman stasiun (StationDevice)

- Endpoint info stasiun (validasi token) menyertakan DefaultResourceId,
  DefaultResourceName, AllowResourceChange.
- Tiga mode saat halaman dibuka:
  1. DefaultResourceId NULL → perilaku sekarang (wajib pilih operator).
  2. Terisi + AllowResourceChange = 1 → operator otomatis terpilih, pemilih
     tetap tampil (ganti berlaku sesi itu saja, tidak mengubah bawaan).
  3. Terisi + AllowResourceChange = 0 → operator otomatis terpilih dan pemilih
     disembunyikan; tampilkan nama resource sebagai teks + ikon gembok.
- Penegakan sisi server (jangan hanya UI): pada semua endpoint stasiun yang
  menerima resourceId, bila stasiun terkunci → resourceId dari request diabaikan
  dan dipaksa = default_resource_id stasiun.
- Selain paksaan pada mode terkunci, cara resource_id dikirim ke API tidak berubah.

## Yang TIDAK boleh dilakukan

- Jangan jadikan default_resource_id wajib untuk semua stasiun — hanya wajib
  bila allow_resource_change = 0.
- Jangan sembunyikan pemilih operator pada stasiun yang tidak terkunci.
- Jangan ubah SIS_WorkflowLog_Manage atau alur log/receive/unreceive.

Setelah selesai: daftar file dibuat/diubah + script SQL manual.
