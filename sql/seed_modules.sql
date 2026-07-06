-- Jalankan setelah modules_schema.sql dieksekusi.
-- User1 & User2 harus sudah dibuat lewat halaman "Kelola User" (Role = User)
-- sebelum bagian assignment di bawah dijalankan, supaya password ter-hash dengan benar.

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'products')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('products', 'Produk', 'Production', 'products', 'fe fe-package', 10, 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'counter')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('counter', 'Counter', 'Production', 'counter', 'fe fe-hash', 20, 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'users')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('users', 'Kelola User', 'App Setting', 'users', 'fe fe-users', 30, 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'module-setting')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('module-setting', 'Module Setting', 'App Setting', 'module-setting', 'fe fe-settings', 40, 1, GETDATE());

IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'module-access')
    INSERT INTO Modules (Code, Name, Category, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('module-access', 'Module Access', 'App Setting', 'module-access', 'fe fe-lock', 50, 1, GETDATE());
GO

-- Assignment module bisnis: User1 -> Produk + Counter, User2 -> Counter saja.
-- Aman dijalankan berulang (idempotent).

INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Username = 'User1'
  AND m.Code IN ('products', 'counter')
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );

INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Username = 'User2'
  AND m.Code = 'counter'
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id
  );
GO

-- Bootstrap privilege App Setting (Kelola User, Module Setting, Module Access)
-- ke Admin pertama yang ada, supaya ada minimal 1 admin yang bisa membuka
-- halaman Module Access untuk mengatur privilege admin lain. Idempotent.

INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT a.Id, m.Id, GETDATE()
FROM (SELECT TOP 1 Id FROM Users WHERE Role = 'Admin' ORDER BY Id) a
CROSS JOIN Modules m
WHERE m.Code IN ('users', 'module-setting', 'module-access')
  AND NOT EXISTS (
      SELECT 1 FROM UserModules um WHERE um.UserId = a.Id AND um.ModuleId = m.Id
  );
GO
