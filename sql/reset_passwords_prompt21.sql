-- Prompt 21: reset semua password (migrasi SHA256 -> PBKDF2, tanpa jalur legacy).
-- Jalankan SETELAH alter_21_password_pbkdf2.sql (kolom perlu varchar(500) dulu
-- supaya hash PBKDF2 admin di bawah tidak terpotong).
-- 'RESET!' bukan format PBKDF2 valid -> PasswordHasher.Verify selalu false -> tidak bisa login.
UPDATE Users SET Password = 'RESET!';
GO

-- Ganti <HASH_ADMIN> dengan hasil: dotnet run --project tools/PasswordHashTool -- <password_baru>
UPDATE Users SET Password = '<HASH_ADMIN>' WHERE Username = 'admin';
GO

-- station_system sengaja ikut ter-reset (IsActive = 0, tidak pernah login).
