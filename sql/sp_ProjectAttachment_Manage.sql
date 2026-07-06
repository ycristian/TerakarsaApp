-- Mutasi & pengambilan data project_attachments dalam satu SP sederhana
-- (tidak butuh full CRUD seperti resource lain): GETBYPROJECT, CREATE, DELETE.
-- Hapus = soft delete metadata saja, file fisik di storage dibiarkan (lihat IFileStorageService).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_ProjectAttachment_Manage
    @Action      VARCHAR(20),
    @Id          INT = NULL,
    @ProjectId   INT = NULL,
    @FileName    VARCHAR(255) = NULL,
    @FilePath    VARCHAR(500) = NULL,
    @FileSizeKb  INT = NULL,
    @FileType    VARCHAR(10) = NULL,
    @Description VARCHAR(255) = NULL,
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GETBYPROJECT'
    BEGIN
        SELECT project_attachment_id AS Id, project_id AS ProjectId,
               file_name AS FileName, file_path AS FilePath,
               file_size_kb AS FileSizeKb, file_type AS FileType,
               [description] AS Description,
               created_at AS CreatedAt, created_by AS CreatedBy
        FROM project_attachments
        WHERE project_id = @ProjectId AND deleted_at IS NULL
        ORDER BY sort_order ASC, project_attachment_id ASC;
    END

    ELSE IF @Action = 'CREATE'
    BEGIN
        DECLARE @NextSort INT = (
            SELECT ISNULL(MAX(sort_order), 0) + 1
            FROM project_attachments
            WHERE project_id = @ProjectId
        );

        INSERT INTO project_attachments (project_id, file_name, file_path, file_size_kb, file_type, [description], sort_order, created_at, created_by)
        VALUES (@ProjectId, @FileName, @FilePath, @FileSizeKb, @FileType, @Description, @NextSort, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE project_attachments
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE project_attachment_id = @Id AND deleted_at IS NULL;
    END
END;
GO
