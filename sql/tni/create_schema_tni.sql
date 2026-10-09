/* =============================================================
   TMOS - Module PDH TNI AD (Prompt 60-69) - Skema `tni`
   FILE CANONICAL untuk seluruh tabel schema tni. Tabel schema dbo
   TIDAK disentuh dari file ini (sql/create_tables_tmos_final.sql
   tetap canonical untuk dbo).

   Aturan penulisan mengikuti sql/create_tables_tmos_final.sql:
   1. snake_case; varchar (bukan nvarchar) kecuali raw_json
   2. varchar spesifik: code(30), name(150), status(20),
      alasan/remarks(500), keterangan(255)
   3. Kolom wajib bisnis = NOT NULL (name, code, FK utama)
   4. Semua FK diberi nama (FK_anak_induk) agar mudah di-ALTER
   5. Kode unik via filtered unique index WHERE deleted_at IS NULL
      (kode bisa dipakai ulang setelah baris lama di-soft-delete)
   6. created_by/updated_by/deleted_by: int tanpa FK -- sama dengan
      tabel dbo (lihat aturan 9 di file canonical dbo)
   7. Tidak ada kolom status maupun tabel saldo: status personel
      diturunkan di tni.v_personel, saldo stok = SUM(qty) mutasi

   Idempotent: tiap objek dibungkus IF ... IS NULL / NOT EXISTS.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'tni')
    EXEC('CREATE SCHEMA tni');
GO

-- ============ 1. MASTER ORDER & WILAYAH ============

-- Satu baris per order PDH. Semua halaman module bekerja pada baris is_active = 1.
IF OBJECT_ID('tni.orders','U') IS NULL
CREATE TABLE tni.orders(
 order_id int primary key identity(1,1),
 order_code varchar(30) not null,
 order_name varchar(150) not null,
 instansi varchar(150) null,
 tahun int not null,
 target_qty int not null default 0,
 project_id int null                        -- opsional: kaitkan ke project TMOS (dbo)
   constraint FK_tni_orders_projects foreign key references dbo.projects(project_id),
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Area rawatan = gudang/pangkalan penerima. area_code ikut jadi awalan kode box (BDG-...).
IF OBJECT_ID('tni.area_rawatan','U') IS NULL
CREATE TABLE tni.area_rawatan(
 area_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_area_rawatan_orders foreign key references tni.orders(order_id),
 area_code varchar(10) not null,            -- dipakai di kode box: BDG
 area_name varchar(150) not null,           -- ejaan PERSIS data mentah form (dipakai mencocokkan import)
 kota varchar(100) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Satuan (kesatuan) pemilik personel. satuan_code ikut jadi awalan kode personel
-- (DTJ-001) dan bagian tengah kode box (BDG-DTJ-01) -- jangan diubah setelah ada personel.
-- satuan_code HARUS unik dalam satu order; filtered index tidak bisa lintas tabel,
-- jadi keunikan lintas-area ditegakkan di SP/seed. Di sini unik per (area_id, satuan_code).
IF OBJECT_ID('tni.satuan','U') IS NULL
CREATE TABLE tni.satuan(
 satuan_id int primary key identity(1,1),
 area_id int not null
   constraint FK_tni_satuan_area_rawatan foreign key references tni.area_rawatan(area_id),
 satuan_code varchar(10) not null,
 satuan_name varchar(150) not null,         -- ejaan PERSIS data mentah form
 kelompok varchar(50) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 2. MASTER POLA ============

-- Pola kemeja = ukuran JADI pakaian (bukan ukuran badan personel).
-- target_gender: P  Pria . PG  Pria Gemuk . W  Wanita non-hijab
--                WH Wanita hijab (lengan panjang + manset) . W_PG / WH_PG versi gemuk.
-- lingkar_manset hanya terisi untuk pola hijab (WH / WH_PG).
IF OBJECT_ID('tni.pola_kemeja','U') IS NULL
CREATE TABLE tni.pola_kemeja(
 pola_kemeja_id int primary key identity(1,1),
 kode varchar(30) not null,                 -- LD_102_P
 kode_alt varchar(30) null,                 -- kode lama dari size pack, mis. 14,5-3
 target_gender varchar(10) not null
   constraint CK_tni_pola_kemeja_gender check (target_gender in ('P','PG','W','W_PG','WH','WH_PG')),
 lingkar_dada_acuan decimal(5,1) not null,  -- angka acuan grading (LD pada kode)
 lingkar_kerah decimal(5,1) null,
 lebar_bahu decimal(5,1) null,
 lingkar_dada decimal(5,1) null,
 lingkar_perut decimal(5,1) null,
 lingkar_pinggul decimal(5,1) null,
 panjang_baju decimal(5,1) null,
 lingkar_lengan decimal(5,1) null,
 lingkar_kerung_lengan decimal(5,1) null,
 panjang_lengan decimal(5,1) null,
 lingkar_manset decimal(5,1) null,          -- hijab saja
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Pola celana = ukuran JADI celana. target_gender hanya P / W.
IF OBJECT_ID('tni.pola_celana','U') IS NULL
CREATE TABLE tni.pola_celana(
 pola_celana_id int primary key identity(1,1),
 kode varchar(30) not null,                 -- 32_P
 target_gender varchar(10) not null
   constraint CK_tni_pola_celana_gender check (target_gender in ('P','W')),
 size_angka int not null,                   -- angka size pada kode
 lingkar_pinggang decimal(5,1) null,
 lingkar_pinggul decimal(5,1) null,
 lingkar_selangkang decimal(5,1) null,
 lingkar_paha decimal(5,1) null,
 lingkar_lutut decimal(5,1) null,
 lingkar_kaki decimal(5,1) null,
 panjang_celana decimal(5,1) null,
 is_active bit not null default 1,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 3. BOX ============

-- Dibuat SEBELUM tni.personel karena personel.box_id menunjuk ke sini.
-- TIDAK ADA KOLOM STATUS: Terbuka / Tertutup / Terkirim diturunkan dari
-- packed_at dan shipped_at. Nomor box tidak pernah diganti atau didaur ulang.
IF OBJECT_ID('tni.box','U') IS NULL
CREATE TABLE tni.box(
 box_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_box_orders foreign key references tni.orders(order_id),
 area_id int not null                       -- selalu ada
   constraint FK_tni_box_area_rawatan foreign key references tni.area_rawatan(area_id),
 satuan_id int null                         -- NULL = box GABUNGAN lintas satuan dalam satu area
   constraint FK_tni_box_satuan foreign key references tni.satuan(satuan_id),
 urut int not null,                         -- urut dalam pemiliknya (per satuan; per area untuk gabungan)
 box_code varchar(30) not null,             -- BDG-DTJ-01, gabungan BDG-GAB-01
 kapasitas int not null default 50,
 packed_at datetime2 null,                  -- box ditutup
 packed_by int null,
 shipped_at datetime2 null,                 -- box terkirim
 shipped_by int null,
 keterangan varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 4. PERSONEL ============

-- Satu baris per orang; tiap orang dapat tepat 1 kemeja + 1 celana.
-- Ukuran badan WAJIB NULLABLE: +-1/3 personel (kategori TU_SIZING) tidak hadir
-- pengukuran, acuan potong murni dari pola.
-- qr_token: QR di kartu berisi <QrBaseUrl>/t/<qr_token>, BUKAN kode_ref -- kode_ref
-- berurutan sehingga mudah ditebak, padahal halaman QR bisa dibuka dari internet.
-- Unique index qr_token TANPA filter deleted_at (token tidak boleh didaur ulang).
IF OBJECT_ID('tni.personel','U') IS NULL
CREATE TABLE tni.personel(
 personel_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_personel_orders foreign key references tni.orders(order_id),
 satuan_id int not null
   constraint FK_tni_personel_satuan foreign key references tni.satuan(satuan_id),
 kode_ref varchar(30) not null,             -- <satuan_code>-<no_urut 3 digit>, mis. DTJ-001
 no_urut int not null,                      -- urutan dalam satuan
 qr_token varchar(16) not null,             -- acak 10 karakter, tidak pernah berubah
 pangkat varchar(50) null,
 nama varchar(150) not null,
 nrp varchar(30) not null,
 no_hp varchar(30) null,
 gender varchar(20) not null
   constraint CK_tni_personel_gender check (gender in ('PRIA','WANITA_HIJAB','WANITA_NON_HIJAB')),
 tinggi_badan int null,
 berat_badan int null,
 kategori varchar(20) not null default 'UKUR'
   constraint CK_tni_personel_kategori check (kategori in ('UKUR','TU_SIZING')),
 pola_kemeja_id int not null
   constraint FK_tni_personel_pola_kemeja foreign key references tni.pola_kemeja(pola_kemeja_id),
 pola_celana_id int not null
   constraint FK_tni_personel_pola_celana foreign key references tni.pola_celana(pola_celana_id),
 size_baju_isian varchar(30) null,          -- isian mentah form, arsip
 size_celana_isian varchar(30) null,        -- isian mentah form, arsip
 email_pengisi varchar(150) null,           -- email PENGISI form, bukan email personel
 submitted_at datetime2 null,               -- timestamp isian form
 -- 8 ukuran badan kemeja
 lingkar_leher decimal(5,1) null,
 lebar_bahu decimal(5,1) null,
 lingkar_dada decimal(5,1) null,
 lingkar_perut decimal(5,1) null,
 panjang_badan_depan decimal(5,1) null,
 panjang_lengan decimal(5,1) null,
 lingkar_lengan decimal(5,1) null,
 lingkar_ketiak decimal(5,1) null,
 -- 7 ukuran badan celana
 lingkar_pinggang_celana decimal(5,1) null,
 lingkar_pinggul decimal(5,1) null,
 lingkar_pesak decimal(5,1) null,
 lingkar_paha decimal(5,1) null,
 lingkar_lutut decimal(5,1) null,
 lingkar_celana_bawah decimal(5,1) null,
 panjang_celana decimal(5,1) null,
 status_data varchar(20) not null default 'OK'
   constraint CK_tni_personel_status_data check (status_data in ('OK','PERLU_REVIEW','DIPERBAIKI')),
 catatan_review varchar(500) null,
 printed_at datetime2 null,                 -- kartu terakhir dicetak
 printed_by int null,
 print_count int not null default 0,
 set_at datetime2 null,                     -- scan Set Jadi
 set_by int null,
 boxed_at datetime2 null,                   -- scan Masuk Box
 boxed_by int null,
 box_id int null
   constraint FK_tni_personel_box foreign key references tni.box(box_id),
 urut_dalam_box int null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 5. STOK ============

-- BUKU BESAR stok, plus-minus. TIDAK ADA TABEL SALDO -- saldo selalu SUM(qty).
-- Stok bersifat ANONIM per pola: kemeja LD_102_P mana pun boleh dipakai siapa pun
-- yang polanya sama. TERPAKAI dibuat otomatis oleh scan Set Jadi (Prompt 66),
-- BONGKAR oleh persetujuan pembatalan (Prompt 68) -- keduanya tidak diinput manual.
IF OBJECT_ID('tni.stok_mutasi','U') IS NULL
CREATE TABLE tni.stok_mutasi(
 mutasi_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_stok_mutasi_orders foreign key references tni.orders(order_id),
 jenis_item varchar(10) not null
   constraint CK_tni_stok_mutasi_jenis_item check (jenis_item in ('KEMEJA','CELANA')),
 pola_kemeja_id int null
   constraint FK_tni_stok_mutasi_pola_kemeja foreign key references tni.pola_kemeja(pola_kemeja_id),
 pola_celana_id int null
   constraint FK_tni_stok_mutasi_pola_celana foreign key references tni.pola_celana(pola_celana_id),
 jenis_mutasi varchar(20) not null
   constraint CK_tni_stok_mutasi_jenis_mutasi check (jenis_mutasi in ('MASUK','TERPAKAI','RUSAK','BONGKAR','KOREKSI')),
 qty int not null,                          -- positif menambah, negatif mengurangi
 alasan varchar(500) null,
 personel_id int null                       -- terisi untuk TERPAKAI & BONGKAR
   constraint FK_tni_stok_mutasi_personel foreign key references tni.personel(personel_id),
 tanggal date not null default cast(sysdatetime() as date),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 -- Tepat satu kolom pola terisi, dan cocok dengan jenis_item
 constraint CK_tni_stok_mutasi_pola_sesuai check (
      (jenis_item = 'KEMEJA' AND pola_kemeja_id IS NOT NULL AND pola_celana_id IS NULL)
   OR (jenis_item = 'CELANA' AND pola_celana_id IS NOT NULL AND pola_kemeja_id IS NULL)
 ),
 constraint CK_tni_stok_mutasi_qty_nonzero check (qty <> 0),
 -- Pengurangan selain TERPAKAI wajib beralasan
 constraint CK_tni_stok_mutasi_alasan check (
   NOT (qty < 0 AND jenis_mutasi <> 'TERPAKAI' AND (alasan IS NULL OR LTRIM(RTRIM(alasan)) = ''))
 )
);
GO

-- ============ 6. PEMBATALAN SCAN ============

-- Scan tidak bisa dihapus langsung: staff mengajukan, pemegang module
-- TNI_PDH_APPROVE memutuskan (Prompt 68). created_by = pengaju.
IF OBJECT_ID('tni.pembatalan','U') IS NULL
CREATE TABLE tni.pembatalan(
 pembatalan_id int primary key identity(1,1),
 personel_id int not null
   constraint FK_tni_pembatalan_personel foreign key references tni.personel(personel_id),
 jenis varchar(10) not null
   constraint CK_tni_pembatalan_jenis check (jenis in ('SET','BOX')),
 alasan varchar(500) not null,
 [status] varchar(20) not null default 'MENUNGGU'
   constraint CK_tni_pembatalan_status check ([status] in ('MENUNGGU','DISETUJUI','DITOLAK')),
 box_id_asal int null                       -- box tempat personel sebelum dibatalkan
   constraint FK_tni_pembatalan_box foreign key references tni.box(box_id),
 diputus_oleh int null,
 diputus_at datetime2 null,
 catatan_keputusan varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- ============ 7. IMPORT ============

-- Satu baris per unggahan file Excel export Google Form (Prompt 62).
IF OBJECT_ID('tni.import_batch','U') IS NULL
CREATE TABLE tni.import_batch(
 batch_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_import_batch_orders foreign key references tni.orders(order_id),
 nama_file varchar(255) not null,
 jumlah_baris int not null default 0,
 jumlah_baru int not null default 0,
 jumlah_diperbarui int not null default 0,
 jumlah_review int not null default 0,
 jumlah_ditolak int not null default 0,
 committed_at datetime2 null,
 committed_by int null,
 catatan varchar(500) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Staging per baris Excel. raw_json = objek baris apa adanya (satu-satunya nvarchar
-- di schema ini: isinya teks bebas dari form). Tabel log: hanya created_at/created_by.
IF OBJECT_ID('tni.import_staging','U') IS NULL
CREATE TABLE tni.import_staging(
 staging_id int primary key identity(1,1),
 batch_id int not null
   constraint FK_tni_import_staging_batch foreign key references tni.import_batch(batch_id),
 baris_ke int not null,                     -- nomor baris di file Excel
 nrp varchar(30) null,
 nama varchar(150) null,
 raw_json nvarchar(max) not null,
 hasil_validasi varchar(20) not null
   constraint CK_tni_import_staging_hasil check (hasil_validasi in ('VALID','REVIEW','TOLAK')),
 aksi varchar(20) null
   constraint CK_tni_import_staging_aksi check (aksi in ('BARU','PERBARUI')),
 pesan_error varchar(1000) null,
 personel_id int null
   constraint FK_tni_import_staging_personel foreign key references tni.personel(personel_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null
);
GO

/* ============ 8. INDEX ============
   Kode unik via filtered unique index WHERE deleted_at IS NULL, kecuali
   UX_tni_personel_qr_token (token tidak boleh didaur ulang -- tanpa filter). */

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_orders_code' AND object_id = OBJECT_ID('tni.orders'))
    CREATE UNIQUE INDEX UX_tni_orders_code        ON tni.orders(order_code)                    WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_area_code' AND object_id = OBJECT_ID('tni.area_rawatan'))
    CREATE UNIQUE INDEX UX_tni_area_code          ON tni.area_rawatan(order_id, area_code)     WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_area_name' AND object_id = OBJECT_ID('tni.area_rawatan'))
    CREATE UNIQUE INDEX UX_tni_area_name          ON tni.area_rawatan(order_id, area_name)     WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_satuan_name' AND object_id = OBJECT_ID('tni.satuan'))
    CREATE UNIQUE INDEX UX_tni_satuan_name        ON tni.satuan(area_id, satuan_name)          WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_satuan_code' AND object_id = OBJECT_ID('tni.satuan'))
    CREATE UNIQUE INDEX UX_tni_satuan_code        ON tni.satuan(area_id, satuan_code)          WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_pola_kemeja_kode' AND object_id = OBJECT_ID('tni.pola_kemeja'))
    CREATE UNIQUE INDEX UX_tni_pola_kemeja_kode   ON tni.pola_kemeja(kode)                     WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_pola_celana_kode' AND object_id = OBJECT_ID('tni.pola_celana'))
    CREATE UNIQUE INDEX UX_tni_pola_celana_kode   ON tni.pola_celana(kode)                     WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_box_code' AND object_id = OBJECT_ID('tni.box'))
    CREATE UNIQUE INDEX UX_tni_box_code           ON tni.box(order_id, box_code)               WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_personel_nrp' AND object_id = OBJECT_ID('tni.personel'))
    CREATE UNIQUE INDEX UX_tni_personel_nrp       ON tni.personel(order_id, nrp)               WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_personel_kode_ref' AND object_id = OBJECT_ID('tni.personel'))
    CREATE UNIQUE INDEX UX_tni_personel_kode_ref  ON tni.personel(order_id, kode_ref)          WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_personel_qr_token' AND object_id = OBJECT_ID('tni.personel'))
    CREATE UNIQUE INDEX UX_tni_personel_qr_token  ON tni.personel(qr_token);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_satuan_area' AND object_id = OBJECT_ID('tni.satuan'))
    CREATE INDEX IX_tni_satuan_area               ON tni.satuan(area_id)                       WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_personel_satuan' AND object_id = OBJECT_ID('tni.personel'))
    CREATE INDEX IX_tni_personel_satuan           ON tni.personel(order_id, satuan_id)         WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_personel_pola_kemeja' AND object_id = OBJECT_ID('tni.personel'))
    CREATE INDEX IX_tni_personel_pola_kemeja      ON tni.personel(pola_kemeja_id)              WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_personel_pola_celana' AND object_id = OBJECT_ID('tni.personel'))
    CREATE INDEX IX_tni_personel_pola_celana      ON tni.personel(pola_celana_id)              WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_personel_box' AND object_id = OBJECT_ID('tni.personel'))
    CREATE INDEX IX_tni_personel_box              ON tni.personel(box_id)                      WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_box_area_satuan' AND object_id = OBJECT_ID('tni.box'))
    CREATE INDEX IX_tni_box_area_satuan           ON tni.box(order_id, area_id, satuan_id)     WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_mutasi_kemeja' AND object_id = OBJECT_ID('tni.stok_mutasi'))
    CREATE INDEX IX_tni_stok_mutasi_kemeja        ON tni.stok_mutasi(order_id, pola_kemeja_id) WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_mutasi_celana' AND object_id = OBJECT_ID('tni.stok_mutasi'))
    CREATE INDEX IX_tni_stok_mutasi_celana        ON tni.stok_mutasi(order_id, pola_celana_id) WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_pembatalan_status' AND object_id = OBJECT_ID('tni.pembatalan'))
    CREATE INDEX IX_tni_pembatalan_status         ON tni.pembatalan([status])                  WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_import_staging_batch' AND object_id = OBJECT_ID('tni.import_staging'))
    CREATE INDEX IX_tni_import_staging_batch      ON tni.import_staging(batch_id);
GO

/* =============================================================
   PERANGKAT TANPA LOGIN (2026-10-02, struktur akhir 2026-10-06)

   Ditambahkan setelah seri 60-69 atas permintaan owner: modul /tni
   dipakai SEPERTI STASIUN -- masuk cukup kode pairing, tanpa login.

   Riwayat: alter_70 (perangkat + tabel petugas dipilih per sesi),
   alter_70b (petugas di-assign ke perangkat), alter_75 (tabel petugas
   DIHAPUS -- nama petugas kini kolom tni.perangkat.nama_petugas dan jejak
   kerja menyimpan *_perangkat_id). Blok ini = STRUKTUR AKHIR; untuk DB
   lama yang masih punya tni.petugas, migrasinya ada di alter_75.

   created_by SELALU user id (user sistem `tni_system`). PERANGKAT yang
   mengerjakan ada di kolom *_perangkat_id, dan nama yang tampil diambil
   dari perangkat.nama_petugas.
   ============================================================= */

IF OBJECT_ID('tni.perangkat','U') IS NULL
CREATE TABLE tni.perangkat(
 perangkat_id int primary key identity(1,1),
 perangkat_code varchar(30) not null,
 perangkat_name varchar(150) not null,
 nama_petugas varchar(150) not null,        -- SATU petugas per perangkat (alter_75)
 perangkat_token varchar(64) not null,      -- GUID tanpa strip, digenerate server
 is_active bit not null default 1,
 pairing_code varchar(10) null,
 pairing_code_expires_at datetime2 null,
 paired_at datetime2 null,
 last_seen_at datetime2 null,
 keterangan varchar(255) null,
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO

-- Jejak kerja: PERANGKAT yang mengerjakan. Semua nullable -- baris lama dan
-- aksi dari user login tidak punya perangkat.
IF COL_LENGTH('tni.personel','printed_perangkat_id') IS NULL
    ALTER TABLE tni.personel ADD printed_perangkat_id int null
        constraint FK_tni_personel_printed_perangkat foreign key references tni.perangkat(perangkat_id);
GO
IF COL_LENGTH('tni.personel','set_perangkat_id') IS NULL
    ALTER TABLE tni.personel ADD set_perangkat_id int null
        constraint FK_tni_personel_set_perangkat foreign key references tni.perangkat(perangkat_id);
GO
IF COL_LENGTH('tni.personel','boxed_perangkat_id') IS NULL
    ALTER TABLE tni.personel ADD boxed_perangkat_id int null
        constraint FK_tni_personel_boxed_perangkat foreign key references tni.perangkat(perangkat_id);
GO
IF COL_LENGTH('tni.box','packed_perangkat_id') IS NULL
    ALTER TABLE tni.box ADD packed_perangkat_id int null
        constraint FK_tni_box_packed_perangkat foreign key references tni.perangkat(perangkat_id);
GO
IF COL_LENGTH('tni.box','shipped_perangkat_id') IS NULL
    ALTER TABLE tni.box ADD shipped_perangkat_id int null
        constraint FK_tni_box_shipped_perangkat foreign key references tni.perangkat(perangkat_id);
GO
IF COL_LENGTH('tni.stok_mutasi','perangkat_id') IS NULL
    ALTER TABLE tni.stok_mutasi ADD perangkat_id int null
        constraint FK_tni_stok_mutasi_perangkat foreign key references tni.perangkat(perangkat_id);
GO
IF COL_LENGTH('tni.pembatalan','perangkat_id') IS NULL
    ALTER TABLE tni.pembatalan ADD perangkat_id int null
        constraint FK_tni_pembatalan_perangkat foreign key references tni.perangkat(perangkat_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_perangkat_code' AND object_id = OBJECT_ID('tni.perangkat'))
    CREATE UNIQUE INDEX UX_tni_perangkat_code   ON tni.perangkat(perangkat_code) WHERE deleted_at IS NULL;
GO
-- Token unik TANPA filter deleted_at: token perangkat terhapus tidak dipakai ulang.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_perangkat_token' AND object_id = OBJECT_ID('tni.perangkat'))
    CREATE UNIQUE INDEX UX_tni_perangkat_token  ON tni.perangkat(perangkat_token);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_perangkat_pairing' AND object_id = OBJECT_ID('tni.perangkat'))
    CREATE INDEX IX_tni_perangkat_pairing       ON tni.perangkat(pairing_code) WHERE pairing_code IS NOT NULL;
GO

-- 2026-10-06 (alter_71): komplain ukuran dari halaman QR /t/{token}, boleh
-- dikirim orang luar tanpa perangkat. created_by = user sistem tni_system.
IF OBJECT_ID('tni.komplain','U') IS NULL
CREATE TABLE tni.komplain(
 komplain_id int primary key identity(1,1),
 personel_id int not null foreign key references tni.personel(personel_id),
 no_telp varchar(30) not null,
 komentar nvarchar(2000) not null,
 perangkat_id int null           -- perangkat pengirim (alter_75); NULL = orang luar
   constraint FK_tni_komplain_perangkat foreign key references tni.perangkat(perangkat_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_komplain_personel' AND object_id = OBJECT_ID('tni.komplain'))
    CREATE INDEX IX_tni_komplain_personel ON tni.komplain(personel_id) WHERE deleted_at IS NULL;
GO

-- 2026-10-06 (alter_72): NO BOX = nomor urut box dalam ORDER (1, 2, 3, ...),
-- terpisah dari box_code (urut per satuan). Tidak pernah didaur ulang.
IF COL_LENGTH('tni.box','box_no') IS NULL
    ALTER TABLE tni.box ADD box_no int null;
GO
;WITH n AS (
    SELECT b.box_id,
           ISNULL((SELECT MAX(x.box_no) FROM tni.box x WHERE x.order_id = b.order_id), 0)
             + ROW_NUMBER() OVER (PARTITION BY b.order_id ORDER BY b.created_at, b.box_id) AS no_baru
    FROM tni.box b
    WHERE b.box_no IS NULL
)
UPDATE b SET box_no = n.no_baru
FROM tni.box b JOIN n ON n.box_id = b.box_id;
GO
IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('tni.box') AND name = 'box_no' AND is_nullable = 1)
    ALTER TABLE tni.box ALTER COLUMN box_no int not null;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_box_order_no' AND object_id = OBJECT_ID('tni.box'))
    CREATE UNIQUE INDEX UX_tni_box_order_no ON tni.box(order_id, box_no);
GO

-- 2026-10-06 (alter_73): supplier setoran stok (teks bebas, opsional).
IF COL_LENGTH('tni.stok_mutasi','supplier') IS NULL
    ALTER TABLE tni.stok_mutasi ADD supplier varchar(150) null;
GO

-- 2026-10-06 (alter_74): akses MENU per perangkat -- satu baris per menu yang
-- DIIZINKAN. Perangkat lama di-backfill semua menu oleh alter_74.
IF OBJECT_ID('tni.perangkat_menu','U') IS NULL
CREATE TABLE tni.perangkat_menu(
 perangkat_menu_id int primary key identity(1,1),
 perangkat_id int not null
   constraint FK_tni_perangkat_menu_perangkat foreign key references tni.perangkat(perangkat_id),
 menu_code varchar(30) not null
   constraint CK_tni_perangkat_menu_code check (menu_code in
     ('PERINTAH_KERJA','SCAN','BOX','STOK','PERSONEL','DASHBOARD','IMPORT','POLA')),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_perangkat_menu' AND object_id = OBJECT_ID('tni.perangkat_menu'))
    CREATE UNIQUE INDEX UX_tni_perangkat_menu ON tni.perangkat_menu(perangkat_id, menu_code) WHERE deleted_at IS NULL;
GO

-- 2026-10-07 (alter_76): header SETORAN stok -- satu setoran per
-- (order, tanggal, supplier); setoran kedua dengan kunci sama digabung.
-- stok_mutasi.tanggal/supplier tetap diisi & disinkronkan SIS_Stok_Manage.
IF OBJECT_ID('tni.stok_setoran','U') IS NULL
CREATE TABLE tni.stok_setoran(
 setoran_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_stok_setoran_orders foreign key references tni.orders(order_id),
 tanggal date not null,
 supplier varchar(150) null,
 perangkat_id int null
   constraint FK_tni_stok_setoran_perangkat foreign key references tni.perangkat(perangkat_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_stok_setoran_kunci' AND object_id = OBJECT_ID('tni.stok_setoran'))
    CREATE UNIQUE INDEX UX_tni_stok_setoran_kunci
        ON tni.stok_setoran(order_id, tanggal, supplier) WHERE deleted_at IS NULL;
GO
IF COL_LENGTH('tni.stok_mutasi','setoran_id') IS NULL
    ALTER TABLE tni.stok_mutasi ADD setoran_id int null
        constraint FK_tni_stok_mutasi_setoran foreign key references tni.stok_setoran(setoran_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_mutasi_setoran' AND object_id = OBJECT_ID('tni.stok_mutasi'))
    CREATE INDEX IX_tni_stok_mutasi_setoran ON tni.stok_mutasi(setoran_id) WHERE deleted_at IS NULL;
GO

-- 2026-10-07 (alter_77): header PENGELUARAN stok (RUSAK / KOREKSI), banyak
-- pola per pengeluaran. Tidak ada kunci unik -- tiap simpan satu pengeluaran.
-- Tanda qty mutasi = arah header; tanggal/alasan disinkronkan SIS_Stok_Manage.
IF OBJECT_ID('tni.stok_keluar','U') IS NULL
CREATE TABLE tni.stok_keluar(
 keluar_id int primary key identity(1,1),
 order_id int not null
   constraint FK_tni_stok_keluar_orders foreign key references tni.orders(order_id),
 tanggal date not null,
 jenis_mutasi varchar(20) not null
   constraint CK_tni_stok_keluar_jenis check (jenis_mutasi in ('RUSAK','KOREKSI')),
 arah int not null
   constraint CK_tni_stok_keluar_arah check (arah in (-1, 1)),
 alasan varchar(500) not null,
 perangkat_id int null
   constraint FK_tni_stok_keluar_perangkat foreign key references tni.perangkat(perangkat_id),
 created_at datetime2 not null default sysdatetime(),
 created_by int not null,
 updated_at datetime2 null,
 updated_by int null,
 deleted_at datetime2 null,
 deleted_by int null,
 constraint CK_tni_stok_keluar_rusak_kurang check (jenis_mutasi <> 'RUSAK' OR arah = -1)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_keluar_order' AND object_id = OBJECT_ID('tni.stok_keluar'))
    CREATE INDEX IX_tni_stok_keluar_order ON tni.stok_keluar(order_id, tanggal) WHERE deleted_at IS NULL;
GO
IF COL_LENGTH('tni.stok_mutasi','keluar_id') IS NULL
    ALTER TABLE tni.stok_mutasi ADD keluar_id int null
        constraint FK_tni_stok_mutasi_keluar foreign key references tni.stok_keluar(keluar_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_tni_stok_mutasi_keluar' AND object_id = OBJECT_ID('tni.stok_mutasi'))
    CREATE INDEX IX_tni_stok_mutasi_keluar ON tni.stok_mutasi(keluar_id) WHERE deleted_at IS NULL;
GO
