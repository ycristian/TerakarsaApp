-- Registrasi module PDH TNI AD (Prompt 60), grup "Order" setelah REPORT_ACTIVITY (56).
--   TNI_PDH          -- beranda module + seluruh halaman operasional /tni/...
--   TNI_PDH_APPROVE  -- khusus memutus pengajuan pembatalan scan (Prompt 68)
-- Akses: role yang sama dengan module Order lain (Admin).
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.
-- CATATAN: ini satu-satunya tempat seri 60-69 menyentuh schema dbo
-- (tabel Modules & UserModules).

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'TNI_PDH')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('TNI_PDH', 'PDH TNI AD', 'Order', NULL, 'tni', 'fe fe-shield', 57, 1, GETDATE());
GO

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'TNI_PDH_APPROVE')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('TNI_PDH_APPROVE', 'Persetujuan PDH TNI', 'Order', NULL, 'tni/pembatalan', 'fe fe-check-square', 58, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code IN ('TNI_PDH', 'TNI_PDH_APPROVE')
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
