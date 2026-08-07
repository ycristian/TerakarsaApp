-- Prompt 50: kolom untuk restrukturisasi workflow artikel yang sudah berjalan (sisip step +
-- nonaktifkan step) tanpa memutus rantai handover. Lihat sql/sp_ArticleWorkflow_Restructure.sql
-- untuk logika SP baru yang memakai kolom-kolom ini.

-- article_workflows.inactive_at/inactive_by: diisi = step berhenti jadi jalur untuk unit baru.
-- Baris step nonaktif TETAP deleted_at IS NULL dengan sengaja -- semua SP baca memfilter
-- deleted_at IS NULL dengan INNER JOIN, jadi soft delete akan membuat log yang menempel di
-- step itu hilang diam-diam dari laporan/timeline/WIP.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflows') AND name = 'inactive_at')
BEGIN
    ALTER TABLE article_workflows ADD inactive_at datetime2 null;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflows') AND name = 'inactive_by')
BEGIN
    ALTER TABLE article_workflows ADD inactive_by int null;
END
GO

-- article_workflow_logs.target_division_id_original: nilai target_division_id SEBELUM
-- redirect pertama (INSERT_STEP kategori B, atau DEACTIVATE_STEP). Hanya diisi kalau masih
-- NULL -- redirect kedua pada baris yang sama TIDAK BOLEH menimpanya (lihat SIS_ArticleWorkflow_
-- Restructure, kedua action INSERT_STEP dan DEACTIVATE_STEP memakai
-- "target_division_id_original = ISNULL(target_division_id_original, <nilai lama>)").
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('article_workflow_logs') AND name = 'target_division_id_original')
BEGIN
    ALTER TABLE article_workflow_logs ADD target_division_id_original int null;
END
GO
