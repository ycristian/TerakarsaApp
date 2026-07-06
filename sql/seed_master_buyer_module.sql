-- Registrasi module MASTER_BUYER untuk grup collapsible "Master Data" di sidebar,
-- digabung ke section "App Setting" yang sudah ada (Category = 'App Setting',
-- SubCategory = 'Master Data'). Jalankan setelah seed_master_data_modules.sql.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'MASTER_BUYER')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('MASTER_BUYER', 'Buyer', 'App Setting', 'Master Data', 'buyers', 'fe fe-shopping-bag', 140, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'MASTER_BUYER'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
