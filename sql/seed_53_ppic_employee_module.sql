-- Prompt 53: Registrasi module PPIC_EMPLOYEE -- pintu masuk mandiri untuk PPIC mengelola
-- penjahit sendiri (CREATE/UPDATE/DELETE/SETACTIVE dibatasi ke divisi ppic_managed = 1, lihat
-- sp_PpicEmployee_Manage.sql/sp_PpicEmployee_Select.sql). Assign ke Role = Admin dulu untuk
-- pengujian -- user PPIC-nya di-assign manual lewat halaman Module Access (BUKAN auto-assign,
-- supaya scope PPIC eksplisit dipilih per divisi lewat checkbox "Dikelola PPIC" di Master
-- Divisi terlebih dulu -- lihat langkah 5/6 di prompt).
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'PPIC_EMPLOYEE')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('PPIC_EMPLOYEE', 'Karyawan (PPIC)', 'Production', 'ppic/karyawan', 'fe fe-user-plus', 200, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent) -- untuk pengujian.
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'PPIC_EMPLOYEE'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO
