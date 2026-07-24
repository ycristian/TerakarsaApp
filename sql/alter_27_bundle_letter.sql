-- Prompt 27: kode huruf bundle per project (bundle_letter, A-Z berputar). Tampilan
-- bundle_no jadi "{huruf}-{bundle_no}" (mis. B-27); logika bundle_no sendiri TIDAK berubah.
-- Idempotent, aman dijalankan berulang.

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('projects') AND name = 'bundle_letter'
)
BEGIN
    ALTER TABLE projects ADD bundle_letter char(1) NULL;
END
GO

-- Backfill: hanya project AKTIF (belum dihapus, manual_status bukan COMPLETED/CANCELLED),
-- urut created_at lalu project_id. Huruf berputar A-Z setelah 26 project (duplikasi
-- diterima -- project lama sudah selesai saat huruf berputar). Hanya menyentuh baris yang
-- belum punya bundle_letter, jadi aman dijalankan ulang.
;WITH Numbered AS (
    SELECT
        project_id,
        ROW_NUMBER() OVER (ORDER BY created_at ASC, project_id ASC) AS rn
    FROM projects
    WHERE bundle_letter IS NULL
      AND deleted_at IS NULL
      AND ISNULL(manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
)
UPDATE p
SET p.bundle_letter = CHAR(65 + ((n.rn - 1) % 26))
FROM projects p
INNER JOIN Numbered n ON n.project_id = p.project_id;
GO
