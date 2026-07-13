-- Prompt 21 follow-up: reset_passwords_prompt21.sql sempat dijalankan dengan
-- placeholder '<HASH_ADMIN>' belum diganti, jadi tidak ada user yang bisa login
-- (admin tersimpan literal '<HASH_ADMIN>', user lain masih marker 'RESET!').
-- Set ulang semua password ke 'Admin123' (hash dari:
-- dotnet run --project tools/PasswordHashTool -- Admin123).
UPDATE Users
SET Password = 'PBKDF2$210000$HDbCGMvuAgbMuqY4GrrFpg==$6FHw92QEFqTEfaSfloJcyqVh3CuUMkpM0FwI6Q960jo='
WHERE Username IN ('admin', 'user1', 'user2', 'ivander', 'station_system');
GO
