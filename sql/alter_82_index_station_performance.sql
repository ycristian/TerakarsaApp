-- =============================================================================
-- alter_82_index_station_performance.sql
--
-- MASALAH: /station butuh 10-20 detik setiap refresh/polling. Diukur di TKA001:
--   SIS_Station_Counts     avg 5.2 s  (max 20.3 s), 2.400.019 logical reads / exec
--   SIS_Station_ActiveWork avg 3.6 s  (max 13.9 s), 1.169.733 logical reads / exec
--   SIS_Station_InProgress avg 1.6 s  (max  3.1 s),   624.558 logical reads / exec
-- padahal article_workflow_logs hanya 26.826 baris dan bundles 6.176 baris.
--
-- SEBAB: dua index yang SUDAH ditulis di create_tables_tmos_final.sql,
--   IX_awl_bundle (bundle_id) dan IX_awl_article_workflow (article_workflow_id),
-- TIDAK ADA di database (hanya dua ini yang hilang dari seluruh index canonical --
-- diduga ikut hilang saat salah satu recreate article_workflow_logs). Akibatnya
-- setiap subquery berkorelasi di dalam CROSS APPLY ketiga SP itu
--   ... WHERE article_workflow_id = @x AND bundle_id = @y AND deleted_at IS NULL
-- dipaksa SCAN SELURUH tabel. SET STATISTICS IO untuk SIS_Station_Counts
-- @DivisionId=2, @ResourceId=NULL:
--   article_workflow_logs : scan count 5.791 -> 5.949.349 logical reads
--   article_workflows     : scan count 5.785 ->   300.820 logical reads
-- article_workflows memang belum punya index nonclustered SAMA SEKALI.
--
-- Dua nama canonical dipakai ULANG (tidak menambah nama baru) tapi definisinya
-- dinaikkan jadi composite + covering, supaya satu index melayani seek berkorelasi
-- SEKALIAN menyediakan kolom qty_* tanpa key lookup -- bukan dua index yang
-- prefix-nya saling tumpang tindih. create_tables_tmos_final.sql ikut diperbarui.
--
-- Semua filtered WHERE deleted_at IS NULL: seluruh query TMOS selalu menyertakan
-- syarat itu, jadi filtered index tetap bisa dipakai optimizer.
-- CATATAN: filtered index WAJIB SET QUOTED_IDENTIFIER ON (default sqlcmd OFF).
-- =============================================================================

SET QUOTED_IDENTIFIER ON;
GO

USE TerakarsaDB;
GO

-- ---------------------------------------------------------------------------
-- 1. article_workflow_logs
-- ---------------------------------------------------------------------------

-- Inti perbaikan. Melayani SEMUA subquery berkorelasi per bundle di
-- SIS_Station_Counts / SIS_Station_InProgress / SIS_Bundle_ScanInfo:
--   SUM(qty_ok) dan SUM(qty_ok + qty_reject_* + qty_lost) per (step, bundle),
--   EXISTS baris sudah diterima / masih menggantung per (bundle, divisi).
-- INCLUDE sengaja memuat seluruh kolom qty + received_at + kedua divisi supaya
-- CROSS APPLY frontier tidak perlu key lookup ke clustered sama sekali.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_bundle' AND object_id = OBJECT_ID('article_workflow_logs'))
    CREATE INDEX IX_awl_bundle ON article_workflow_logs(bundle_id, article_workflow_id)
        INCLUDE (division_id, target_division_id, received_at, article_size_id, resource_id,
                 qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost)
        WHERE deleted_at IS NULL;
GO

-- Jalur non-bundle: SizesJson & StockCutting per size di SIS_Station_ActiveWork
-- (SUM(qty_ok) per step x size) dan WorkStartedAt (MAX(received_at) per step).
-- Kolom pertama sama dengan definisi canonical lama, jadi seek
-- "article_workflow_id = @x" saja tetap terlayani.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_article_workflow' AND object_id = OBJECT_ID('article_workflow_logs'))
    CREATE INDEX IX_awl_article_workflow ON article_workflow_logs(article_workflow_id, article_size_id)
        INCLUDE (bundle_id, division_id, target_division_id, received_at, created_at, qty_ok)
        WHERE deleted_at IS NULL;
GO

-- MasukCount (SIS_Station_Counts) + SIS_Station_PendingReceives: baris yang
-- dikirim KE divisi ini dan belum diterima.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_target_division' AND object_id = OBJECT_ID('article_workflow_logs'))
    CREATE INDEX IX_awl_target_division ON article_workflow_logs(target_division_id, received_at)
        INCLUDE (bundle_id, article_workflow_id, article_size_id, resource_id, qty_ok, created_at)
        WHERE deleted_at IS NULL;
GO

-- DikirimCount + OutUnlockedCount (SIS_Station_Counts), SIS_Station_PendingHandover,
-- SIS_Station_UnlockedDates: semuanya memfilter division_id = @DivisionId lalu
-- menimbang lock_id / log_type / created_at / resource_id.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_awl_division' AND object_id = OBJECT_ID('article_workflow_logs'))
    CREATE INDEX IX_awl_division ON article_workflow_logs(division_id)
        INCLUDE (article_workflow_id, bundle_id, resource_id, qty_ok, received_at,
                 target_division_id, created_at, log_type, lock_id)
        WHERE deleted_at IS NULL;
GO

-- ---------------------------------------------------------------------------
-- 2. article_workflows -- sebelum ini TIDAK punya index nonclustered sama sekali,
--    padahal dipindai 5.785 kali per eksekusi SIS_Station_Counts.
-- ---------------------------------------------------------------------------

-- Dipakai subquery IsLastStep / NextDivisionId / NextDivisionName / step
-- sebelumnya (MAX(sort_order) < sort_order) dan CROSS APPLY frontier --
-- semuanya "article_id = @x AND deleted_at IS NULL" lalu urut sort_order.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_aw_article_sort' AND object_id = OBJECT_ID('article_workflows'))
    CREATE INDEX IX_aw_article_sort ON article_workflows(article_id, sort_order)
        INCLUDE (division_id, step_name, requires_bundle, is_bundling, inactive_at, unit_price)
        WHERE deleted_at IS NULL;
GO

-- Daftar step milik divisi stasiun ini (SIS_Station_ActiveWork, DikerjakanCount).
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_aw_division' AND object_id = OBJECT_ID('article_workflows'))
    CREATE INDEX IX_aw_division ON article_workflows(division_id)
        INCLUDE (article_id, sort_order, step_name, requires_bundle, is_bundling, inactive_at)
        WHERE deleted_at IS NULL;
GO

UPDATE STATISTICS article_workflow_logs WITH FULLSCAN;
UPDATE STATISTICS article_workflows WITH FULLSCAN;
GO

PRINT 'alter_82 selesai. Index station performance terpasang.';
GO
