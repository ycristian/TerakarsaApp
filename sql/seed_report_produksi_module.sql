-- Prompt 30: Registrasi module baru Laporan Produksi Periode Gajian (read-only, dasar
-- penggajian mingguan), grup "Order" sejajar REPORT_BUNDLE/REPORT_WIP. Akses: role yang sama
-- (Admin). Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'REPORT_PRODUKSI')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('REPORT_PRODUKSI', 'Laporan Produksi', 'Order', NULL, 'reports/produksi', 'fe fe-calendar', 55, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'REPORT_PRODUKSI'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
