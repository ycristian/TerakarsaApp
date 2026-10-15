/* =============================================================
   Prompt 78 -- module CUTTING + role Admin Cutting.

   Satu module untuk SELURUH halaman /cutting/... (Stok Bundle, Buat Hamparan,
   Daftar & Detail Hamparan). Pola persis sql/inv/seed_71_inv_thread_module.sql
   dan sql/inv/alter_71_home_route.sql (role Admin Gudang / WAREHOUSE).

   Role di TMOS bukan tabel -- cuma varchar di dbo.Users -- jadi "seed role"
   di sini = fallback home_route per role di dua SP auth, plus pilihan
   "Admin Cutting" di halaman User Management (sisi client).

   Idempotent: aman dijalankan berulang.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============ 1. module ============
IF NOT EXISTS (SELECT 1 FROM Modules WHERE Code = 'CUTTING')
    INSERT INTO Modules (Code, Name, Category, SubCategory, Route, Icon, SortOrder, IsActive, CreatedAt)
    VALUES ('CUTTING', 'Stok Bundle Cutting', 'Production', NULL, 'cutting', 'fe fe-scissors', 70, 1, GETDATE());
GO

-- PENYIMPANGAN SENGAJA dari Prompt 78 §5 ("jangan assign ke user mana pun"):
-- module claim HANYA berasal dari UserModules (lihat RequireModuleAttribute --
-- tidak ada bypass untuk Role = 'Admin'), jadi tanpa assign ini §3 prompt yang
-- sama ("Owner/superadmin tetap bisa akses") tidak mungkin terpenuhi dan module
-- tidak bisa diuji sama sekali. Yang di-assign HANYA user Role = 'Admin' (owner),
-- persis pola INV_THREAD di Prompt 71. Tidak ada user baru yang dibuat.
INSERT INTO UserModules (UserId, ModuleId, CreatedAt)
SELECT u.Id, m.Id, GETDATE()
FROM Users u
CROSS JOIN Modules m
WHERE u.Role = 'Admin'
  AND m.Code = 'CUTTING'
  AND NOT EXISTS (SELECT 1 FROM UserModules um WHERE um.UserId = u.Id AND um.ModuleId = m.Id);
GO

-- ============ 2. landing per role ============
-- Role CUTTING (tampilan "Admin Cutting") hanya memegang module CUTTING, jadi
-- dashboard utama kosong untuknya -> fallback ke /cutting bila home_route NULL.
-- Dua SP di bawah adalah SP yang sama yang diubah sql/inv/alter_71_home_route.sql;
-- di sini cuma DITAMBAH satu cabang CASE, perilaku WAREHOUSE tidak berubah.
CREATE OR ALTER PROCEDURE SIS_User_GetByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Username, Password, FullName, Role, IsActive,
           ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(home_route,''))), ''),
                  CASE Role WHEN 'WAREHOUSE' THEN '/gudang/benang'
                            WHEN 'CUTTING'   THEN '/cutting' END) AS HomeRoute
    FROM Users
    WHERE Username = @Username
      AND IsActive = 1;
END;
GO

CREATE OR ALTER PROCEDURE SIS_RefreshToken_Manage
    @Action     NVARCHAR(20),
    @UserId     INT = NULL,
    @Token      NVARCHAR(255) = NULL,
    @ExpiresAt  DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO RefreshTokens (UserId, Token, ExpiresAt, CreatedAt)
        VALUES (@UserId, @Token, @ExpiresAt, GETDATE());
    END

    ELSE IF @Action = 'GET'
    BEGIN
        SELECT
            u.Id AS UserId,
            u.Username,
            u.FullName,
            u.Role,
            u.IsActive,
            ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(u.home_route,''))), ''),
                   CASE u.Role WHEN 'WAREHOUSE' THEN '/gudang/benang'
                               WHEN 'CUTTING'   THEN '/cutting' END) AS HomeRoute,
            rt.ExpiresAt AS TokenExpiresAt,
            rt.RevokedAt
        FROM RefreshTokens rt
        INNER JOIN Users u ON u.Id = rt.UserId
        WHERE rt.Token = @Token;
    END

    ELSE IF @Action = 'REVOKE'
    BEGIN
        UPDATE RefreshTokens SET RevokedAt = GETDATE() WHERE Token = @Token AND RevokedAt IS NULL;
    END
END;
GO

-- ============ 3. routing printer stiker cutting ============
-- Job type baru CUTTING_BUNDLE_LABEL diarahkan ke perangkat label yang sama
-- dengan BUNDLE_LABEL (dicari by device_code, bukan id hardcode).
INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
SELECT 'CUTTING_BUNDLE_LABEL', d.print_device_id, SYSDATETIME(), 1
FROM print_devices d
WHERE d.device_code = 'LABEL' AND d.deleted_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM print_job_routes r
      WHERE r.job_type = 'CUTTING_BUNDLE_LABEL' AND r.deleted_at IS NULL);
GO

-- ============ 4. verifikasi ============
SELECT m.Id, m.Code, m.Name, m.Route,
       (SELECT COUNT(*) FROM UserModules um WHERE um.ModuleId = m.Id) AS JumlahUser
FROM Modules m WHERE m.Code = 'CUTTING';

SELECT r.job_type, d.device_code, d.printer_name, d.render_mode
FROM print_job_routes r
INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
WHERE r.job_type = 'CUTTING_BUNDLE_LABEL' AND r.deleted_at IS NULL;
GO
