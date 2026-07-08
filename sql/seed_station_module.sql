-- Registrasi module baru untuk kelola Stasiun, grup "App Setting".
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'STATION_MANAGE')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('STATION_MANAGE', 'Kelola Stasiun', 'App Setting', 'stations', 'fe fe-monitor', 60, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'STATION_MANAGE'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
