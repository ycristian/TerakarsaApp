/* =============================================================
   PDH TNI AD -- NO BOX per order (2026-10-06).

   Permintaan owner: selain box_code (BDG-DTJ-01, urut per satuan), tiap box
   punya NOMOR URUT DALAM ORDER (1, 2, 3, ...) supaya tahu "ini box ke berapa"
   dan mudah dicari.

   - Diberikan saat CREATE: MAX(box_no) + 1 per order, TERMASUK box yang sudah
     dihapus -> nomor tidak pernah didaur ulang (sama seperti box_code).
   - Box lama diisi menurut urutan dibuat (created_at, box_id).
   - Unik per order TANPA filter deleted_at (nomor box terhapus tetap terpakai).

   Idempotent. ANSI_NULLS/QUOTED_IDENTIFIER ON: tabel tni punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('tni.box','box_no') IS NULL
    ALTER TABLE tni.box ADD box_no int null;
GO

-- isi box lama yang belum bernomor, melanjutkan nomor terbesar yang sudah ada
;WITH n AS (
    SELECT b.box_id,
           ISNULL((SELECT MAX(x.box_no) FROM tni.box x WHERE x.order_id = b.order_id), 0)
             + ROW_NUMBER() OVER (PARTITION BY b.order_id ORDER BY b.created_at, b.box_id) AS no_baru
    FROM tni.box b
    WHERE b.box_no IS NULL
)
UPDATE b SET box_no = n.no_baru
FROM tni.box b JOIN n ON n.box_id = b.box_id;
GO

IF EXISTS (SELECT 1 FROM sys.columns
           WHERE object_id = OBJECT_ID('tni.box') AND name = 'box_no' AND is_nullable = 1)
    ALTER TABLE tni.box ALTER COLUMN box_no int not null;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_tni_box_order_no' AND object_id = OBJECT_ID('tni.box'))
    CREATE UNIQUE INDEX UX_tni_box_order_no ON tni.box(order_id, box_no);
GO

PRINT 'tni.box.box_no siap.';
GO
