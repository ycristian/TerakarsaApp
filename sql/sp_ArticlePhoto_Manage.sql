-- Mutasi & pengambilan data article_photos dalam satu SP sederhana
-- (sama seperti project_attachments): GETBYARTICLE, GETFIRSTFORPROJECT, CREATE, DELETE, SETPRIMARY.
-- GETFIRSTFORPROJECT: foto primary (atau foto pertama) dari artikel dengan article_id
-- terkecil pada project tsb -- dipakai untuk kolom Foto di Daftar Project.
-- Foto pertama yang diupload untuk sebuah artikel otomatis jadi is_primary = 1.
-- Hapus = soft delete metadata saja, file fisik di storage dibiarkan (lihat IFileStorageService).
-- Jika foto primary dihapus dan masih ada foto lain, foto berikutnya otomatis jadi primary.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ArticlePhoto_Manage
    @Action     VARCHAR(20),
    @Id         INT = NULL,
    @ArticleId  INT = NULL,
    @ProjectId  INT = NULL,
    @FileName   VARCHAR(255) = NULL,
    @FilePath   VARCHAR(500) = NULL,
    @FileSizeKb INT = NULL,
    @UserId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GETBYARTICLE'
    BEGIN
        SELECT article_photo_id AS Id, article_id AS ArticleId,
               file_name AS FileName, file_path AS FilePath, file_size_kb AS FileSizeKb,
               is_primary AS IsPrimary,
               created_at AS CreatedAt, created_by AS CreatedBy
        FROM article_photos
        WHERE article_id = @ArticleId AND deleted_at IS NULL
        ORDER BY sort_order ASC, article_photo_id ASC;
    END

    ELSE IF @Action = 'GETFIRSTFORPROJECT'
    BEGIN
        DECLARE @FirstArticleId INT = (
            SELECT TOP 1 article_id FROM articles
            WHERE project_id = @ProjectId AND deleted_at IS NULL
            ORDER BY article_id ASC
        );

        SELECT TOP 1 article_photo_id AS Id, article_id AS ArticleId,
               file_name AS FileName, file_path AS FilePath, file_size_kb AS FileSizeKb,
               is_primary AS IsPrimary,
               created_at AS CreatedAt, created_by AS CreatedBy
        FROM article_photos
        WHERE article_id = @FirstArticleId AND deleted_at IS NULL
        ORDER BY is_primary DESC, sort_order ASC, article_photo_id ASC;
    END

    ELSE IF @Action = 'CREATE'
    BEGIN
        DECLARE @NextSort INT = (
            SELECT ISNULL(MAX(sort_order), 0) + 1
            FROM article_photos
            WHERE article_id = @ArticleId
        );
        DECLARE @IsFirst BIT = CASE
            WHEN EXISTS (SELECT 1 FROM article_photos WHERE article_id = @ArticleId AND deleted_at IS NULL)
            THEN 0 ELSE 1
        END;

        INSERT INTO article_photos (article_id, file_name, file_path, file_size_kb, sort_order, is_primary, created_at, created_by)
        VALUES (@ArticleId, @FileName, @FilePath, @FileSizeKb, @NextSort, @IsFirst, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        DECLARE @DeletedArticleId INT, @WasPrimary BIT;
        SELECT @DeletedArticleId = article_id, @WasPrimary = is_primary
        FROM article_photos WHERE article_photo_id = @Id AND deleted_at IS NULL;

        UPDATE article_photos
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE article_photo_id = @Id AND deleted_at IS NULL;

        IF @WasPrimary = 1
        BEGIN
            UPDATE article_photos
            SET is_primary = 1
            WHERE article_photo_id = (
                SELECT TOP 1 article_photo_id FROM article_photos
                WHERE article_id = @DeletedArticleId AND deleted_at IS NULL
                ORDER BY sort_order ASC, article_photo_id ASC
            );
        END
    END

    ELSE IF @Action = 'SETPRIMARY'
    BEGIN
        DECLARE @TargetArticleId INT = (SELECT article_id FROM article_photos WHERE article_photo_id = @Id AND deleted_at IS NULL);

        BEGIN TRAN;
        UPDATE article_photos SET is_primary = 0
        WHERE article_id = @TargetArticleId AND deleted_at IS NULL;

        UPDATE article_photos SET is_primary = 1
        WHERE article_photo_id = @Id AND deleted_at IS NULL;
        COMMIT TRAN;
    END
END;
GO
