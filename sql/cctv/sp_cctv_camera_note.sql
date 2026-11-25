/* =============================================================
   TMOS - Module CCTV - Stored procedure catatan kejadian rekaman
   cctv.SIS_CameraNote_Manage : CREATE | UPDATE | DELETE
   cctv.SIS_CameraNote_List   : kejadian dalam rentang waktu (opsional satu kamera), urut waktu
   cctv.SIS_CameraNote_Tags   : tag yang pernah dipakai (saran isian), paling sering dulu

   Waktu (@EventAt, @From, @To) = WIB tanpa offset.
   Hanya MEMBACA dbo.Users (nama pembuat).
   Jalankan sql/cctv/alter_cctv_camera_notes.sql lebih dulu.
   Idempotent: CREATE OR ALTER.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE cctv.SIS_CameraNote_Manage
    @Action   VARCHAR(20),          -- CREATE | UPDATE | DELETE
    @NoteId   INT = NULL,
    @CameraId INT = NULL,
    @EventAt  DATETIME2(0) = NULL,
    @Tag      NVARCHAR(30) = NULL,
    @Note     NVARCHAR(500) = NULL,
    @UserId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Tag  = NULLIF(LTRIM(RTRIM(ISNULL(@Tag, N''))), N'');
    SET @Note = NULLIF(LTRIM(RTRIM(ISNULL(@Note, N''))), N'');

    IF @UserId IS NULL
    BEGIN
        RAISERROR('User wajib diisi.', 16, 1);
        RETURN;
    END

    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        IF @EventAt IS NULL
        BEGIN
            RAISERROR('Waktu kejadian wajib diisi.', 16, 1);
            RETURN;
        END

        -- Jam WIB server, tidak bergantung zona waktu Windows server. Toleransi 1 menit.
        IF @EventAt > DATEADD(MINUTE, 1, CAST(SWITCHOFFSET(SYSDATETIMEOFFSET(), '+07:00') AS DATETIME2(0)))
        BEGIN
            RAISERROR('Waktu kejadian tidak boleh di masa depan.', 16, 1);
            RETURN;
        END

        IF @Note IS NULL
        BEGIN
            RAISERROR('Catatan kejadian wajib diisi.', 16, 1);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM cctv.cameras WHERE camera_id = @CameraId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kamera tidak ditemukan.', 16, 1);
            RETURN;
        END

        INSERT INTO cctv.camera_notes (camera_id, event_at, tag, note, created_by)
        VALUES (@CameraId, @EventAt, @Tag, @Note, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM cctv.camera_notes WHERE note_id = @NoteId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Catatan kejadian tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- Kamera TIDAK ikut diubah: catatan melekat ke rekaman kamera itu.
    IF @Action = 'UPDATE'
    BEGIN
        UPDATE cctv.camera_notes
        SET event_at   = @EventAt,
            tag        = @Tag,
            note       = @Note,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE note_id = @NoteId;

        SELECT @NoteId AS Value;
        RETURN;
    END

    IF @Action = 'DELETE'
    BEGIN
        UPDATE cctv.camera_notes
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE note_id = @NoteId;

        SELECT @NoteId AS Value;
        RETURN;
    END

    RAISERROR('Action tidak dikenal.', 16, 1);
END
GO

-- [@From, @To) WIB. @CameraId NULL = semua kamera hidup.
CREATE OR ALTER PROCEDURE cctv.SIS_CameraNote_List
    @From     DATETIME2(0),
    @To       DATETIME2(0),
    @CameraId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        n.note_id    AS NoteId,
        n.camera_id  AS CameraId,
        c.name       AS CameraName,
        c.area       AS Area,
        c.mtx_path   AS MtxPath,
        n.event_at   AS EventAt,
        n.tag        AS Tag,
        n.note       AS Note,
        CAST(COALESCE(u.FullName, u.Username) AS NVARCHAR(150)) AS CreatedByName,
        n.created_at AS CreatedAt
    FROM cctv.camera_notes n
    JOIN cctv.cameras c ON c.camera_id = n.camera_id AND c.deleted_at IS NULL
    LEFT JOIN dbo.Users u ON u.Id = n.created_by
    WHERE n.deleted_at IS NULL
      AND n.event_at >= @From AND n.event_at < @To
      AND (@CameraId IS NULL OR n.camera_id = @CameraId)
    ORDER BY n.event_at, c.sort_order, n.note_id;
END
GO

CREATE OR ALTER PROCEDURE cctv.SIS_CameraNote_Tags
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (30) tag AS Value
    FROM cctv.camera_notes
    WHERE deleted_at IS NULL AND tag IS NOT NULL
    GROUP BY tag
    ORDER BY COUNT(*) DESC, MAX(event_at) DESC;
END
GO
