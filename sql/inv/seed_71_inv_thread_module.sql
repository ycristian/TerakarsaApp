/* =============================================================
   Module Stok Benang (Prompt 71) -- registrasi module INV_THREAD.
   Satu module untuk SELURUH halaman /gudang/benang/... (landing, SKU,
   lokasi, master, movement & opname di prompt berikutnya).

   Ini satu-satunya tempat seri 71-77 menyentuh schema dbo
   (tabel Modules & UserModules) -- plus sql/inv/alter_71_home_route.sql.

   Idempotent: aman dijalankan berulang, tidak menghapus data yang ada.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'INV_THREAD')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('INV_THREAD', 'Stok Benang', 'Gudang', NULL, 'gudang/benang', 'fe fe-layers', 300, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
-- User role WAREHOUSE (Admin Gudang) di-assign terpisah oleh seed_71_user_gudang.sql.
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'INV_THREAD'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
