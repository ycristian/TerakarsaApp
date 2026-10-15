/* =============================================================
   Prompt 78 -- user Admin Cutting.

   Username  : cutting
   Password  : cutting123   <-- GANTI setelah login pertama
   Role      : CUTTING      (tampilan "Admin Cutting" di halaman User Management)
   home_route: /cutting

   Hash dibuat dengan tool yang sama seperti user lain:
     dotnet run --project tools/PasswordHashTool -- cutting123
   (format PBKDF2$<iterasi>$<saltBase64>$<hashBase64>, lihat
   TerakarsaApp.API/Services/PasswordHasher.cs). Salt-nya acak, jadi hash di bawah
   TIDAK sama dengan hasil menjalankan tool itu lagi -- keduanya tetap cocok
   untuk password yang sama.

   User ini HANYA diberi module CUTTING: dashboard utama kosong untuknya, dan
   setelah login langsung diarahkan ke /cutting.

   Pola persis sql/inv/seed_71_user_gudang.sql (user 'gudang' / role WAREHOUSE).
   Idempotent: tidak menimpa password kalau user sudah ada.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = 'cutting')
    INSERT INTO Users (Username, Password, FullName, Role, IsActive, CreatedAt, home_route)
    VALUES ('cutting',
            'PBKDF2$210000$NkKFs3AT8vjqeCDePgb7Rg==$jJMyWvRRKQyc8VY+4LSqqD1aLvHMpnQiR5yDgHkfG6E=',
            'Admin Cutting', 'CUTTING', 1, GETDATE(), '/cutting');
GO

-- Pastikan role & landing benar walau baris sudah ada dari percobaan sebelumnya
-- (password TIDAK disentuh).
UPDATE Users
SET Role = 'CUTTING',
    home_route = '/cutting'
WHERE Username = 'cutting'
  AND (Role <> 'CUTTING' OR ISNULL(home_route, '') <> '/cutting');
GO

-- Akses module: hanya CUTTING.
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Username = 'cutting'
  AND m.Code = 'CUTTING'
  AND NOT EXISTS (SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id);
GO

SELECT u.Id, u.Username, u.FullName, u.Role, u.home_route,
       (SELECT COUNT(*) FROM UserModules um WHERE um.UserId = u.Id) AS JumlahModule
FROM Users u
WHERE u.Username = 'cutting';
GO
