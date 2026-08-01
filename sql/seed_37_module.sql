-- Prompt 37 -- Registrasi module baru Planning Harian PPIC, sejajar ORDER_PROJECT/
-- BUNDLE_MANAGE/WORKFLOW_INPUT di section "Production". Idempotent: aman dijalankan
-- berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'PPIC_PLANNING')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('PPIC_PLANNING', 'Planning Harian', 'Production', NULL, 'ppic-planning', 'fe fe-calendar', 60, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'PPIC_PLANNING'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
