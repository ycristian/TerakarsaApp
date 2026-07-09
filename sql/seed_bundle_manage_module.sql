-- Registrasi module baru untuk pintu masuk mandiri Kelola Bundle, grup "Order"
-- (sejajar dengan ORDER_PROJECT, flat -- bukan submenu), supaya supervisor produksi
-- tidak perlu privilege PROJECT hanya untuk membuat bundle harian.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'BUNDLE_MANAGE')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('BUNDLE_MANAGE', 'Bundle', 'Order', NULL, 'bundles', 'fe fe-package', 51, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'BUNDLE_MANAGE'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
