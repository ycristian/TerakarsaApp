-- Prompt 38 -- Registrasi module baru Dashboard TV (halaman admin kelola token, BUKAN
-- halaman kiosk /tv-dashboard yang selalu publik & diamankan token). Digabung ke section
-- "App Setting". Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'DASHBOARD_TARGET')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('DASHBOARD_TARGET', 'Dashboard TV', 'App Setting', NULL, 'dashboard-tokens', 'fe fe-monitor', 190, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'DASHBOARD_TARGET'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
