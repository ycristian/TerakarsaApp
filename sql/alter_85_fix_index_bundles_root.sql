-- ============================================================================
-- Perbaikan index UX_bundles_root_sequence (dibuat di alter_84_bundle_anak.sql).
--
-- GEJALA: "Simpan draft" hamparan cutting gagal dengan
--   Cannot insert duplicate key row in object 'dbo.bundles' with unique index
--   'UX_bundles_root_sequence'. The duplicate key value is (0, 0).
--
-- SEBAB: induk utama lahir dengan root_bundle_id = 0 (default kolom) dan baru
-- di-UPDATE jadi dirinya sendiri SESUDAH insert -- bundle_id identity belum ada
-- saat insert. SIS_CuttingSpread_Manage meng-INSERT seluruh bundle hamparan
-- dalam SATU statement set-based, jadi semua baris transit itu memegang
-- (root_bundle_id, sequence_no) = (0, 0) sekaligus dan saling bentrok.
--
-- PERBAIKAN: index unik hanya untuk baris yang root-nya sudah terisi. Jaminan
-- "nomor anak unik per induk" tidak berubah: setiap baris yang sudah commit
-- selalu punya root_bundle_id <> 0 (anak pun selalu dibuat dengan root induknya).
--
-- Idempotent. DIJALANKAN MANUAL oleh developer.
-- ============================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Jaga-jaga: tidak boleh ada baris tertinggal dengan root_bundle_id = 0.
UPDATE bundles SET root_bundle_id = bundle_id WHERE root_bundle_id = 0;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE name = 'UX_bundles_root_sequence' AND object_id = OBJECT_ID('bundles')
             AND ISNULL(filter_definition, '') NOT LIKE '%root_bundle_id%')
    DROP INDEX UX_bundles_root_sequence ON bundles;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_bundles_root_sequence')
    CREATE UNIQUE INDEX UX_bundles_root_sequence ON bundles(root_bundle_id, sequence_no)
        WHERE deleted_at IS NULL AND root_bundle_id <> 0;
GO

SELECT name, filter_definition
FROM sys.indexes
WHERE object_id = OBJECT_ID('bundles') AND name = 'UX_bundles_root_sequence';
GO
