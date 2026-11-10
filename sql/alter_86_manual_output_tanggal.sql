-- Tanggal transaksi untuk output manual: manual_outputs.output_date.
-- Idempotent -- aman dijalankan berkali-kali.
-- Jalankan SETELAH sql/alter_83_manual_output_harga.sql.
--
-- -------------------------------------------------------------------------------
-- KENAPA KOLOM BARU, BUKAN created_at
-- Sampai sekarang manual_outputs TIDAK punya tanggal transaksi: created_at cuma stempel
-- kapan PIC mengetik barisnya, dan periode gajiannya datang dari lock_id ->
-- workflow_locks.payroll_period_id. Akibatnya pekerjaan tanggal 30/11 yang baru diketik
-- 02/12 tercatat sebagai 02/12, dan tidak ada cara mengoreksinya.
--
-- output_date = TANGGAL KERJAANNYA TERJADI, diisi PIC di form (bawaannya mengikuti
-- tanggal yang sedang dipilih di tab OUT). created_at TETAP ADA dan tetap murni audit --
-- keduanya sengaja dipisah supaya "kapan dikerjakan" dan "kapan dicatat" bisa berbeda
-- dan dua-duanya masih kelihatan.
--
-- YANG TIDAK BERUBAH: periode gajian TETAP dari lock (aturan CLAUDE.md "periode gajian
-- log = periode di workflow_locks, bukan dari created_at"). output_date TIDAK dipakai
-- SIS_WorkflowLock_Manage maupun SIS_PayrollRekap_* untuk menentukan periode -- kalau
-- nanti mau begitu, itu perubahan terpisah yang menyentuh uang.
--
-- Tipe `date` (bukan datetime2) mengikuti kolom tanggal lain yang diisi manusia di DB ini
-- (spreads.spread_date, employee_attendances.attendance_date, stok_mutasi.movement_date):
-- jam tidak pernah diminta di form, jadi tidak disimpan.
--
-- Tidak ada recreate table di sini (ADD COLUMN + ALTER COLUMN langsung bisa, kolomnya
-- belum dipakai index/constraint apa pun), jadi tidak perlu penampungan data.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- 1. Tambah kolom. Dibuat NULLABLE dulu supaya baris lama bisa diisi di langkah 2 --
--    ADD ... NOT NULL DEFAULT akan menimpa semua baris lama dengan tanggal HARI INI,
--    bukan tanggal aslinya.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('manual_outputs') AND name = 'output_date'
)
    ALTER TABLE manual_outputs ADD output_date date null;
GO

-- ---------------------------------------------------------------------------
-- 2. Backfill baris lama: created_at adalah perkiraan terbaik yang ada. Baris yang
--    tanggal aslinya beda harus dikoreksi manual lewat form (selama belum lock).
-- ---------------------------------------------------------------------------
UPDATE manual_outputs
SET output_date = CAST(created_at AS date)
WHERE output_date IS NULL;
GO

-- ---------------------------------------------------------------------------
-- 3. Baru dijadikan NOT NULL + default hari ini (jaring pengaman kalau ada pemanggil
--    yang tidak mengirim tanggal).
-- ---------------------------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('manual_outputs') AND name = 'output_date' AND is_nullable = 1
)
    ALTER TABLE manual_outputs ALTER COLUMN output_date date not null;
GO

IF NOT EXISTS (SELECT 1 FROM sys.default_constraints WHERE name = 'DF_mo_output_date')
    ALTER TABLE manual_outputs
        ADD CONSTRAINT DF_mo_output_date DEFAULT (CAST(SYSDATETIME() AS date)) FOR output_date;
GO

-- ---------------------------------------------------------------------------
-- 4. Index: tab OUT mengambil per divisi lalu mengurutkan tanggal transaksi.
--    IX_mo_division_lock yang sudah ada tidak menolong urutan ini.
-- ---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_mo_division_date')
    CREATE INDEX IX_mo_division_date ON manual_outputs(division_id, output_date DESC)
        INCLUDE (resource_id, qty, lock_id) WHERE deleted_at IS NULL;
GO

PRINT 'alter_86: manual_outputs.output_date siap.';
GO
