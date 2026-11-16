/* =============================================================
   TMOS - Module CCTV (Prompt 91) - Stored procedure master kamera
   cctv.SIS_Camera_Manage  : CREATE | UPDATE | DELETE | SYNC_ADD | SET_LINKS
   cctv.SIS_Camera_List    : daftar kamera + ringkasan tautan
   cctv.SIS_Camera_Get     : detail (result set 1) + tautan (result set 2)
   cctv.SIS_Camera_Lookup  : resource & divisi hidup untuk form

   Hanya MEMBACA dbo.resources & dbo.divisions.
   Idempotent: CREATE OR ALTER.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE cctv.SIS_Camera_Manage
    @Action      VARCHAR(20),          -- CREATE | UPDATE | DELETE | SYNC_ADD | SET_LINKS
    @CameraId    INT = NULL,
    @Name        NVARCHAR(100) = NULL,
    @Area        NVARCHAR(50) = NULL,
    @MtxPath     NVARCHAR(50) = NULL,
    @IpAddress   NVARCHAR(45) = NULL,
    @SerialNo    NVARCHAR(30) = NULL,
    @NvrChannel  INT = NULL,
    @SortOrder   INT = NULL,
    @IsVisible   BIT = NULL,
    @Note        NVARCHAR(200) = NULL,
    @ResourceIds NVARCHAR(MAX) = NULL, -- SET_LINKS: id dipisah koma, boleh kosong
    @DivisionIds NVARCHAR(MAX) = NULL, -- SET_LINKS: id dipisah koma, boleh kosong
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Name      = NULLIF(LTRIM(RTRIM(ISNULL(@Name, N''))), N'');
    SET @Area      = NULLIF(LTRIM(RTRIM(ISNULL(@Area, N''))), N'');
    SET @MtxPath   = NULLIF(LTRIM(RTRIM(ISNULL(@MtxPath, N''))), N'');
    SET @IpAddress = NULLIF(LTRIM(RTRIM(ISNULL(@IpAddress, N''))), N'');
    SET @SerialNo  = NULLIF(LTRIM(RTRIM(ISNULL(@SerialNo, N''))), N'');
    SET @Note      = NULLIF(LTRIM(RTRIM(ISNULL(@Note, N''))), N'');

    IF @UserId IS NULL
    BEGIN
        RAISERROR('User wajib diisi.', 16, 1);
        RETURN;
    END

    -- ---------- SYNC_ADD: path dari server MediaMTX ----------
    -- Path yang sudah ada (atau tidak valid) dilewati TANPA error -> Value = 0.
    IF @Action = 'SYNC_ADD'
    BEGIN
        IF @MtxPath IS NULL OR @MtxPath LIKE N'%[^A-Za-z0-9_-]%'
           OR EXISTS (SELECT 1 FROM cctv.cameras WHERE mtx_path = @MtxPath AND deleted_at IS NULL)
        BEGIN
            SELECT CAST(0 AS INT) AS Value;
            RETURN;
        END

        INSERT INTO cctv.cameras (name, mtx_path, sort_order, is_visible, created_by)
        VALUES (@MtxPath, @MtxPath,
                ISNULL((SELECT MAX(sort_order) FROM cctv.cameras WHERE deleted_at IS NULL), 0) + 1,
                1, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    -- ---------- validasi bersama CREATE / UPDATE ----------
    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        IF @Name IS NULL
        BEGIN
            RAISERROR('Nama kamera wajib diisi.', 16, 1);
            RETURN;
        END

        IF @NvrChannel IS NOT NULL AND @NvrChannel < 0
        BEGIN
            RAISERROR('Channel NVR tidak boleh minus.', 16, 1);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        IF @MtxPath IS NULL
        BEGIN
            RAISERROR('Path MediaMTX wajib diisi.', 16, 1);
            RETURN;
        END

        IF @MtxPath LIKE N'%[^A-Za-z0-9_-]%'
        BEGIN
            RAISERROR('Path hanya boleh berisi huruf, angka, garis bawah (_), dan tanda hubung (-).', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM cctv.cameras WHERE mtx_path = @MtxPath AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Path "%s" sudah dipakai kamera lain.', 16, 1, @MtxPath);
            RETURN;
        END

        INSERT INTO cctv.cameras (name, area, mtx_path, ip_address, serial_no, nvr_channel,
                                  sort_order, is_visible, note, created_by)
        VALUES (@Name, @Area, @MtxPath, @IpAddress, @SerialNo, @NvrChannel,
                ISNULL(@SortOrder, 0), ISNULL(@IsVisible, 1), @Note, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
        RETURN;
    END

    -- Aksi di bawah ini butuh kamera hidup.
    IF NOT EXISTS (SELECT 1 FROM cctv.cameras WHERE camera_id = @CameraId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Kamera tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- Path TIDAK ikut diubah di UPDATE: path hanya diisi saat tambah manual / sync.
    IF @Action = 'UPDATE'
    BEGIN
        UPDATE cctv.cameras
        SET name        = @Name,
            area        = @Area,
            ip_address  = @IpAddress,
            serial_no   = @SerialNo,
            nvr_channel = @NvrChannel,
            sort_order  = ISNULL(@SortOrder, sort_order),
            is_visible  = ISNULL(@IsVisible, is_visible),
            note        = @Note,
            updated_at  = SYSDATETIME(),
            updated_by  = @UserId
        WHERE camera_id = @CameraId;

        SELECT @CameraId AS Value;
        RETURN;
    END

    IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;

        UPDATE cctv.camera_links
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE camera_id = @CameraId AND deleted_at IS NULL;

        UPDATE cctv.cameras
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE camera_id = @CameraId;

        COMMIT;

        SELECT @CameraId AS Value;
        RETURN;
    END

    -- ---------- SET_LINKS: ganti seluruh tautan satu kamera ----------
    IF @Action = 'SET_LINKS'
    BEGIN
        DECLARE @res TABLE (id INT PRIMARY KEY);
        DECLARE @div TABLE (id INT PRIMARY KEY);

        IF EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(@ResourceIds, N''), N',')
                   WHERE LTRIM(RTRIM(value)) <> N'' AND TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NULL)
           OR EXISTS (SELECT 1 FROM STRING_SPLIT(ISNULL(@DivisionIds, N''), N',')
                      WHERE LTRIM(RTRIM(value)) <> N'' AND TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NULL)
        BEGIN
            RAISERROR('Daftar station / divisi tidak valid.', 16, 1);
            RETURN;
        END

        INSERT INTO @res (id)
        SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(ISNULL(@ResourceIds, N''), N',')
        WHERE LTRIM(RTRIM(value)) <> N'';

        INSERT INTO @div (id)
        SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(ISNULL(@DivisionIds, N''), N',')
        WHERE LTRIM(RTRIM(value)) <> N'';

        IF EXISTS (SELECT 1 FROM @res x
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.resources r
                                     WHERE r.resource_id = x.id AND r.deleted_at IS NULL))
        BEGIN
            RAISERROR('Ada station / line yang tidak ditemukan atau sudah dihapus.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @div x
                   WHERE NOT EXISTS (SELECT 1 FROM dbo.divisions d
                                     WHERE d.division_id = x.id AND d.deleted_at IS NULL))
        BEGIN
            RAISERROR('Ada divisi yang tidak ditemukan atau sudah dihapus.', 16, 1);
            RETURN;
        END

        BEGIN TRAN;

        -- lepas tautan yang tidak ada lagi di daftar
        UPDATE l
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        FROM cctv.camera_links l
        WHERE l.camera_id = @CameraId AND l.deleted_at IS NULL
          AND (   (l.resource_id IS NOT NULL AND l.resource_id NOT IN (SELECT id FROM @res))
               OR (l.division_id IS NOT NULL AND l.division_id NOT IN (SELECT id FROM @div)));

        -- tambah tautan baru
        INSERT INTO cctv.camera_links (camera_id, resource_id, division_id, created_by)
        SELECT @CameraId, x.id, NULL, @UserId
        FROM @res x
        WHERE NOT EXISTS (SELECT 1 FROM cctv.camera_links l
                          WHERE l.camera_id = @CameraId AND l.resource_id = x.id AND l.deleted_at IS NULL);

        INSERT INTO cctv.camera_links (camera_id, resource_id, division_id, created_by)
        SELECT @CameraId, NULL, x.id, @UserId
        FROM @div x
        WHERE NOT EXISTS (SELECT 1 FROM cctv.camera_links l
                          WHERE l.camera_id = @CameraId AND l.division_id = x.id AND l.deleted_at IS NULL);

        COMMIT;

        SELECT @CameraId AS Value;
        RETURN;
    END

    RAISERROR('Action tidak dikenal.', 16, 1);
END
GO

CREATE OR ALTER PROCEDURE cctv.SIS_Camera_List
    @OnlyVisible BIT = 0,
    @Area        NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        c.camera_id   AS CameraId,
        c.name        AS Name,
        c.area        AS Area,
        c.mtx_path    AS MtxPath,
        c.ip_address  AS IpAddress,
        c.serial_no   AS SerialNo,
        c.nvr_channel AS NvrChannel,
        c.sort_order  AS SortOrder,
        c.is_visible  AS IsVisible,
        c.note        AS Note,
        (SELECT STRING_AGG(CAST(r.resource_name AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY r.resource_name)
         FROM cctv.camera_links l
         JOIN dbo.resources r ON r.resource_id = l.resource_id
         WHERE l.camera_id = c.camera_id AND l.deleted_at IS NULL) AS ResourceNames,
        (SELECT STRING_AGG(CAST(d.division_name AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY d.division_name)
         FROM cctv.camera_links l
         JOIN dbo.divisions d ON d.division_id = l.division_id
         WHERE l.camera_id = c.camera_id AND l.deleted_at IS NULL) AS DivisionNames
    FROM cctv.cameras c
    WHERE c.deleted_at IS NULL
      AND (@OnlyVisible = 0 OR c.is_visible = 1)
      AND (@Area IS NULL OR c.area = @Area)
    ORDER BY c.sort_order, c.name;
END
GO

CREATE OR ALTER PROCEDURE cctv.SIS_Camera_Get
    @CameraId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- result set 1: detail kamera
    SELECT
        c.camera_id   AS CameraId,
        c.name        AS Name,
        c.area        AS Area,
        c.mtx_path    AS MtxPath,
        c.ip_address  AS IpAddress,
        c.serial_no   AS SerialNo,
        c.nvr_channel AS NvrChannel,
        c.sort_order  AS SortOrder,
        c.is_visible  AS IsVisible,
        c.note        AS Note
    FROM cctv.cameras c
    WHERE c.camera_id = @CameraId AND c.deleted_at IS NULL;

    -- result set 2: tautan hidup
    SELECT
        l.camera_link_id AS CameraLinkId,
        l.resource_id    AS ResourceId,
        r.resource_name  AS ResourceName,
        l.division_id    AS DivisionId,
        d.division_name  AS DivisionName
    FROM cctv.camera_links l
    JOIN cctv.cameras c ON c.camera_id = l.camera_id AND c.deleted_at IS NULL
    LEFT JOIN dbo.resources r ON r.resource_id = l.resource_id
    LEFT JOIN dbo.divisions d ON d.division_id = l.division_id
    WHERE l.camera_id = @CameraId AND l.deleted_at IS NULL
    ORDER BY CASE WHEN l.resource_id IS NOT NULL THEN 0 ELSE 1 END, r.resource_name, d.division_name;
END
GO

-- Satu result set: Kind = RESOURCE | DIVISION. GroupName = nama divisi resource.
CREATE OR ALTER PROCEDURE cctv.SIS_Camera_Lookup
AS
BEGIN
    SET NOCOUNT ON;

    SELECT Kind, Id, Name, GroupName
    FROM (
        SELECT 'RESOURCE' AS Kind,
               r.resource_id AS Id,
               CAST(r.resource_name AS NVARCHAR(150)) AS Name,
               CAST(d.division_name AS NVARCHAR(150)) AS GroupName,
               0 AS SortKind
        FROM dbo.resources r
        JOIN dbo.divisions d ON d.division_id = r.division_id
        WHERE r.deleted_at IS NULL AND r.is_active = 1
        UNION ALL
        SELECT 'DIVISION', d.division_id, CAST(d.division_name AS NVARCHAR(150)), CAST(NULL AS NVARCHAR(150)), 1
        FROM dbo.divisions d
        WHERE d.deleted_at IS NULL
    ) x
    ORDER BY SortKind, GroupName, Name;
END
GO
