-- Prompt 47: Registrasi module baru Log Aktivitas (read-only, listing mentah
-- article_workflow_logs tanpa agregasi), grup "Order" sejajar REPORT_WIP/REPORT_PRODUKSI.
-- Akses: role yang sama (Admin). Idempotent: aman dijalankan berulang, tidak menghapus
-- data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'REPORT_ACTIVITY')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('REPORT_ACTIVITY', 'Log Aktivitas', 'Order', NULL, 'activity-log', 'fe fe-list', 56, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'REPORT_ACTIVITY'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
