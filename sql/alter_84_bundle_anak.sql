-- ============================================================================
-- Prompt 82 -- Bundle anak, pemecahan, dan selisih.
-- (Nomor file 84 karena alter_82/alter_83 sudah dipakai script index performa
--  stasiun yang tidak berhubungan -- isi file ini tetap Prompt 82.)
--
-- SEMUA PENAMBAHAN. Tidak ada kolom yang dihapus/dikosongkan.
-- Satu-satunya nilai lama yang BERUBAH MAKNA: bundles.qty -- dari "qty awal"
-- menjadi "qty saat ini" (qty awal pindah ke baris log log_kind = 'Creation',
-- lihat sql/migrasi_84_bundle_anak.sql).
--
-- Idempotent: boleh dijalankan berkali-kali.
-- Server: AGS\SQLEXPRESS (192.168.8.233), database TerakarsaDB.
-- DIJALANKAN MANUAL oleh developer.
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- 1. bundles -- pohon induk/anak + status + selisih
-- ---------------------------------------------------------------------------
-- parent_bundle_id : bundle yang LANGSUNG memecahnya (boleh induk utama atau anak).
--                    NULL untuk induk utama.
-- root_bundle_id   : induk utama; self untuk induk utama. Dipakai sebagai sumber
--                    penomoran sequence_no (anak dari anak tetap bernomor dari root).
-- sequence_no      : 0 = induk utama, 1..n = anak. Serial anak = '{serial root}-{seq}',
--                    tampilan = '{bundle_no root}-{seq}' (mis. K-49-1).
-- status           : OK | Perbaikan | Reject | TidakLengkap. SATU bundle SATU status --
--                    campur = pecah jadi anak.
-- reject_category  : RejectBahan | RejectJahit | RejectPrint | Perbaikan | TidakLengkap
-- missing_qty      : hanya di induk utama. Positif = hilang, negatif = lebih.
IF COL_LENGTH('bundles', 'parent_bundle_id') IS NULL
    ALTER TABLE bundles ADD parent_bundle_id INT NULL;
GO
-- DEFAULT 0 (bukan sekadar NOT NULL) supaya INSERT lama yang tidak menyebut kolom ini
-- (SIS_Bundle_Manage CREATE, SIS_CuttingSpread_Manage) tetap jalan -- keduanya langsung
-- meng-UPDATE root_bundle_id = bundle_id di transaksi yang sama setelah insert.
IF COL_LENGTH('bundles', 'root_bundle_id') IS NULL
    ALTER TABLE bundles ADD root_bundle_id INT NOT NULL CONSTRAINT DF_bundles_root_bundle_id DEFAULT 0;
GO
IF COL_LENGTH('bundles', 'sequence_no') IS NULL
    ALTER TABLE bundles ADD sequence_no INT NOT NULL CONSTRAINT DF_bundles_sequence_no DEFAULT 0;
GO
IF COL_LENGTH('bundles', 'status') IS NULL
    ALTER TABLE bundles ADD [status] VARCHAR(15) NOT NULL CONSTRAINT DF_bundles_status DEFAULT 'OK';
GO
IF COL_LENGTH('bundles', 'reject_category') IS NULL
    ALTER TABLE bundles ADD reject_category VARCHAR(20) NULL;
GO
IF COL_LENGTH('bundles', 'reject_reason') IS NULL
    ALTER TABLE bundles ADD reject_reason VARCHAR(500) NULL;
GO
IF COL_LENGTH('bundles', 'missing_qty') IS NULL
    ALTER TABLE bundles ADD missing_qty INT NOT NULL CONSTRAINT DF_bundles_missing_qty DEFAULT 0;
GO

-- Backfill: semua bundle lama = induk utama (root = self, parent NULL, seq 0, OK).
UPDATE bundles SET root_bundle_id = bundle_id WHERE root_bundle_id = 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bundles_parent')
    ALTER TABLE bundles ADD CONSTRAINT FK_bundles_parent
        FOREIGN KEY (parent_bundle_id) REFERENCES bundles(bundle_id);
GO
-- root_bundle_id SENGAJA TANPA foreign key: induk utama menunjuk DIRINYA SENDIRI, dan
-- bundle_id baru hanya diketahui SETELAH insert (identity). Dengan FK self-referencing,
-- insert induk baru tidak punya nilai sah untuk diisi lebih dulu. SP mengisinya dua
-- langkah dalam satu transaksi (INSERT root_bundle_id = 0 -> UPDATE = SCOPE_IDENTITY()).
-- parent_bundle_id tetap ber-FK (selalu bundle yang sudah ada saat anak dibuat).
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_bundles_root')
    ALTER TABLE bundles DROP CONSTRAINT FK_bundles_root;
GO

-- Anak ber-nomor urut unik per root (dipakai juga sebagai penjaga race pembuatan anak).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_bundles_root_sequence')
    CREATE UNIQUE INDEX UX_bundles_root_sequence ON bundles(root_bundle_id, sequence_no)
        WHERE deleted_at IS NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bundles_root')
    CREATE INDEX IX_bundles_root ON bundles(root_bundle_id) WHERE deleted_at IS NULL;
GO
-- Angka "Hilang"/"Lebih" di kartu artikel stasiun: Sigma missing_qty per artikel+size.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bundles_missing')
    CREATE INDEX IX_bundles_missing ON bundles(article_id, article_size_id)
        INCLUDE (missing_qty) WHERE deleted_at IS NULL AND missing_qty <> 0;
GO

-- ---------------------------------------------------------------------------
-- 2. article_workflow_logs -- rantai qty bertanda + jenis baris
-- ---------------------------------------------------------------------------
-- qty_delta : bertanda (+57 Creation, -5 Split/Kirim, +1 Ketemu). Sigma qty_delta per
--             bundle HARUS = bundles.qty -- dipakai sebagai cek konsistensi.
-- qty_after : qty bundle SETELAH baris ini.
-- log_kind  : Creation | Kirim | Split | Dikembalikan | Hilang | Ketemu.
--             Kolom log_type (NORMAL/ADJUSTMENT) yang lama TETAP, tidak diubah.
-- split_id  : FK bundle_splits (baris yang lahir dari satu pemecahan/penemuan).
-- reason    : alasan bebas untuk baris Hilang/Ketemu/Dikembalikan.
--
-- qty_reject_print/fabric/sewing/rework dan qty_lost: BERHENTI diisi untuk log BARU
-- (dibiarkan 0). TIDAK dihapus, TIDAK dikosongkan -- laporan PO lama masih membacanya.
IF COL_LENGTH('article_workflow_logs', 'qty_delta') IS NULL
    ALTER TABLE article_workflow_logs ADD qty_delta INT NOT NULL CONSTRAINT DF_awl_qty_delta DEFAULT 0;
GO
IF COL_LENGTH('article_workflow_logs', 'qty_after') IS NULL
    ALTER TABLE article_workflow_logs ADD qty_after INT NOT NULL CONSTRAINT DF_awl_qty_after DEFAULT 0;
GO
IF COL_LENGTH('article_workflow_logs', 'log_kind') IS NULL
    ALTER TABLE article_workflow_logs ADD log_kind VARCHAR(15) NOT NULL CONSTRAINT DF_awl_log_kind DEFAULT 'Kirim';
GO
IF COL_LENGTH('article_workflow_logs', 'split_id') IS NULL
    ALTER TABLE article_workflow_logs ADD split_id INT NULL;
GO
IF COL_LENGTH('article_workflow_logs', 'reason') IS NULL
    ALTER TABLE article_workflow_logs ADD reason VARCHAR(500) NULL;
GO

-- ---------------------------------------------------------------------------
-- 2b. app_settings -- batas "dua jalur" laporan reject
-- ---------------------------------------------------------------------------
-- Diisi oleh sql/migrasi_84_bundle_anak.sql. Log dengan created_at < nilai ini
-- dibaca dari qty_reject_*/qty_lost (data gaya lama); sesudahnya dari bundle anak
-- + missing_qty. NULL = migrasi belum jalan -> semua dianggap gaya lama.
IF COL_LENGTH('app_settings', 'bundle_split_migrated_at') IS NULL
    ALTER TABLE app_settings ADD bundle_split_migrated_at DATETIME2 NULL;
GO

-- ---------------------------------------------------------------------------
-- 3. bundle_splits -- satu baris per PERNYATAAN pemecahan / penemuan
-- ---------------------------------------------------------------------------
-- kind = 'split' : hasil Kirim Hasil (induk dipecah: OK + anak + selisih)
-- kind = 'found' : hasil modal "Barang ketemu" (selisih induk ditutup, anak lahir)
-- lock_id        : mewarisi lock baris log Kirim-nya (diisi SIS_WorkflowLock_Manage
--                  lewat baris log; disimpan di sini untuk jejak periode).
IF OBJECT_ID('bundle_splits', 'U') IS NULL
BEGIN
    CREATE TABLE bundle_splits(
        split_id          INT PRIMARY KEY IDENTITY(1,1),
        source_bundle_id  INT NOT NULL
            CONSTRAINT FK_bsplit_bundles FOREIGN KEY REFERENCES bundles(bundle_id),
        source_qty_before INT NOT NULL,
        kind              VARCHAR(10) NOT NULL,    -- split | found
        division_id       INT NOT NULL
            CONSTRAINT FK_bsplit_divisions FOREIGN KEY REFERENCES divisions(division_id),
        resource_id       INT NULL
            CONSTRAINT FK_bsplit_resources FOREIGN KEY REFERENCES resources(resource_id),
        created_at        DATETIME2 NOT NULL CONSTRAINT DF_bsplit_created_at DEFAULT SYSDATETIME(),
        created_by        INT NOT NULL,
        lock_id           INT NULL
            CONSTRAINT FK_bsplit_workflow_locks FOREIGN KEY REFERENCES workflow_locks(lock_id)
    );
END
GO

-- ---------------------------------------------------------------------------
-- 4. bundle_split_results -- anak yang lahir (atau anak yang ditambah qty-nya)
-- ---------------------------------------------------------------------------
-- is_system_choice = 1 : alokasi dipilih sistem (LIFO otomatis), 0 = admin mengubahnya.
IF OBJECT_ID('bundle_split_results', 'U') IS NULL
BEGIN
    CREATE TABLE bundle_split_results(
        split_result_id  INT PRIMARY KEY IDENTITY(1,1),
        split_id         INT NOT NULL
            CONSTRAINT FK_bsres_splits FOREIGN KEY REFERENCES bundle_splits(split_id),
        bundle_id        INT NOT NULL
            CONSTRAINT FK_bsres_bundles FOREIGN KEY REFERENCES bundles(bundle_id),
        qty              INT NOT NULL,
        [status]         VARCHAR(15) NOT NULL,
        reject_category  VARCHAR(20) NULL,
        reject_reason    VARCHAR(500) NULL,
        is_system_choice BIT NOT NULL CONSTRAINT DF_bsres_is_system_choice DEFAULT 0
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_awl_bundle_splits')
    ALTER TABLE article_workflow_logs ADD CONSTRAINT FK_awl_bundle_splits
        FOREIGN KEY (split_id) REFERENCES bundle_splits(split_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bsplit_source')
    CREATE INDEX IX_bsplit_source ON bundle_splits(source_bundle_id, created_at DESC);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bsres_split')
    CREATE INDEX IX_bsres_split ON bundle_split_results(split_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_split_id')
    CREATE INDEX IX_awl_split_id ON article_workflow_logs(split_id) WHERE split_id IS NOT NULL;
GO
-- Alokasi LIFO modal "Barang ketemu" membaca baris Hilang terakhir per bundle.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_log_kind')
    CREATE INDEX IX_awl_log_kind ON article_workflow_logs(bundle_id, log_kind, created_at DESC)
        WHERE deleted_at IS NULL;
GO

PRINT 'alter_84_bundle_anak.sql selesai.';
GO
