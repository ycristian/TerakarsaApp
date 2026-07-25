-- Prompt 29: bundles.delete_reason -- bundles tidak punya kolom ini sebelumnya (soft delete
-- lewat SIS_Bundle_Manage tidak pernah meminta alasan). SIS_SuperAdmin_Manage action
-- BUNDLE_DELETE mewajibkan alasan, jadi kolomnya ditambahkan di sini.
-- Idempotent -- aman dijalankan berkali-kali.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('bundles') AND name = 'delete_reason'
)
BEGIN
    ALTER TABLE bundles
        ADD delete_reason varchar(255) null;
END
GO
