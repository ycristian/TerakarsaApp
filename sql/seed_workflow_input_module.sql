-- Registrasi module baru untuk input log step non-bundle (mis. Cutting), pintu masuk
-- mandiri lewat UI login (bukan lagi lewat stasiun -- lihat prompt_12c), grup "Order"
-- sejajar BUNDLE_MANAGE. Label menu "Hasil Cutting" (bahasa lapangan), tapi halamannya
-- generik untuk SEMUA step requires_bundle = 0 milik artikel manapun.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'WORKFLOW_INPUT')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('WORKFLOW_INPUT', 'Hasil Cutting', 'Order', NULL, 'workflow-input', 'fe fe-scissors', 52, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'WORKFLOW_INPUT'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
