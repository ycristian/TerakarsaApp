/* =============================================================
   Prompt 71 - landing per role.

   Sebelum ini TMOS tidak punya mekanisme "halaman awal per role": Role di
   dbo.Users hanya varchar ('Admin' / 'User'), bukan tabel, dan Login.razor
   selalu mengarahkan ke "/". Role baru WAREHOUSE (tampilan "Admin Gudang")
   hanya memegang module INV_THREAD, jadi dashboard utama kosong untuknya.

   Solusi sesuai prompt: kolom home_route di dbo.Users (role bukan tabel).
   Nilainya dipakai Login.razor lewat claim JWT "home_route".

   Role WAREHOUSE tidak perlu diisi satu-satu: SIS_User_GetByUsername
   mem-fallback ke '/gudang/benang' untuk role itu bila home_route NULL,
   jadi user baru yang dibuat dari halaman User Management langsung benar.

   Idempotent. HANYA menambah kolom (tanpa recreate table) dan mengubah
   dua SP auth yang sudah ada -- tidak ada data yang dipindahkan.
   ============================================================= */

IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.Users') AND name = 'home_route')
    ALTER TABLE dbo.Users ADD home_route VARCHAR(100) NULL;
GO

-- Dipakai AuthService.LoginAsync. Kolom HomeRoute ditambahkan Prompt 71:
-- halaman awal setelah login. Fallback per role ditegakkan di SP (bukan di C#).
CREATE OR ALTER PROCEDURE SIS_User_GetByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Username, Password, FullName, Role, IsActive,
           ISNULL(NULLIF(LTRIM(RTRIM(ISNULL(home_route,''))), ''),
                  CASE WHEN Role = 'WAREHOUSE' THEN '/gudang/benang' END) AS HomeRoute
    FROM Users
    WHERE Username = @Username
      AND IsActive = 1;
END;
GO

-- Prompt 71: GET ikut mengembalikan HomeRoute supaya claim "home_route"
-- tidak hilang setiap kali access token di-refresh (rotasi 15 menit).
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
                   CASE WHEN u.Role = 'WAREHOUSE' THEN '/gudang/benang' END) AS HomeRoute,
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
