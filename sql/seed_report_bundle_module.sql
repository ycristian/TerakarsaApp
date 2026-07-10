-- Registrasi module baru Laporan Bundle (read-only, arus bundle WIP/Progres/Riwayat),
-- grup "Order" sejajar BUNDLE_MANAGE. Akses: role yang sama dengan BUNDLE_MANAGE (Admin).
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'REPORT_BUNDLE')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('REPORT_BUNDLE', 'Laporan Bundle', 'Order', NULL, 'report-bundle', 'fe fe-bar-chart-2', 53, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'REPORT_BUNDLE'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
