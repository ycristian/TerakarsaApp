-- Membuat buyer_id di size_packs opsional (nullable), karena size pack kini
-- bisa dibuat tanpa terikat ke buyer tertentu (dipakai lintas project/buyer).
-- Idempotent: aman dijalankan berulang.

IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('size_packs') AND name = 'buyer_id' AND is_nullable = 0
)
BEGIN
    ALTER TABLE size_packs ALTER COLUMN buyer_id INT NULL;
END
GO
