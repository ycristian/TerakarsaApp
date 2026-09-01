-- Ad hoc: konsisten dengan kode divisi lain (CT, SW, PRS, PCK, CR, TR, PRT -- semua
-- singkatan pendek), division_code 'BUNDLING' diganti jadi 'BD'. division_name tetap
-- 'Bundling'. Jalankan SETELAH sp_ArticleWorkflow_Manage.sql (SP versi baru) di-deploy
-- ulang, supaya tidak ada window di mana SP lama masih mencari code 'BUNDLING'.
-- Idempotent: aman dijalankan berulang.

IF EXISTS (SELECT 1 FROM divisions WHERE division_code = 'BUNDLING' AND deleted_at IS NULL)
    UPDATE divisions
    SET division_code = 'BD'
    WHERE division_code = 'BUNDLING' AND deleted_at IS NULL;
GO
