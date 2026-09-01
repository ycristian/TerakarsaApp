-- Prompt 17: divisi Bundling (step implisit yang disisipkan otomatis oleh
-- SIS_ArticleWorkflow_Manage di antara step non-bundle terakhir dan step ber-bundle
-- pertama). Tidak ada station/token untuk divisi ini -- lihat prompt 17.
-- Idempotent: aman dijalankan berulang.

IF NOT EXISTS (SELECT 1 FROM divisions WHERE division_code = 'BD' AND deleted_at IS NULL)
    INSERT INTO divisions (division_code, division_name, created_at, created_by)
    VALUES ('BD', N'Bundling', SYSDATETIME(), 1);
GO
