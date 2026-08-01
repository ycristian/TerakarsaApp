-- Prompt 36 -- Registrasi module baru Jam Kerja & Target Default, digabung ke section
-- "App Setting" > "Master Data" yang sudah dipakai divisions/positions/resource_types/resources.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'SETTING_JAM_KERJA')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('SETTING_JAM_KERJA', 'Jam Kerja & Target', 'App Setting', 'Master Data', 'work-schedule', 'fe fe-clock', 180, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'SETTING_JAM_KERJA'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
