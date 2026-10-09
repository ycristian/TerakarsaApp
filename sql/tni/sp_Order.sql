-- Order aktif PDH TNI AD (Prompt 61). Dipakai TniOrderState di client dan
-- subjudul beranda module (Prompt 63). Semua halaman /tni/... bekerja pada
-- order tni.orders.is_active = 1.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE tni.SIS_Order_Aktif
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
           o.order_id       AS OrderId,
           o.order_code     AS OrderCode,
           o.order_name     AS OrderName,
           o.instansi       AS Instansi,
           o.tahun          AS Tahun,
           o.target_qty     AS TargetQty,
           -- status personel selalu dari view, bukan CASE ulang
           (SELECT COUNT(*) FROM tni.v_personel v WHERE v.order_id = o.order_id)   AS TotalPersonel,
           (SELECT COUNT(*) FROM tni.area_rawatan a
             WHERE a.order_id = o.order_id AND a.deleted_at IS NULL)               AS JumlahArea,
           (SELECT COUNT(*) FROM tni.satuan s
              JOIN tni.area_rawatan a2 ON a2.area_id = s.area_id AND a2.deleted_at IS NULL
             WHERE a2.order_id = o.order_id AND s.deleted_at IS NULL)              AS JumlahSatuan
    FROM tni.orders o
    WHERE o.is_active = 1 AND o.deleted_at IS NULL
    ORDER BY o.order_id DESC;
END;
GO
