/* =============================================================
   Module Stok Benang (Prompt 75) -- SP BACA untuk riwayat, ringkasan
   landing, matriks lokasi, dan pemakaian per project.

   TIDAK ADA SP TULIS di file ini.

   ANSI_NULLS / QUOTED_IDENTIFIER wajib ON (filtered index di tabel inv.*).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================
-- RIWAYAT MOVEMENT (paged + filter)
-- TotalCount dibawa di tiap baris (pola sama dengan SIS_ThreadItem_List).
-- @MovementTypes: daftar dipisah koma, mis. 'ISSUE,ADJUST'. NULL = semua.
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadMovement_List
    @Dari           DATETIME2 = NULL,      -- NULL = 7 hari terakhir
    @Sampai         DATETIME2 = NULL,
    @MovementTypes  VARCHAR(300) = NULL,
    @ReasonCode     VARCHAR(30) = NULL,
    @ItemId         INT = NULL,
    @LocationId     INT = NULL,            -- cocok sebagai rak asal ATAU tujuan
    @ResourceId     INT = NULL,
    @ProjectId      INT = NULL,
    @CreatedBy      INT = NULL,
    @PageNumber     INT = 1,
    @PageSize       INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @PageNumber IS NULL OR @PageNumber < 1 SET @PageNumber = 1;
    IF @PageSize IS NULL OR @PageSize < 1 OR @PageSize > 10000 SET @PageSize = 50;

    IF @Dari IS NULL SET @Dari = DATEADD(DAY, -7, CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2));
    IF @Sampai IS NULL SET @Sampai = SYSDATETIME();

    -- Batas atas dibuat inklusif sampai akhir hari kalau pemanggil mengirim tanggal saja.
    IF CAST(@Sampai AS TIME) = '00:00:00' SET @Sampai = DATEADD(DAY, 1, @Sampai);

    DECLARE @Types TABLE (movement_type VARCHAR(20) PRIMARY KEY);
    IF @MovementTypes IS NOT NULL AND LTRIM(RTRIM(@MovementTypes)) <> ''
        INSERT INTO @Types (movement_type)
        SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(@MovementTypes, ',')
        WHERE LTRIM(RTRIM(value)) <> '';

    DECLARE @AdaFilterType BIT = CASE WHEN EXISTS (SELECT 1 FROM @Types) THEN 1 ELSE 0 END;

    ;WITH src AS (
        SELECT m.thread_movement_id,
               m.movement_type,
               m.created_at,
               m.thread_item_id,
               i.sku_code, i.color_name, i.color_code,
               t.name AS type_name, b.name AS brand_name,
               c.cone_code,
               lf.code AS from_code, lt.code AS to_code,
               m.qty_whole, m.weight_gram,
               m.resource_id, r.resource_name,
               m.project_id, p.project_name, p.no_po,
               m.reason_code, rc.name AS reason_name,
               m.note,
               m.created_by, u.FullName AS created_by_name,
               m.opname_line_id,
               os.session_no AS opname_session_no,
               os.thread_opname_session_id AS opname_session_id
        FROM inv.thread_movements m
        INNER JOIN inv.thread_items i  ON i.thread_item_id = m.thread_item_id
        INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
        INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
        LEFT JOIN inv.thread_split_cones c  ON c.thread_split_cone_id = m.thread_split_cone_id
        LEFT JOIN inv.thread_locations lf   ON lf.thread_location_id = m.from_location_id
        LEFT JOIN inv.thread_locations lt   ON lt.thread_location_id = m.to_location_id
        LEFT JOIN dbo.resources r           ON r.resource_id = m.resource_id
        LEFT JOIN dbo.projects p            ON p.project_id = m.project_id
        LEFT JOIN inv.thread_reason_codes rc ON rc.code = m.reason_code
        LEFT JOIN dbo.Users u               ON u.Id = m.created_by
        LEFT JOIN inv.thread_opname_lines ol ON ol.thread_opname_line_id = m.opname_line_id
        LEFT JOIN inv.thread_opname_sessions os ON os.thread_opname_session_id = ol.thread_opname_session_id
        WHERE m.deleted_at IS NULL
          AND m.created_at >= @Dari
          AND m.created_at < @Sampai
          AND (@AdaFilterType = 0 OR m.movement_type IN (SELECT movement_type FROM @Types))
          AND (@ReasonCode IS NULL OR m.reason_code = @ReasonCode)
          AND (@ItemId IS NULL OR m.thread_item_id = @ItemId)
          AND (@LocationId IS NULL OR m.from_location_id = @LocationId OR m.to_location_id = @LocationId)
          AND (@ResourceId IS NULL OR m.resource_id = @ResourceId)
          AND (@ProjectId IS NULL OR m.project_id = @ProjectId)
          AND (@CreatedBy IS NULL OR m.created_by = @CreatedBy)
    )
    SELECT thread_movement_id AS MovementId,
           movement_type      AS MovementType,
           created_at         AS CreatedAt,
           thread_item_id     AS ThreadItemId,
           sku_code           AS SkuCode,
           color_name         AS ColorName,
           color_code         AS ColorCode,
           type_name          AS TypeName,
           brand_name         AS BrandName,
           cone_code          AS ConeCode,
           from_code          AS FromCode,
           to_code            AS ToCode,
           qty_whole          AS QtyWhole,
           weight_gram        AS WeightGram,
           resource_id        AS ResourceId,
           resource_name      AS ResourceName,
           project_id         AS ProjectId,
           project_name       AS ProjectName,
           no_po              AS NoPo,
           reason_code        AS ReasonCode,
           reason_name        AS ReasonName,
           note               AS Note,
           created_by         AS CreatedBy,
           created_by_name    AS CreatedByName,
           opname_line_id     AS OpnameLineId,
           opname_session_id  AS OpnameSessionId,
           opname_session_no  AS OpnameSessionNo,
           COUNT(*) OVER ()   AS TotalCount
    FROM src
    ORDER BY created_at DESC, thread_movement_id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- =============================================================
-- RINGKASAN LANDING
-- @Bagian membatasi ke satu result set (EF Core hanya baca satu).
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadStock_Summary
    @Bagian VARCHAR(10) = NULL        -- TOTAL | HARIINI | PERHATIAN | NULL = ketiganya
AS
BEGIN
    SET NOCOUNT ON;

    IF @Bagian IS NULL OR @Bagian = 'TOTAL'
        SELECT (SELECT COUNT(*) FROM inv.thread_items
                 WHERE deleted_at IS NULL AND is_active = 1)                       AS SkuAktif,
               (SELECT COUNT(*) FROM inv.thread_items WHERE deleted_at IS NULL)    AS SkuTotal,
               (SELECT ISNULL(SUM(qty_whole), 0) FROM inv.thread_stocks
                 WHERE deleted_at IS NULL)                                         AS WholeTotal,
               (SELECT COUNT(*) FROM inv.thread_split_cones
                 WHERE deleted_at IS NULL AND [status] = 'IN_STOCK')               AS SplitKones,
               (SELECT ISNULL(SUM(weight_gram), 0) FROM inv.thread_split_cones
                 WHERE deleted_at IS NULL AND [status] = 'IN_STOCK')               AS SplitGram,
               (SELECT COUNT(*) FROM inv.thread_split_cones
                 WHERE deleted_at IS NULL AND [status] = 'ISSUED')                 AS SplitDiLine,
               (SELECT ISNULL(SUM(weight_gram), 0) FROM inv.thread_split_cones
                 WHERE deleted_at IS NULL AND [status] = 'ISSUED')                 AS SplitDiLineGram,
               (SELECT COUNT(*) FROM inv.thread_locations
                 WHERE deleted_at IS NULL AND is_active = 1)                       AS LokasiAktif,
               (SELECT TOP 1 thread_opname_session_id FROM inv.thread_opname_sessions
                 WHERE [status] = 'OPEN' AND deleted_at IS NULL
                 ORDER BY thread_opname_session_id DESC)                           AS OpnameSessionId,
               (SELECT TOP 1 session_no FROM inv.thread_opname_sessions
                 WHERE [status] = 'OPEN' AND deleted_at IS NULL
                 ORDER BY thread_opname_session_id DESC)                           AS OpnameSessionNo;

    IF @Bagian IS NULL OR @Bagian = 'HARIINI'
        SELECT m.movement_type   AS MovementType,
               COUNT(*)          AS Jumlah,
               ISNULL(SUM(ABS(ISNULL(m.qty_whole, 0))), 0) AS QtyWhole,
               ISNULL(SUM(ISNULL(m.weight_gram, 0)), 0)    AS WeightGram
        FROM inv.thread_movements m
        WHERE m.deleted_at IS NULL
          AND m.created_at >= CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2)
        GROUP BY m.movement_type;

    -- 5 SKU dengan stok whole paling sedikit yang MASIH dipakai (ada ISSUE 30 hari
    -- terakhir). Ini sekadar peringatan -- module ini TIDAK punya stok minimum.
    IF @Bagian IS NULL OR @Bagian = 'PERHATIAN'
        SELECT TOP 5
               i.thread_item_id   AS ThreadItemId,
               i.sku_code         AS SkuCode,
               i.color_name       AS ColorName,
               i.color_code       AS ColorCode,
               b.name             AS BrandName,
               t.name             AS TypeName,
               i.photo_path       AS PhotoPath,
               v.qty_whole_total  AS QtyWholeTotal,
               v.split_count_in_stock AS SplitCountInStock,
               (SELECT ISNULL(SUM(ABS(m2.qty_whole)), 0) FROM inv.thread_movements m2
                 WHERE m2.thread_item_id = i.thread_item_id
                   AND m2.movement_type = 'ISSUE'
                   AND m2.deleted_at IS NULL
                   AND m2.created_at >= DATEADD(DAY, -30, SYSDATETIME())) AS Dipakai30Hari
        FROM inv.thread_items i
        INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
        INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
        INNER JOIN inv.v_thread_item_stock v ON v.thread_item_id = i.thread_item_id
        WHERE i.deleted_at IS NULL AND i.is_active = 1
          AND EXISTS (SELECT 1 FROM inv.thread_movements m
                       WHERE m.thread_item_id = i.thread_item_id
                         AND m.movement_type = 'ISSUE'
                         AND m.deleted_at IS NULL
                         AND m.created_at >= DATEADD(DAY, -30, SYSDATETIME()))
        ORDER BY v.qty_whole_total, i.color_name;
END;
GO

-- =============================================================
-- MATRIKS LOKASI (halaman lokasi): rak x jumlah SKU/kones
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadStock_ByLocation
AS
BEGIN
    SET NOCOUNT ON;

    SELECT l.thread_location_id AS ThreadLocationId,
           l.code               AS Code,
           l.name               AS Name,
           l.is_active          AS IsActive,
           ISNULL(w.sku_count, 0)  AS SkuCount,
           ISNULL(w.qty_whole, 0)  AS QtyWhole,
           ISNULL(s.split_count, 0) AS SplitCount,
           ISNULL(s.split_gram, 0)  AS SplitGram
    FROM inv.thread_locations l
    OUTER APPLY (
        SELECT COUNT(*) AS sku_count, SUM(st.qty_whole) AS qty_whole
        FROM inv.thread_stocks st
        WHERE st.thread_location_id = l.thread_location_id
          AND st.deleted_at IS NULL AND st.qty_whole > 0
    ) w
    OUTER APPLY (
        SELECT COUNT(*) AS split_count, SUM(c.weight_gram) AS split_gram
        FROM inv.thread_split_cones c
        WHERE c.thread_location_id = l.thread_location_id
          AND c.deleted_at IS NULL AND c.[status] = 'IN_STOCK'
    ) s
    WHERE l.deleted_at IS NULL
    ORDER BY l.sort_order, l.code;
END;
GO

-- =============================================================
-- PEMAKAIAN PER PROJECT
-- Whole: SUM(ABS(qty)) movement ISSUE.
-- Split: gram ISSUE_SPLIT dikurangi gram RETURN/RETURN_SPLIT project yang sama
--        (kones yang kembali berarti tidak terpakai habis).
-- Angka gram TIDAK dikonversi ke ekuivalen whole (keputusan desain).
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadUsage_ByProject
    @ProjectId INT = NULL,            -- NULL = semua project
    @Dari      DATETIME2 = NULL,
    @Sampai    DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Dari IS NULL SET @Dari = DATEADD(DAY, -30, CAST(CAST(SYSDATETIME() AS DATE) AS DATETIME2));
    IF @Sampai IS NULL SET @Sampai = SYSDATETIME();
    IF CAST(@Sampai AS TIME) = '00:00:00' SET @Sampai = DATEADD(DAY, 1, @Sampai);

    SELECT m.project_id        AS ProjectId,
           p.project_name      AS ProjectName,
           p.no_po             AS NoPo,
           i.thread_item_id    AS ThreadItemId,
           i.sku_code          AS SkuCode,
           i.color_name        AS ColorName,
           i.color_code        AS ColorCode,
           t.name              AS TypeName,
           b.name              AS BrandName,
           SUM(CASE WHEN m.movement_type = 'ISSUE' THEN ABS(ISNULL(m.qty_whole, 0)) ELSE 0 END)
               AS WholeIssued,
           SUM(CASE WHEN m.movement_type = 'ISSUE_SPLIT' THEN ISNULL(m.weight_gram, 0) ELSE 0 END)
               AS SplitGramIssued,
           SUM(CASE WHEN m.movement_type IN ('RETURN','RETURN_SPLIT') THEN ISNULL(m.weight_gram, 0) ELSE 0 END)
               AS SplitGramReturned,
           SUM(CASE WHEN m.movement_type = 'ISSUE_SPLIT' THEN ISNULL(m.weight_gram, 0)
                    WHEN m.movement_type IN ('RETURN','RETURN_SPLIT') THEN -ISNULL(m.weight_gram, 0)
                    ELSE 0 END)
               AS SplitGramNet
    FROM inv.thread_movements m
    INNER JOIN inv.thread_items i  ON i.thread_item_id = m.thread_item_id
    INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
    INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
    LEFT JOIN dbo.projects p       ON p.project_id = m.project_id
    WHERE m.deleted_at IS NULL
      AND m.project_id IS NOT NULL
      AND (@ProjectId IS NULL OR m.project_id = @ProjectId)
      AND m.created_at >= @Dari
      AND m.created_at < @Sampai
      AND m.movement_type IN ('ISSUE','ISSUE_SPLIT','RETURN','RETURN_SPLIT')
    GROUP BY m.project_id, p.project_name, p.no_po,
             i.thread_item_id, i.sku_code, i.color_name, i.color_code, t.name, b.name
    HAVING SUM(CASE WHEN m.movement_type = 'ISSUE' THEN ABS(ISNULL(m.qty_whole, 0)) ELSE 0 END) > 0
        OR SUM(CASE WHEN m.movement_type = 'ISSUE_SPLIT' THEN ISNULL(m.weight_gram, 0) ELSE 0 END) > 0
    ORDER BY p.project_name, i.color_name;
END;
GO
