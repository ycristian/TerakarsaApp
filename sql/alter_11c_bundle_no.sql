-- Migrasi untuk DB yang sudah ada: kolom bundle_no (nomor urut per project, tidak
-- pernah dipakai ulang meski bundle dihapus) pada tabel bundles. Idempotent, aman
-- dijalankan berulang.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('bundles') AND name = 'bundle_no'
)
BEGIN
    ALTER TABLE bundles ADD bundle_no int NULL;
END
GO

-- Backfill: nomori SEMUA bundle (termasuk yang soft-deleted) per project, urut
-- created_at lalu bundle_id. Hanya menyentuh baris yang belum punya bundle_no,
-- jadi aman dijalankan ulang setelah kolom sudah NOT NULL (0 baris ter-update).
;WITH Numbered AS (
    SELECT
        b.bundle_id,
        ROW_NUMBER() OVER (PARTITION BY a.project_id ORDER BY b.created_at ASC, b.bundle_id ASC) AS rn
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    WHERE b.bundle_no IS NULL
)
UPDATE b
SET b.bundle_no = n.rn
FROM bundles b
INNER JOIN Numbered n ON n.bundle_id = b.bundle_id;
GO

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('bundles') AND name = 'bundle_no' AND is_nullable = 1
)
BEGIN
    ALTER TABLE bundles ALTER COLUMN bundle_no int NOT NULL;
END
GO
