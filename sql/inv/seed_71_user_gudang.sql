/* =============================================================
   Prompt 71 - user Admin Gudang.

   Username  : gudang
   Password   : gudang123   <-- GANTI setelah login pertama
   Role       : WAREHOUSE   (tampilan "Admin Gudang" di halaman User Management)
   home_route : /gudang/benang

   Hash dibuat dengan fungsi yang sama seperti user lain:
     dotnet run --project tools/PasswordHashTool -- gudang123
   (format PBKDF2$<iterasi>$<saltBase64>$<hashBase64>, lihat
   TerakarsaApp.API/Services/PasswordHasher.cs). Salt-nya acak, jadi hash
   di bawah TIDAK sama dengan hasil menjalankan tool itu lagi -- keduanya
   tetap cocok untuk password yang sama.

   User ini HANYA diberi module INV_THREAD: dashboard utama kosong untuknya,
   dan setelah login langsung diarahkan ke /gudang/benang.

   Idempotent: tidak menimpa password kalau user sudah ada.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = 'gudang')
    INSERT INTO Users (Username, Password, FullName, Role, IsActive, CreatedAt, home_route)
    VALUES ('gudang',
            'PBKDF2$210000$AhDUizeeyLflCDsPJnmp0w==$mLPtYTxJgV1FQRzVYaaYTt1aVwy95ZqJgVUTmwq0jUs=',
            'Admin Gudang', 'WAREHOUSE', 1, GETDATE(), '/gudang/benang');
GO

-- Pastikan role & landing benar walau baris sudah ada dari percobaan sebelumnya
-- (password TIDAK disentuh).
UPDATE Users
SET Role = 'WAREHOUSE',
    home_route = '/gudang/benang'
WHERE Username = 'gudang'
  AND (Role <> 'WAREHOUSE' OR ISNULL(home_route,'') <> '/gudang/benang');
GO

-- Akses module: hanya INV_THREAD.
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Username = 'gudang'
  AND m.Code = 'INV_THREAD'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO

SELECT u.Id, u.Username, u.FullName, u.Role, u.home_route,
       (SELECT COUNT(*) FROM UserModules um WHERE um.UserId = u.Id) AS JumlahModule
FROM Users u
WHERE u.Username = 'gudang';
GO
