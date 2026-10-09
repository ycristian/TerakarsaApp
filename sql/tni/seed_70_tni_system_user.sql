-- User sistem untuk kolom created_by semua mutasi dari PERANGKAT TNI
-- (endpoint api/tni/* memakai header X-Tni-Token, tanpa JWT, jadi tidak ada
-- UserId dari token login).
--
-- Petugas yang sebenarnya mengerjakan DISIMPAN TERPISAH di kolom *_petugas_id
-- (tni.petugas) -- user sistem ini hanya pengisi created_by, sesuai aturan
-- CLAUDE.md "created_by SELALU user id".
--
-- IsActive = 0 supaya tidak bisa dipakai login manual; password nilai acak.
-- Idempotent: aman dijalankan berulang.
--
-- SETELAH DIJALANKAN: catat Id dari SELECT terakhir, isikan ke
-- TerakarsaApp.API/appsettings.json -> "Tni": { "SystemUserId": <Id> }.

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = 'tni_system')
    INSERT INTO Users (Username, Password, FullName, Role, IsActive, CreatedAt)
    VALUES ('tni_system', LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', '')), N'TNI System', N'System', 0, GETDATE());
GO

SELECT Id, Username, FullName, Role, IsActive FROM Users WHERE Username = 'tni_system';
GO
