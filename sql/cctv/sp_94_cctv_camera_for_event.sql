/* =============================================================
   TMOS - Module CCTV (Prompt 94) - kamera untuk sebuah transaksi (scan)
   cctv.SIS_Camera_ForEvent
     result set 1: kamera hidup yang tertaut ke @ResourceId; kalau tidak ada,
                   yang tertaut ke @DivisionId. Urut sort_order, name.
     result set 2: kamera hidup LAIN di area yang sama dengan kamera pertama
                   (dropdown "Kamera lain di area ini"). Kosong kalau kamera
                   pertama tanpa area / tidak ada kamera.
   Hanya MEMBACA. Idempotent: CREATE OR ALTER.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE cctv.SIS_Camera_ForEvent
    @ResourceId INT = NULL,
    @DivisionId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @cams TABLE (
        camera_id  INT PRIMARY KEY,
        matched_by VARCHAR(10) NOT NULL
    );

    IF @ResourceId IS NOT NULL
        INSERT INTO @cams (camera_id, matched_by)
        SELECT DISTINCT c.camera_id, 'RESOURCE'
        FROM cctv.camera_links l
        JOIN cctv.cameras c ON c.camera_id = l.camera_id AND c.deleted_at IS NULL
        WHERE l.resource_id = @ResourceId AND l.deleted_at IS NULL;

    IF NOT EXISTS (SELECT 1 FROM @cams) AND @DivisionId IS NOT NULL
        INSERT INTO @cams (camera_id, matched_by)
        SELECT DISTINCT c.camera_id, 'DIVISION'
        FROM cctv.camera_links l
        JOIN cctv.cameras c ON c.camera_id = l.camera_id AND c.deleted_at IS NULL
        WHERE l.division_id = @DivisionId AND l.deleted_at IS NULL;

    -- result set 1
    SELECT
        c.camera_id  AS CameraId,
        c.name       AS Name,
        c.area       AS Area,
        c.mtx_path   AS MtxPath,
        x.matched_by AS MatchedBy
    FROM @cams x
    JOIN cctv.cameras c ON c.camera_id = x.camera_id
    ORDER BY c.sort_order, c.name;

    -- area kamera pertama
    DECLARE @Area NVARCHAR(50) = (
        SELECT TOP (1) c.area
        FROM @cams x
        JOIN cctv.cameras c ON c.camera_id = x.camera_id
        ORDER BY c.sort_order, c.name);

    -- result set 2
    SELECT
        c.camera_id AS CameraId,
        c.name      AS Name,
        c.area      AS Area,
        c.mtx_path  AS MtxPath,
        'AREA'      AS MatchedBy
    FROM cctv.cameras c
    WHERE c.deleted_at IS NULL
      AND @Area IS NOT NULL
      AND c.area = @Area
      AND NOT EXISTS (SELECT 1 FROM @cams x WHERE x.camera_id = c.camera_id)
    ORDER BY c.sort_order, c.name;
END
GO
