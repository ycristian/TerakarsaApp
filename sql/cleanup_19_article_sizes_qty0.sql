-- Prompt 19: data lama -- soft delete article_sizes hidup ber-qty = 0 yang tidak
-- direferensikan bundle/log produksi hidup (SIS_Article_Manage sekarang mencegah baris
-- seperti ini terbentuk lagi, tapi baris lama sebelum Prompt 19 perlu dibersihkan manual).
-- Idempotent: aman dijalankan berulang (baris yang sudah di-soft-delete tidak terjaring lagi).
-- Dijalankan manual sekali oleh developer.

UPDATE asz
SET asz.deleted_at = SYSDATETIME(),
    asz.deleted_by = 1
FROM article_sizes asz
WHERE asz.deleted_at IS NULL
  AND asz.qty = 0
  AND NOT EXISTS (SELECT 1 FROM bundles b WHERE b.article_size_id = asz.article_size_id AND b.deleted_at IS NULL)
  AND NOT EXISTS (SELECT 1 FROM article_workflow_logs awl WHERE awl.article_size_id = asz.article_size_id AND awl.deleted_at IS NULL);
GO
