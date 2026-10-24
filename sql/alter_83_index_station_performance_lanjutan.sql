-- =============================================================================
-- alter_83_index_station_performance_lanjutan.sql
--
-- Lanjutan alter_82. Setelah alter_82 dijalankan, article_workflow_logs sudah
-- beres (SIS_Station_Counts div 2: 16.627 ms -> 333 ms; reads 5.949.349 -> 11.084),
-- tapi SIS_Station_ActiveWork divisi 7 masih 2.869 ms. SET STATISTICS IO menunjuk
-- tersangka yang BERBEDA -- bottleneck-nya pindah:
--   bundles       : scan count 3.777 -> 543.888 logical reads
--   article_sizes : scan count 2.045 ->  44.990 logical reads
--
-- SEBAB: lima subquery di SIS_Station_ActiveWork (BundleCount, TotalBundleQty,
-- StockCuttingJson, dan dua pasangannya) plus DikerjakanCount di
-- SIS_Station_Counts memfilter bundles lewat article_size_id:
--   ... INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
--       WHERE asz.article_id = aw.article_id AND b.deleted_at IS NULL
--   ... WHERE b.article_size_id = asz6.article_size_id AND b.deleted_at IS NULL
-- tapi bundles TIDAK punya index di article_size_id (yang ada: article_id, serial,
-- cutting_code, (source,stock_status,article_id), (spread_id,bundle_seq)), dan
-- article_sizes tidak punya index nonclustered SAMA SEKALI -- hanya PK
-- article_size_id, padahal yang difilter article_id.
-- =============================================================================

SET QUOTED_IDENTIFIER ON;
GO

USE TerakarsaDB;
GO

-- Arah seek "dari size ke bundle": dipakai StockCuttingJson per size, BundleCount,
-- TotalBundleQty (SIS_Station_ActiveWork), DikerjakanCount (SIS_Station_Counts),
-- dan StockCutting per size di SIS_Article_BundleSummary. INCLUDE qty supaya
-- SUM(b.qty) tidak perlu key lookup; stock_status/source untuk kartu Stok Cutting.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_bundles_article_size' AND object_id = OBJECT_ID('bundles'))
    CREATE INDEX IX_bundles_article_size ON bundles(article_size_id)
        INCLUDE (article_id, qty, resource_id, source, stock_status, bundle_no, sort_order)
        WHERE deleted_at IS NULL;
GO

-- Arah seek "dari artikel ke size". SENGAJA TIDAK filtered WHERE deleted_at IS NULL:
-- subquery BundleCount/TotalBundleQty di SIS_Station_ActiveWork hanya menyaring
-- b.deleted_at, TIDAK asz.deleted_at, jadi filtered index tidak akan dipakai
-- optimizer di sana. Non-filtered melayani kedua pola sekaligus.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_article_sizes_article' AND object_id = OBJECT_ID('article_sizes'))
    CREATE INDEX IX_article_sizes_article ON article_sizes(article_id)
        INCLUDE (size_pack_detail_id, qty, bundle_qty, deleted_at);
GO

UPDATE STATISTICS bundles WITH FULLSCAN;
UPDATE STATISTICS article_sizes WITH FULLSCAN;
GO

PRINT 'alter_83 selesai. Index bundles/article_sizes terpasang.';
GO
