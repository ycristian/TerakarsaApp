CREATE TABLE RefreshTokens (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    UserId INT NOT NULL,
    Token NVARCHAR(255) NOT NULL,
    ExpiresAt DATETIME NOT NULL,
    CreatedAt DATETIME NOT NULL DEFAULT GETDATE(),
    RevokedAt DATETIME NULL,
    CONSTRAINT FK_RefreshTokens_Users FOREIGN KEY (UserId) REFERENCES Users(Id)
);

CREATE INDEX IX_RefreshTokens_Token ON RefreshTokens(Token);
GO

CREATE PROCEDURE SIS_RefreshToken_Manage
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
