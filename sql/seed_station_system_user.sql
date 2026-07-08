-- User sistem untuk kolom created_by pada log yang dibuat dari perangkat stasiun
-- (endpoint api/station/* tidak punya JWT, jadi tidak ada UserId dari token login).
-- IsActive = 0 supaya user ini tidak bisa dipakai untuk login manual; password diisi
-- nilai acak yang tidak pernah dipakai untuk login.
-- Idempotent: aman dijalankan berulang.
--
-- SETELAH DIJALANKAN: catat Id yang muncul di hasil SELECT terakhir, lalu isikan ke
-- TerakarsaApp.API/appsettings.json -> "Station": { "SystemUserId": <Id> }.

IF NOT EXISTS (SELECT 1 FROM Users WHERE Username = 'station_system')
    INSERT INTO Users (Username, Password, FullName, Role, IsActive, CreatedAt)
    VALUES ('station_system', LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', '')), N'Station System', N'System', 0, GETDATE());
GO

SELECT Id, Username, FullName, Role, IsActive FROM Users WHERE Username = 'station_system';
GO
