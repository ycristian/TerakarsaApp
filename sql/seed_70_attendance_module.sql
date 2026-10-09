-- Prompt 70 -- Registrasi module HR_ATTENDANCE (halaman /attendance: tab Kartu Karyawan,
-- Rekap Absensi, Koreksi Absensi) + user sistem 'gate_system' untuk kolom created_by mutasi
-- yang datang dari perangkat gate.
-- Idempotent: aman dijalankan berulang, tidak menghapus data yang sudah ada.

-- ============ 1. Module ============

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'HR_ATTENDANCE')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('HR_ATTENDANCE', 'Absensi', 'Order', NULL, 'attendance', 'fe fe-clock', 58, 1, GETDATE());
GO

-- Assign ke seluruh user dengan Role = Admin yang sudah ada (idempotent).
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'HR_ATTENDANCE'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO

-- ============ 2. User sistem gate_system ============

-- Endpoint api/gate/* tidak punya JWT (aplikasi gate memang tanpa login), jadi tidak ada
-- UserId dari token. Semua mutasi dari gate memakai user ini sebagai created_by/updated_by;
-- pelaku sebenarnya (satpam) tercatat di kolom *_by_employee_id.
-- IsActive = 0 supaya user ini tidak bisa dipakai login manual; password diisi nilai acak
-- yang tidak pernah dipakai login.
--
-- SETELAH DIJALANKAN: catat Id yang muncul di hasil SELECT terakhir, lalu isikan ke
-- TerakarsaApp.API/appsettings.json -> "Gate": { "SystemUserId": <Id> }.
IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = 'gate_system')
    INSERT INTO Users (Username, Password, FullName, Role, IsActive, CreatedAt)
    VALUES ('gate_system', LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', '')), N'Gate System', N'System', 0, GETDATE());
GO

SELECT Id, Username, FullName, Role, IsActive FROM Users WHERE Username = 'gate_system';
GO
