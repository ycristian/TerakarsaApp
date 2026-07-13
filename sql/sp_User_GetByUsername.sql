-- Prompt 21: dipakai AuthService.LoginAsync. Pencocokan password pindah ke C#
-- (PasswordHasher.Verify), jadi SP ini tidak menerima/mencocokkan password.
CREATE OR ALTER PROCEDURE SIS_User_GetByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Id, Username, Password, FullName, Role, IsActive
    FROM Users
    WHERE Username = @Username
      AND IsActive = 1;
END;
GO
