-- Prompt 22: Registrasi module baru Dashboard WIP per Divisi & Resource (read-only,
-- bottleneck monitoring), grup "Order" sejajar REPORT_BUNDLE. Akses: role yang sama
-- dengan REPORT_BUNDLE (Admin). Idempotent: aman dijalankan berulang, tidak menghapus
-- data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'REPORT_WIP')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('REPORT_WIP', 'Dashboard WIP', 'Order', NULL, 'wip-dashboard', 'fe fe-activity', 54, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'REPORT_WIP'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
