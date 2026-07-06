-- Registrasi module ORDER_PROJECT untuk section top-level baru "Order" di sidebar
-- (Category = 'Order', SubCategory = NULL -> tampil sebagai link flat, bukan submenu
-- collapsible seperti "Master Data"). Jalankan setelah modules_schema.sql.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'ORDER_PROJECT')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('ORDER_PROJECT', 'Project', 'Order', NULL, 'projects', 'fe fe-briefcase', 50, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'ORDER_PROJECT'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
