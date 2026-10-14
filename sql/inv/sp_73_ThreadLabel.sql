/* =============================================================
   Module Stok Benang (Prompt 73) -- antrian cetak label 30x20 mm.

   Dua job type:
     THREAD_SKU_LABEL   ref_id = thread_item_id       (QR `TB:<sku_code>`)
     THREAD_SPLIT_LABEL ref_id = thread_split_cone_id (QR `TS:<cone_code>`)

   SATU baris print_jobs per permintaan cetak; jumlah copy label SKU dibawa di
   payload (`copies`) dan diterjemahkan jadi `PRINT 1,<copies>` oleh TsplBuilder --
   BEDA dengan BUNDLE_LABEL yang membuat satu job per copy.

   Label TIDAK pernah dibuat otomatis setelah RETURN (Prompt 72): admin gudang
   menekan tombol cetak setelah yakin kones & beratnya benar.

   Payload snake_case (FOR JSON PATH) supaya seragam dengan payload label lain.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inv.SIS_ThreadLabel_Enqueue
    @Kind   VARCHAR(10),        -- SKU | SPLIT
    @RefId  INT,
    @Copies INT = 1,            -- hanya untuk SKU, 1-50
    @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Kind NOT IN ('SKU','SPLIT')
    BEGIN
        RAISERROR('Jenis label harus SKU atau SPLIT.', 16, 1);
        RETURN;
    END

    DECLARE @Payload NVARCHAR(MAX);
    DECLARE @JobType VARCHAR(30);

    IF @Kind = 'SKU'
    BEGIN
        IF @Copies IS NULL OR @Copies < 1 OR @Copies > 50
        BEGIN
            RAISERROR('Jumlah label harus antara 1 dan 50.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM inv.thread_items
                        WHERE thread_item_id = @RefId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU benang tidak ditemukan.', 16, 1);
            RETURN;
        END

        SET @JobType = 'THREAD_SKU_LABEL';

        SET @Payload = (
            SELECT 'SKU'                  AS kind,
                   'TB:' + i.sku_code     AS qr,
                   i.sku_code             AS sku_code,
                   i.color_code           AS color_code,
                   i.color_name           AS color_name,
                   b.name                 AS brand,
                   t.name                 AS thread_type,
                   i.cone_size            AS cone_size,
                   @Copies                AS copies
            FROM inv.thread_items i
            INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
            INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
            WHERE i.thread_item_id = @RefId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_split_cones
                        WHERE thread_split_cone_id = @RefId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kones split tidak ditemukan.', 16, 1);
            RETURN;
        END

        SET @JobType = 'THREAD_SPLIT_LABEL';

        -- Label split selalu 1 lembar: satu kones fisik, satu label.
        SET @Payload = (
            SELECT 'SPLIT'                AS kind,
                   'TS:' + c.cone_code    AS qr,
                   c.cone_code            AS cone_code,
                   i.sku_code             AS sku_code,
                   i.color_code           AS color_code,
                   i.color_name           AS color_name,
                   b.name                 AS brand,
                   t.name                 AS thread_type,
                   i.cone_size            AS cone_size,
                   c.weight_gram          AS weight_gram,
                   1                      AS copies
            FROM inv.thread_split_cones c
            INNER JOIN inv.thread_items i  ON i.thread_item_id = c.thread_item_id
            INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
            INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
            WHERE c.thread_split_cone_id = @RefId
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
    END

    IF @Payload IS NULL
    BEGIN
        RAISERROR('Data label tidak bisa dirakit.', 16, 1);
        RETURN;
    END

    -- Kolom sama dengan enqueue label bundle (sql/sp_Bundle_Manage.sql):
    -- print_device_id SENGAJA tidak diisi di sini -- diresolusi SAAT KLAIM lewat
    -- print_job_routes (Prompt 48).
    INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
    VALUES (@JobType, @RefId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS Value;
END;
GO

-- =============================================================
-- BACA: status cetak label satu SKU / kones (PENDING/PRINTING/DONE/ERROR),
-- dipakai UI untuk menampilkan hasil tombol cetak -- sama seperti label bundle.
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadLabel_Status
    @Kind  VARCHAR(10),
    @RefId INT,
    @Top   INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    IF @Top IS NULL OR @Top < 1 OR @Top > 50 SET @Top = 5;

    DECLARE @JobType VARCHAR(30) =
        CASE WHEN @Kind = 'SPLIT' THEN 'THREAD_SPLIT_LABEL' ELSE 'THREAD_SKU_LABEL' END;

    SELECT TOP (@Top)
           j.print_job_id    AS PrintJobId,
           j.job_type        AS JobType,
           j.ref_id          AS RefId,
           j.[status]        AS Status,
           j.error_message   AS ErrorMessage,
           j.printed_at      AS PrintedAt,
           j.created_at      AS CreatedAt
    FROM print_jobs j
    WHERE j.job_type = @JobType
      AND j.ref_id = @RefId
      AND j.deleted_at IS NULL
    ORDER BY j.print_job_id DESC;
END;
GO
