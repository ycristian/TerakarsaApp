-- Mutasi data packs/pack_items (CREATE/UPDATE_PLAN/CONFIRM/DELETE) + cetak ulang label
-- (SIS_Pack_ReprintLabel). Pengambilan data ada di sp_Pack_Select.sql.
-- Dibuat di stasiun khusus packing (station kiosk, tanpa login user).
-- Aturan:
--   1. Items dikirim sebagai JSON (@ItemsJson), diparse dengan OPENJSON:
--        CREATE/UPDATE_PLAN: array {articleId, articleSizeId, qtyPlan}.
--        CONFIRM:            array {packItemId, qtyActual}.
--   2. Satu karung boleh campur artikel, TIDAK boleh campur project (project_id di level
--      pack, bukan per item) -- artikel tiap item divalidasi milik @ProjectId.
--   3. Stok tersedia = qty_ok log hidup STEP TERAKHIR artikel (per artikel, MAX sort_order
--      article_workflows artikel itu sendiri) dikurangi Σ COALESCE(qty_actual, qty_plan)
--      pack_items hidup untuk (artikel, size) yang sama -- rumus sama persis dengan
--      SIS_Pack_StockAvailable (sp_Pack_Select.sql), diulang di sini karena CTE tidak bisa
--      dipakai lintas statement. TIDAK ada tabel stok terpisah.
--   4. Serial + pack_no digenerate dalam sp_getapplock 'pack_serial_seq' (pola persis
--      SIS_Bundle_Manage): serial global PK{yy}-{6 digit}, pack_no = MAX per project
--      TERMASUK yang soft-deleted + 1 (tidak pernah dipakai ulang).
--   5. CREATE otomatis membuat baris print_jobs (job_type PACK_LABEL, ref_id = pack baru)
--      kecuali @SkipPrintJob = 1 (checkbox "Cetak label otomatis" tidak dicentang).
--      qr_content = @PublicBaseUrl + '/pack/' + serial, dirakit di sini karena serial baru
--      diketahui di dalam applock.
--   6. UPDATE_PLAN (ganti seluruh komposisi planning) hanya boleh selama SEMUA baris
--      qty_actual pack ini masih NULL (belum ada yang dikonfirmasi).
--   7. CONFIRM mengisi/mengubah qty_actual per pack_item_id, boleh dipanggil berulang
--      (edit kondisi terkini) -- qty_actual 0 = batal masuk karung tapi baris tetap
--      tercatat (bukan soft delete).
--   8. DELETE (@DeleteReason wajib) soft delete pack + semua items -- stok otomatis
--      kembali karena rumus stok tidak lagi menghitung pack yang sudah dihapus.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Pack_Manage
    @Action        VARCHAR(20),
    @Id            INT = NULL,
    @ProjectId     INT = NULL,
    @ItemsJson     NVARCHAR(MAX) = NULL,
    @PublicBaseUrl VARCHAR(255) = NULL,
    @SkipPrintJob  BIT = 0,
    @DeleteReason  VARCHAR(255) = NULL,
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        DECLARE @Items TABLE (RowId INT IDENTITY(1,1), ArticleId INT, ArticleSizeId INT, QtyPlan INT);
        INSERT INTO @Items (ArticleId, ArticleSizeId, QtyPlan)
        SELECT articleId, articleSizeId, qtyPlan
        FROM OPENJSON(@ItemsJson)
        WITH (
            articleId     INT '$.articleId',
            articleSizeId INT '$.articleSizeId',
            qtyPlan       INT '$.qtyPlan'
        );

        IF NOT EXISTS (SELECT 1 FROM @Items)
        BEGIN
            RAISERROR('Karung harus berisi minimal 1 item.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Items WHERE QtyPlan IS NULL OR QtyPlan <= 0)
        BEGIN
            RAISERROR('Qty tiap item harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT ArticleId, ArticleSizeId FROM @Items GROUP BY ArticleId, ArticleSizeId HAVING COUNT(*) > 1)
        BEGIN
            RAISERROR('Ada artikel+ukuran yang duplikat dalam satu karung.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM @Items i
            LEFT JOIN articles a ON a.article_id = i.ArticleId AND a.project_id = @ProjectId AND a.deleted_at IS NULL
            WHERE a.article_id IS NULL
        )
        BEGIN
            RAISERROR('Ada artikel yang tidak ditemukan/bukan milik project ini.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM @Items i
            LEFT JOIN article_sizes asz ON asz.article_size_id = i.ArticleSizeId AND asz.article_id = i.ArticleId AND asz.deleted_at IS NULL
            WHERE asz.article_size_id IS NULL
        )
        BEGIN
            RAISERROR('Ada ukuran yang tidak ditemukan/bukan milik artikelnya.', 16, 1);
            RETURN;
        END

        DECLARE @BadArticleName_C VARCHAR(255), @BadSizeName_C VARCHAR(255), @BadAvailable_C INT;
        ;WITH LastStep AS (
            SELECT a.article_id,
                   (SELECT TOP 1 aw.article_workflow_id FROM article_workflows aw
                    WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL
                    ORDER BY aw.sort_order DESC) AS LastStepId
            FROM articles a WHERE a.project_id = @ProjectId AND a.deleted_at IS NULL
        ),
        Done AS (
            SELECT ls.article_id AS ArticleId,
                   COALESCE(awl.article_size_id, b.article_size_id) AS ArticleSizeId,
                   SUM(awl.qty_ok) AS QtyDone
            FROM LastStep ls
            INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = ls.LastStepId AND awl.deleted_at IS NULL
            LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
            GROUP BY ls.article_id, COALESCE(awl.article_size_id, b.article_size_id)
        ),
        Packed AS (
            SELECT pi.article_id AS ArticleId, pi.article_size_id AS ArticleSizeId,
                   SUM(COALESCE(pi.qty_actual, pi.qty_plan)) AS QtyPacked
            FROM pack_items pi
            INNER JOIN packs p ON p.pack_id = pi.pack_id AND p.deleted_at IS NULL
            WHERE pi.deleted_at IS NULL AND p.project_id = @ProjectId
            GROUP BY pi.article_id, pi.article_size_id
        )
        SELECT TOP 1 @BadArticleName_C = a.article_name, @BadSizeName_C = spd.size_name,
                      @BadAvailable_C = ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0)
        FROM @Items i
        INNER JOIN articles a ON a.article_id = i.ArticleId
        INNER JOIN article_sizes asz ON asz.article_size_id = i.ArticleSizeId
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN Done d ON d.ArticleId = i.ArticleId AND d.ArticleSizeId = i.ArticleSizeId
        LEFT JOIN Packed pk ON pk.ArticleId = i.ArticleId AND pk.ArticleSizeId = i.ArticleSizeId
        WHERE i.QtyPlan > (ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0));

        IF @BadArticleName_C IS NOT NULL
        BEGIN
            RAISERROR('Stok %s ukuran %s tidak cukup (sisa %d).', 16, 1, @BadArticleName_C, @BadSizeName_C, @BadAvailable_C);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            DECLARE @LockResult INT;
            EXEC @LockResult = sp_getapplock
                @Resource = 'pack_serial_seq',
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                RAISERROR('Gagal mengunci penomoran serial karung. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            DECLARE @NextNumber INT;
            SELECT @NextNumber = ISNULL(MAX(CAST(RIGHT(serial, 6) AS INT)), 0) + 1 FROM packs;

            DECLARE @Yy VARCHAR(2) = RIGHT(CAST(YEAR(SYSDATETIME()) AS VARCHAR(4)), 2);
            DECLARE @NewSerial VARCHAR(20) = 'PK' + @Yy + '-' + RIGHT('000000' + CAST(@NextNumber AS VARCHAR(6)), 6);

            DECLARE @NewPackNo INT;
            SELECT @NewPackNo = ISNULL(MAX(pack_no), 0) + 1 FROM packs WHERE project_id = @ProjectId;

            INSERT INTO packs (project_id, pack_no, serial, created_at, created_by)
            VALUES (@ProjectId, @NewPackNo, @NewSerial, SYSDATETIME(), @UserId);

            DECLARE @NewPackId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO pack_items (pack_id, article_id, article_size_id, qty_plan, created_at, created_by)
            SELECT @NewPackId, ArticleId, ArticleSizeId, QtyPlan, SYSDATETIME(), @UserId
            FROM @Items;

            DECLARE @NewPrintJobId INT = NULL;
            IF @SkipPrintJob = 0
            BEGIN
                DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/pack/' + @NewSerial;
                DECLARE @TotalQty INT = (SELECT SUM(QtyPlan) FROM @Items);
                DECLARE @ItemCount INT = (SELECT COUNT(DISTINCT ArticleId) FROM @Items);
                DECLARE @ProjectName_C VARCHAR(255) = (SELECT project_name FROM projects WHERE project_id = @ProjectId);

                DECLARE @Payload NVARCHAR(MAX) = (
                    SELECT
                        @NewSerial AS serial,
                        @QrContent AS qr_content,
                        @ProjectName_C AS project_name,
                        @NewPackNo AS pack_no,
                        @TotalQty AS total_qty,
                        @ItemCount AS item_count,
                        CAST(0 AS BIT) AS is_confirmed
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
                VALUES ('PACK_LABEL', @NewPackId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

                SET @NewPrintJobId = CAST(SCOPE_IDENTITY() AS INT);
            END

            COMMIT TRAN;

            SELECT @NewPackId AS NewId, @NewPackNo AS NewPackNo, @NewSerial AS NewSerial, @NewPrintJobId AS NewPrintJobId;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'UPDATE_PLAN'
    BEGIN
        DECLARE @PlanProjectId INT;
        SELECT @PlanProjectId = project_id FROM packs WHERE pack_id = @Id AND deleted_at IS NULL;

        IF @PlanProjectId IS NULL
        BEGIN
            RAISERROR('Karung tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM pack_items WHERE pack_id = @Id AND deleted_at IS NULL AND qty_actual IS NOT NULL)
        BEGIN
            RAISERROR('Karung sudah punya item yang dikonfirmasi, planning tidak bisa diubah lagi.', 16, 1);
            RETURN;
        END

        DECLARE @PlanItems TABLE (RowId INT IDENTITY(1,1), ArticleId INT, ArticleSizeId INT, QtyPlan INT);
        INSERT INTO @PlanItems (ArticleId, ArticleSizeId, QtyPlan)
        SELECT articleId, articleSizeId, qtyPlan
        FROM OPENJSON(@ItemsJson)
        WITH (
            articleId     INT '$.articleId',
            articleSizeId INT '$.articleSizeId',
            qtyPlan       INT '$.qtyPlan'
        );

        IF NOT EXISTS (SELECT 1 FROM @PlanItems)
        BEGIN
            RAISERROR('Karung harus berisi minimal 1 item.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @PlanItems WHERE QtyPlan IS NULL OR QtyPlan <= 0)
        BEGIN
            RAISERROR('Qty tiap item harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT ArticleId, ArticleSizeId FROM @PlanItems GROUP BY ArticleId, ArticleSizeId HAVING COUNT(*) > 1)
        BEGIN
            RAISERROR('Ada artikel+ukuran yang duplikat dalam satu karung.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM @PlanItems i
            LEFT JOIN articles a ON a.article_id = i.ArticleId AND a.project_id = @PlanProjectId AND a.deleted_at IS NULL
            WHERE a.article_id IS NULL
        )
        BEGIN
            RAISERROR('Ada artikel yang tidak ditemukan/bukan milik project ini.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM @PlanItems i
            LEFT JOIN article_sizes asz ON asz.article_size_id = i.ArticleSizeId AND asz.article_id = i.ArticleId AND asz.deleted_at IS NULL
            WHERE asz.article_size_id IS NULL
        )
        BEGIN
            RAISERROR('Ada ukuran yang tidak ditemukan/bukan milik artikelnya.', 16, 1);
            RETURN;
        END

        DECLARE @BadArticleName_U VARCHAR(255), @BadSizeName_U VARCHAR(255), @BadAvailable_U INT;
        ;WITH LastStep AS (
            SELECT a.article_id,
                   (SELECT TOP 1 aw.article_workflow_id FROM article_workflows aw
                    WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL
                    ORDER BY aw.sort_order DESC) AS LastStepId
            FROM articles a WHERE a.project_id = @PlanProjectId AND a.deleted_at IS NULL
        ),
        Done AS (
            SELECT ls.article_id AS ArticleId,
                   COALESCE(awl.article_size_id, b.article_size_id) AS ArticleSizeId,
                   SUM(awl.qty_ok) AS QtyDone
            FROM LastStep ls
            INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = ls.LastStepId AND awl.deleted_at IS NULL
            LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
            GROUP BY ls.article_id, COALESCE(awl.article_size_id, b.article_size_id)
        ),
        Packed AS (
            -- @Id sendiri dikecualikan -- planning lama karung ini tidak menghitung sebagai "sudah dipack".
            SELECT pi.article_id AS ArticleId, pi.article_size_id AS ArticleSizeId,
                   SUM(COALESCE(pi.qty_actual, pi.qty_plan)) AS QtyPacked
            FROM pack_items pi
            INNER JOIN packs p ON p.pack_id = pi.pack_id AND p.deleted_at IS NULL
            WHERE pi.deleted_at IS NULL AND p.project_id = @PlanProjectId AND p.pack_id <> @Id
            GROUP BY pi.article_id, pi.article_size_id
        )
        SELECT TOP 1 @BadArticleName_U = a.article_name, @BadSizeName_U = spd.size_name,
                      @BadAvailable_U = ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0)
        FROM @PlanItems i
        INNER JOIN articles a ON a.article_id = i.ArticleId
        INNER JOIN article_sizes asz ON asz.article_size_id = i.ArticleSizeId
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN Done d ON d.ArticleId = i.ArticleId AND d.ArticleSizeId = i.ArticleSizeId
        LEFT JOIN Packed pk ON pk.ArticleId = i.ArticleId AND pk.ArticleSizeId = i.ArticleSizeId
        WHERE i.QtyPlan > (ISNULL(d.QtyDone, 0) - ISNULL(pk.QtyPacked, 0));

        IF @BadArticleName_U IS NOT NULL
        BEGIN
            RAISERROR('Stok %s ukuran %s tidak cukup (sisa %d).', 16, 1, @BadArticleName_U, @BadSizeName_U, @BadAvailable_U);
            RETURN;
        END

        UPDATE pack_items
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE pack_id = @Id AND deleted_at IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM @PlanItems i
              WHERE i.ArticleId = pack_items.article_id AND i.ArticleSizeId = pack_items.article_size_id
          );

        UPDATE pi
        SET pi.qty_plan = i.QtyPlan,
            pi.updated_at = SYSDATETIME(),
            pi.updated_by = @UserId
        FROM pack_items pi
        INNER JOIN @PlanItems i ON i.ArticleId = pi.article_id AND i.ArticleSizeId = pi.article_size_id
        WHERE pi.pack_id = @Id AND pi.deleted_at IS NULL;

        INSERT INTO pack_items (pack_id, article_id, article_size_id, qty_plan, created_at, created_by)
        SELECT @Id, i.ArticleId, i.ArticleSizeId, i.QtyPlan, SYSDATETIME(), @UserId
        FROM @PlanItems i
        WHERE NOT EXISTS (
            SELECT 1 FROM pack_items pi2
            WHERE pi2.pack_id = @Id AND pi2.deleted_at IS NULL
              AND pi2.article_id = i.ArticleId AND pi2.article_size_id = i.ArticleSizeId
        );

        UPDATE packs SET updated_at = SYSDATETIME(), updated_by = @UserId WHERE pack_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'CONFIRM'
    BEGIN
        DECLARE @ConfirmProjectId INT;
        SELECT @ConfirmProjectId = project_id FROM packs WHERE pack_id = @Id AND deleted_at IS NULL;

        IF @ConfirmProjectId IS NULL
        BEGIN
            RAISERROR('Karung tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @ConfirmItems TABLE (RowId INT IDENTITY(1,1), PackItemId INT, QtyActual INT);
        INSERT INTO @ConfirmItems (PackItemId, QtyActual)
        SELECT packItemId, qtyActual
        FROM OPENJSON(@ItemsJson)
        WITH (
            packItemId INT '$.packItemId',
            qtyActual  INT '$.qtyActual'
        );

        IF NOT EXISTS (SELECT 1 FROM @ConfirmItems)
        BEGIN
            RAISERROR('Minimal satu item harus dikonfirmasi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @ConfirmItems WHERE QtyActual IS NULL OR QtyActual < 0)
        BEGIN
            RAISERROR('Qty aktual tidak boleh negatif.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT PackItemId FROM @ConfirmItems GROUP BY PackItemId HAVING COUNT(*) > 1)
        BEGIN
            RAISERROR('Ada item karung yang duplikat dalam satu permintaan.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM @ConfirmItems i
            LEFT JOIN pack_items pi ON pi.pack_item_id = i.PackItemId AND pi.pack_id = @Id AND pi.deleted_at IS NULL
            WHERE pi.pack_item_id IS NULL
        )
        BEGIN
            RAISERROR('Ada item karung yang tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @ConfirmResolved TABLE (PackItemId INT, ArticleId INT, ArticleSizeId INT, QtyActual INT);
        INSERT INTO @ConfirmResolved (PackItemId, ArticleId, ArticleSizeId, QtyActual)
        SELECT pi.pack_item_id, pi.article_id, pi.article_size_id, i.QtyActual
        FROM @ConfirmItems i
        INNER JOIN pack_items pi ON pi.pack_item_id = i.PackItemId;

        DECLARE @BadArticleName_F VARCHAR(255), @BadSizeName_F VARCHAR(255), @BadAvailable_F INT;
        ;WITH LastStep AS (
            SELECT a.article_id,
                   (SELECT TOP 1 aw.article_workflow_id FROM article_workflows aw
                    WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL
                    ORDER BY aw.sort_order DESC) AS LastStepId
            FROM articles a WHERE a.project_id = @ConfirmProjectId AND a.deleted_at IS NULL
        ),
        Done AS (
            SELECT ls.article_id AS ArticleId,
                   COALESCE(awl.article_size_id, b.article_size_id) AS ArticleSizeId,
                   SUM(awl.qty_ok) AS QtyDone
            FROM LastStep ls
            INNER JOIN article_workflow_logs awl ON awl.article_workflow_id = ls.LastStepId AND awl.deleted_at IS NULL
            LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
            GROUP BY ls.article_id, COALESCE(awl.article_size_id, b.article_size_id)
        ),
        -- Item yang sedang dikonfirmasi dikecualikan dari total lama (nilai lamanya diganti
        -- oleh QtyActual baru yang dijumlah lewat @ConfirmResolved di bawah).
        PackedExcl AS (
            SELECT pi.article_id AS ArticleId, pi.article_size_id AS ArticleSizeId,
                   SUM(COALESCE(pi.qty_actual, pi.qty_plan)) AS QtyPacked
            FROM pack_items pi
            INNER JOIN packs p ON p.pack_id = pi.pack_id AND p.deleted_at IS NULL
            WHERE pi.deleted_at IS NULL AND p.project_id = @ConfirmProjectId
              AND pi.pack_item_id NOT IN (SELECT PackItemId FROM @ConfirmResolved)
            GROUP BY pi.article_id, pi.article_size_id
        ),
        NewGroup AS (
            SELECT ArticleId, ArticleSizeId, SUM(QtyActual) AS QtyNew
            FROM @ConfirmResolved
            GROUP BY ArticleId, ArticleSizeId
        )
        SELECT TOP 1 @BadArticleName_F = a.article_name, @BadSizeName_F = spd.size_name,
                      @BadAvailable_F = ISNULL(d.QtyDone, 0) - ISNULL(pe.QtyPacked, 0)
        FROM NewGroup ng
        INNER JOIN articles a ON a.article_id = ng.ArticleId
        INNER JOIN article_sizes asz ON asz.article_size_id = ng.ArticleSizeId
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN Done d ON d.ArticleId = ng.ArticleId AND d.ArticleSizeId = ng.ArticleSizeId
        LEFT JOIN PackedExcl pe ON pe.ArticleId = ng.ArticleId AND pe.ArticleSizeId = ng.ArticleSizeId
        WHERE (ISNULL(pe.QtyPacked, 0) + ng.QtyNew) > ISNULL(d.QtyDone, 0);

        IF @BadArticleName_F IS NOT NULL
        BEGIN
            RAISERROR('Stok %s ukuran %s tidak cukup (sisa %d).', 16, 1, @BadArticleName_F, @BadSizeName_F, @BadAvailable_F);
            RETURN;
        END

        UPDATE pi
        SET pi.qty_actual = r.QtyActual,
            pi.updated_at = SYSDATETIME(),
            pi.updated_by = @UserId
        FROM pack_items pi
        INNER JOIN @ConfirmResolved r ON r.PackItemId = pi.pack_item_id
        WHERE pi.pack_id = @Id AND pi.deleted_at IS NULL;

        UPDATE packs SET updated_at = SYSDATETIME(), updated_by = @UserId WHERE pack_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus karung wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM packs WHERE pack_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Karung tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE packs
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId, delete_reason = @DeleteReason
        WHERE pack_id = @Id AND deleted_at IS NULL;

        UPDATE pack_items
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE pack_id = @Id AND deleted_at IS NULL;
    END
END;
GO

-- Cetak ulang label: insert baris print_jobs baru, payload dirakit ulang dari data terkini
-- (qty aktual terbaru bila sudah dikonfirmasi, badge PLAN/AKTUAL menyesuaikan).
CREATE OR ALTER PROCEDURE SIS_Pack_ReprintLabel
    @PackId        INT,
    @PublicBaseUrl VARCHAR(255) = NULL,
    @UserId        INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM packs WHERE pack_id = @PackId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Karung tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @Serial VARCHAR(20), @PackNo INT, @ProjectName VARCHAR(255);
    SELECT @Serial = p.serial, @PackNo = p.pack_no, @ProjectName = pr.project_name
    FROM packs p
    INNER JOIN projects pr ON pr.project_id = p.project_id
    WHERE p.pack_id = @PackId;

    DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/pack/' + @Serial;
    DECLARE @TotalQty INT = ISNULL((SELECT SUM(COALESCE(qty_actual, qty_plan)) FROM pack_items WHERE pack_id = @PackId AND deleted_at IS NULL), 0);
    DECLARE @ItemCount INT = ISNULL((SELECT COUNT(DISTINCT article_id) FROM pack_items WHERE pack_id = @PackId AND deleted_at IS NULL), 0);
    DECLARE @IsConfirmed BIT = CASE WHEN EXISTS (SELECT 1 FROM pack_items WHERE pack_id = @PackId AND deleted_at IS NULL)
                                      AND NOT EXISTS (SELECT 1 FROM pack_items WHERE pack_id = @PackId AND deleted_at IS NULL AND qty_actual IS NULL)
                                 THEN 1 ELSE 0 END;

    DECLARE @Payload NVARCHAR(MAX) = (
        SELECT
            @Serial AS serial,
            @QrContent AS qr_content,
            @ProjectName AS project_name,
            @PackNo AS pack_no,
            @TotalQty AS total_qty,
            @ItemCount AS item_count,
            @IsConfirmed AS is_confirmed
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
    VALUES ('PACK_LABEL', @PackId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewPrintJobId;
END;
GO
