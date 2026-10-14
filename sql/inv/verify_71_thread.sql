/* =============================================================
   Verifikasi Prompt 71 -- schema `inv`, master benang, module & role.
   HANYA MEMBACA (tidak membuat/mengubah data). Jalankan SETELAH:
     1. create_71_inv_thread.sql
     2. sp_71_ThreadMaster.sql
     3. seed_71_inv_thread.sql
     4. seed_71_inv_thread_module.sql
     5. alter_71_home_route.sql
     6. seed_71_user_gudang.sql

   Tiap baris hasil berisi kolom Hasil = OK / GAGAL.
   ============================================================= */

SET NOCOUNT ON;

PRINT '--- 1. Objek schema inv ---';

SELECT 'Tabel' AS Bagian, n.nama AS Objek,
       CASE WHEN OBJECT_ID('inv.' + n.nama, 'U') IS NULL THEN 'GAGAL' ELSE 'OK' END AS Hasil
FROM (VALUES ('thread_types'), ('thread_brands'), ('thread_locations'),
             ('thread_reason_codes'), ('thread_items'), ('thread_stocks'),
             ('thread_split_cones'), ('thread_movements')) AS n(nama)
UNION ALL
SELECT 'View', 'v_thread_item_stock',
       CASE WHEN OBJECT_ID('inv.v_thread_item_stock', 'V') IS NULL THEN 'GAGAL' ELSE 'OK' END
UNION ALL
SELECT 'Fungsi', 'fn_ThreadAlnum',
       CASE WHEN OBJECT_ID('inv.fn_ThreadAlnum', 'FN') IS NULL THEN 'GAGAL' ELSE 'OK' END
UNION ALL
SELECT 'SP', n.nama,
       CASE WHEN OBJECT_ID('inv.' + n.nama, 'P') IS NULL THEN 'GAGAL' ELSE 'OK' END
FROM (VALUES ('SIS_ThreadType_Manage'), ('SIS_ThreadType_List'),
             ('SIS_ThreadBrand_Manage'), ('SIS_ThreadBrand_List'),
             ('SIS_ThreadLocation_Manage'), ('SIS_ThreadLocation_List'),
             ('SIS_ThreadItem_Manage'), ('SIS_ThreadItem_List'),
             ('SIS_ThreadItem_GetById'), ('SIS_ThreadItem_GetBySku')) AS n(nama);

PRINT '--- 2. Filtered unique index ---';

SELECT i.name AS IndeksUnik, OBJECT_NAME(i.object_id) AS Tabel,
       CASE WHEN i.is_unique = 1 AND i.has_filter = 1 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM sys.indexes i
WHERE i.object_id IN (
        OBJECT_ID('inv.thread_types'), OBJECT_ID('inv.thread_brands'),
        OBJECT_ID('inv.thread_locations'), OBJECT_ID('inv.thread_items'),
        OBJECT_ID('inv.thread_stocks'), OBJECT_ID('inv.thread_split_cones'))
  AND i.name LIKE 'UX_%';

PRINT '--- 3. Seed ---';

SELECT 'thread_types' AS Tabel, COUNT(*) AS Jumlah,
       CASE WHEN COUNT(*) >= 4 THEN 'OK' ELSE 'GAGAL' END AS Hasil
FROM inv.thread_types WHERE deleted_at IS NULL
UNION ALL
SELECT 'thread_reason_codes', COUNT(*),
       CASE WHEN COUNT(*) >= 7 THEN 'OK' ELSE 'GAGAL' END
FROM inv.thread_reason_codes WHERE deleted_at IS NULL;

-- Hanya LAINNYA yang wajib keterangan.
SELECT 'LAINNYA requires_note' AS Cek,
       CASE WHEN EXISTS (SELECT 1 FROM inv.thread_reason_codes
                          WHERE code = 'LAINNYA' AND requires_note = 1)
             AND NOT EXISTS (SELECT 1 FROM inv.thread_reason_codes
                              WHERE code <> 'LAINNYA' AND requires_note = 1)
            THEN 'OK' ELSE 'GAGAL' END AS Hasil;

PRINT '--- 4. Module & role ---';

SELECT 'Module INV_THREAD' AS Cek,
       CASE WHEN EXISTS (SELECT 1 FROM Modules
                          WHERE Code = 'INV_THREAD' AND Route = 'gudang/benang' AND IsActive = 1)
            THEN 'OK' ELSE 'GAGAL' END AS Hasil
UNION ALL
SELECT 'Kolom Users.home_route',
       CASE WHEN EXISTS (SELECT 1 FROM sys.columns
                          WHERE object_id = OBJECT_ID('dbo.Users') AND name = 'home_route')
            THEN 'OK' ELSE 'GAGAL' END
UNION ALL
SELECT 'User gudang role WAREHOUSE',
       CASE WHEN EXISTS (SELECT 1 FROM Users WHERE Username = 'gudang' AND Role = 'WAREHOUSE')
            THEN 'OK' ELSE 'GAGAL' END
UNION ALL
SELECT 'User gudang hanya module INV_THREAD',
       CASE WHEN (SELECT COUNT(*) FROM UserModules um
                   INNER JOIN Users u ON u.Id = um.UserId
                   INNER JOIN Modules m ON m.Id = um.ModuleId
                   WHERE u.Username = 'gudang') = 1
             AND EXISTS (SELECT 1 FROM UserModules um
                          INNER JOIN Users u ON u.Id = um.UserId
                          INNER JOIN Modules m ON m.Id = um.ModuleId
                          WHERE u.Username = 'gudang' AND m.Code = 'INV_THREAD')
            THEN 'OK' ELSE 'GAGAL' END;

-- HomeRoute harus terisi untuk user gudang (lewat SP yang dipakai login).
EXEC SIS_User_GetByUsername @Username = 'gudang';

PRINT '--- 5. Read SP jalan (database masih kosong, hanya cek binding kolom) ---';

EXEC inv.SIS_ThreadType_List;
EXEC inv.SIS_ThreadBrand_List;
EXEC inv.SIS_ThreadLocation_List @HanyaAktif = 0;
EXEC inv.SIS_ThreadItem_List @PageNumber = 1, @PageSize = 5;
EXEC inv.SIS_ThreadItem_GetById @Id = -1;
EXEC inv.SIS_ThreadItem_GetBySku @SkuCode = 'TB:TIDAK-ADA';

PRINT '--- 6. Pembentuk sku_code ---';

SELECT inv.fn_ThreadAlnum('Astra Jaya')  AS Brand3Sumber,   -- ASTRAJAYA -> AST
       inv.fn_ThreadAlnum('poly')        AS TypeSumber,     -- POLY -> POL
       inv.fn_ThreadAlnum('20-41 b')     AS KodeWarna,      -- 2041B
       CASE WHEN inv.fn_ThreadAlnum('Astra Jaya') = 'ASTRAJAYA'
             AND inv.fn_ThreadAlnum('20-41 b') = '2041B'
            THEN 'OK' ELSE 'GAGAL' END   AS Hasil;
GO
