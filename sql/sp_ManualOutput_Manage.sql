-- Prompt 83: output MANUAL -- output yang tidak lewat bundle, dicatat tiap divisi sendiri
-- dari tab OUT stasiun. Tidak bergantung artikel, PO, maupun divisi lain.
--
-- Pintu masuk MANDIRI, terpisah dari SIS_WorkflowLog_Manage: baris di sini TIDAK menyentuh
-- article_workflow_logs dan TIDAK MENYENTUH SALDO BUNDLE sama sekali -- murni untuk gajian
-- dan laporan per resource. Tidak ada rantai qty_delta/qty_after di sini.
--
-- Bedanya dengan SIS_NonPoOutput_Manage (Prompt 59, kini diretire):
--   * harga TIDAK PERNAH diisi PIC. Harga melekat ke LOCK ITEM, bukan ke baris ini.
--   * qty boleh 0 atau MINUS (baris minus = catatan potongan).
--   * IKUT mekanisme lock Prompt 55: lock_id terisi -> qty beku di semua jalur.
--   * periode gajian datang dari lock, bukan dari tanggal baris.
--
-- Prefix pesan error yang dikenali UI: 'LOCKED|' (sama dengan SIS_Bundle_Manage /
-- SIS_WorkflowLog_Manage, supaya UI bisa menawarkan pengajuan unlock).
--
-- Pengambilan data ada di procedure terpisah: sql/sp_ManualOutput_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ===========================================================================
-- SATU-SATUNYA definisi aturan tarif step. Dipakai SIS_WorkflowLock_Manage (saat
-- lock) dan SIS_ManualOutput_LinkArticle (saat artikel ditempel belakangan), jadi
-- harga yang dibekukan tidak bisa berbeda antara dua jalur itu.
--
-- article_workflows.unit_price NOT NULL DEFAULT 0 (Prompt 59), jadi 0 ambigu:
--   step Bundling (is_bundling=1) -> 0 adalah HARGA YANG BENAR, kembalikan 0.
--   step lain                     -> 0 berarti tarif belum diisi, kembalikan NULL
--                                    supaya baris itu disorot & memblokir finalisasi.
-- Keputusan owner Prompt 83. JANGAN mengisi 0 sebagai pengganti NULL di SP lain.
-- ===========================================================================
CREATE OR ALTER FUNCTION dbo.SIS_fn_StepUnitPrice(@ArticleWorkflowId INT)
RETURNS DECIMAL(19,4)
AS
BEGIN
    DECLARE @Price DECIMAL(19,4), @IsBundling BIT;

    SELECT @Price = unit_price, @IsBundling = is_bundling
    FROM article_workflows
    WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

    IF @Price IS NULL RETURN NULL;          -- step tidak ditemukan
    IF @IsBundling = 1 RETURN @Price;       -- 0 di step Bundling = harga yang benar
    RETURN NULLIF(@Price, 0);               -- 0 di step lain = tarif belum diisi
END;
GO

-- Tarif untuk baris MANUAL. Hanya bisa ditentukan kalau artikel SUDAH terisi DAN
-- step-nya tidak ambigu dari divisi: tepat SATU step aktif artikel itu di divisi
-- tersebut. Artikel yang punya dua step di divisi sama (mis. dua kali lewat QC)
-- sengaja dikembalikan NULL -- lebih baik admin yang memutuskan harganya daripada
-- SP menebak step mana yang dimaksud.
CREATE OR ALTER FUNCTION dbo.SIS_fn_ManualStepUnitPrice(@ArticleId INT, @DivisionId INT)
RETURNS DECIMAL(19,4)
AS
BEGIN
    IF @ArticleId IS NULL OR @DivisionId IS NULL RETURN NULL;

    DECLARE @Cocok INT, @AwId INT;

    SELECT @Cocok = COUNT(*), @AwId = MIN(article_workflow_id)
    FROM article_workflows
    WHERE article_id = @ArticleId AND division_id = @DivisionId
      AND deleted_at IS NULL AND inactive_at IS NULL;

    IF @Cocok <> 1 RETURN NULL;             -- step tidak bisa ditentukan dari divisi
    RETURN dbo.SIS_fn_StepUnitPrice(@AwId);
END;
GO

-- ===========================================================================
-- SIS_ManualOutput_Manage -- CREATE / UPDATE / DELETE / LINK_ARTICLE
--
-- Divisi TIDAK pernah datang dari client: selalu disalin dari resources.division_id
-- (pola SIS_NonPoOutput_Manage). Harga tidak punya parameter di sini SAMA SEKALI --
-- itu disengaja, PIC tidak boleh bisa menyentuh harga.
-- ===========================================================================
CREATE OR ALTER PROCEDURE SIS_ManualOutput_Manage
    @Action          VARCHAR(20),
    @ManualOutputId  INT = NULL,
    @ResourceId      INT = NULL,            -- operator sesi stasiun; pemilik baris
    @ArticleId       INT = NULL,            -- opsional
    @WorkDescription NVARCHAR(300) = NULL,
    @SizeName        VARCHAR(50) = NULL,
    @Qty             INT = NULL,            -- boleh 0 atau minus
    @RejectQty       INT = NULL,
    @Note            NVARCHAR(500) = NULL,
    @ManualOutputIds VARCHAR(MAX) = NULL,   -- LINK_ARTICLE: CSV id
    @UserId          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @UserId IS NULL
    BEGIN
        RAISERROR('User pencatat tidak dikenal.', 16, 1);
        RETURN;
    END

    -- =======================================================================
    -- LINK_ARTICLE -- menempelkan artikel ke satu/banyak baris.
    -- Dipisah di depan karena jalur ini TIDAK butuh @ResourceId dan BOLEH
    -- menyentuh baris yang sudah lock (menempel artikel bukan mengubah qty).
    -- =======================================================================
    IF @Action = 'LINK_ARTICLE'
    BEGIN
        IF @ArticleId IS NULL OR NOT EXISTS (
            SELECT 1 FROM articles WHERE article_id = @ArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Artikel tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @Ids TABLE (manual_output_id INT PRIMARY KEY);
        INSERT INTO @Ids (manual_output_id)
        SELECT DISTINCT CAST(LTRIM(RTRIM(value)) AS INT)
        FROM STRING_SPLIT(ISNULL(@ManualOutputIds, ''), ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        -- Pemanggil satu baris boleh pakai @ManualOutputId saja.
        IF NOT EXISTS (SELECT 1 FROM @Ids) AND @ManualOutputId IS NOT NULL
            INSERT INTO @Ids (manual_output_id) VALUES (@ManualOutputId);

        IF NOT EXISTS (SELECT 1 FROM @Ids)
        BEGIN
            RAISERROR('Pilih minimal satu baris output manual.', 16, 1);
            RETURN;
        END

        DECLARE @Hilang INT = (
            SELECT COUNT(*) FROM @Ids i
            WHERE NOT EXISTS (
                SELECT 1 FROM manual_outputs mo
                WHERE mo.manual_output_id = i.manual_output_id AND mo.deleted_at IS NULL
            )
        );

        IF @Hilang > 0
        BEGIN
            RAISERROR('%d baris output manual tidak ditemukan. Muat ulang daftar.', 16, 1, @Hilang);
            RETURN;
        END

        DECLARE @LinkedCount INT, @PricedCount INT;

        BEGIN TRAN;
        BEGIN TRY
            UPDATE mo
            SET mo.article_id = @ArticleId,
                mo.updated_at = SYSDATETIME(),
                mo.updated_by = @UserId
            FROM manual_outputs mo
            INNER JOIN @Ids i ON i.manual_output_id = mo.manual_output_id
            WHERE mo.deleted_at IS NULL;

            SET @LinkedCount = @@ROWCOUNT;

            -- Baris yang SUDAH lock: isi unit_price lock item-nya dari tarif artikel
            -- yang baru ditempel -- TAPI HANYA kalau masih NULL. Harga yang sudah
            -- diisi/dikoreksi admin TIDAK PERNAH ditimpa (aturan Bagian 3.3).
            -- Lock item di periode yang sudah final juga tidak disentuh.
            UPDATE wli
            SET wli.unit_price = dbo.SIS_fn_ManualStepUnitPrice(@ArticleId, mo.division_id),
                wli.updated_at = SYSDATETIME(),
                wli.updated_by = @UserId
            FROM workflow_lock_items wli
            INNER JOIN manual_outputs mo ON mo.manual_output_id = wli.manual_output_id
            INNER JOIN @Ids i ON i.manual_output_id = mo.manual_output_id
            INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id
            INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
            WHERE wli.source = 'MANUAL'
              AND wli.unit_price IS NULL
              AND wli.released_at IS NULL AND wli.deleted_at IS NULL
              AND pp.finalized_at IS NULL
              AND dbo.SIS_fn_ManualStepUnitPrice(@ArticleId, mo.division_id) IS NOT NULL;

            SET @PricedCount = @@ROWCOUNT;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH

        SELECT @LinkedCount AS LinkedCount, @PricedCount AS PricedCount;
        RETURN;
    END

    -- =======================================================================
    -- CREATE / UPDATE / DELETE
    -- =======================================================================
    IF @Action NOT IN ('CREATE', 'UPDATE', 'DELETE')
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END

    DECLARE @DivisionId INT;
    SELECT @DivisionId = division_id
    FROM resources
    WHERE resource_id = @ResourceId AND deleted_at IS NULL;

    IF @DivisionId IS NULL
    BEGIN
        RAISERROR('Operator wajib dipilih.', 16, 1);
        RETURN;
    END

    -- ----- Validasi isi (CREATE & UPDATE) -----
    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        SET @WorkDescription = NULLIF(LTRIM(RTRIM(ISNULL(@WorkDescription, N''))), N'');
        SET @SizeName = NULLIF(LTRIM(RTRIM(ISNULL(@SizeName, ''))), '');
        SET @Note = NULLIF(LTRIM(RTRIM(ISNULL(@Note, N''))), N'');

        IF @WorkDescription IS NULL
        BEGIN
            RAISERROR('Deskripsi kerjaan wajib diisi.', 16, 1);
            RETURN;
        END

        -- Qty TIDAK divalidasi > 0: 0 dan minus keduanya sah (minus = catatan potongan).
        IF @Qty IS NULL
        BEGIN
            RAISERROR('Qty wajib diisi.', 16, 1);
            RETURN;
        END

        IF ISNULL(@RejectQty, 0) < 0
        BEGIN
            RAISERROR('Reject tidak boleh minus.', 16, 1);
            RETURN;
        END

        -- Baris minus adalah catatan potongan -- tanpa kronologi di catatan, admin
        -- produksi tidak punya dasar menentukan nominalnya.
        IF @Qty < 0 AND @Note IS NULL
        BEGIN
            RAISERROR('Qty minus adalah catatan potongan -- catatan wajib diisi (kronologi dan usulan potongan).', 16, 1);
            RETURN;
        END

        IF @ArticleId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM articles WHERE article_id = @ArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Artikel tidak ditemukan.', 16, 1);
            RETURN;
        END
    END

    -- ----- Baris yang diubah/dihapus harus ada, milik divisi ini, dan BELUM lock -----
    IF @Action IN ('UPDATE', 'DELETE')
    BEGIN
        DECLARE @RowDivisionId INT, @RowLockId INT;

        SELECT @RowDivisionId = division_id, @RowLockId = lock_id
        FROM manual_outputs
        WHERE manual_output_id = @ManualOutputId AND deleted_at IS NULL;

        IF @RowDivisionId IS NULL
        BEGIN
            RAISERROR('Output manual tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @RowDivisionId <> @DivisionId
        BEGIN
            RAISERROR('Output manual ini bukan milik divisi Anda.', 16, 1);
            RETURN;
        END

        -- Guard lock berlaku untuk SEMUA jalur, termasuk Super Admin (Bagian 3.2):
        -- tidak ada parameter "paksa" di SP ini dan memang tidak boleh ada.
        IF @RowLockId IS NOT NULL
        BEGIN
            RAISERROR('LOCKED|Data sudah di-lock. Ajukan unlock untuk mengubah.', 16, 1);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO manual_outputs (resource_id, division_id, article_id, work_description,
                                    size_name, qty, reject_qty, note, created_at, created_by)
        VALUES (@ResourceId, @DivisionId, @ArticleId, @WorkDescription,
                @SizeName, @Qty, ISNULL(@RejectQty, 0), @Note, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        -- division_id ikut disegarkan: resource bisa dipindah divisi sejak baris dibuat,
        -- dan kolom itu hanyalah salinan dari resources (bukan input user).
        UPDATE manual_outputs
        SET resource_id = @ResourceId,
            division_id = @DivisionId,
            article_id = @ArticleId,
            work_description = @WorkDescription,
            size_name = @SizeName,
            qty = @Qty,
            reject_qty = ISNULL(@RejectQty, 0),
            note = @Note,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE manual_output_id = @ManualOutputId AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE manual_outputs
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE manual_output_id = @ManualOutputId AND deleted_at IS NULL;
    END
END;
GO

-- ===========================================================================
-- SIS_ManualOutput_LinkArticle -- nama yang diminta Prompt 83 Bagian 3.3.
--
-- Isinya SENGAJA cuma meneruskan ke SIS_ManualOutput_Manage: aturan CLAUDE.md
-- menaruh semua Create/Update/Delete di satu SP _Manage dengan @Action, sementara
-- prompt menyebut nama SP ini secara eksplisit. Dua-duanya dipenuhi tanpa
-- menduplikasi logika -- jangan menyalin isi LINK_ARTICLE ke sini.
-- ===========================================================================
CREATE OR ALTER PROCEDURE SIS_ManualOutput_LinkArticle
    @ManualOutputIds VARCHAR(MAX) = NULL,   -- CSV; satu baris boleh pakai @ManualOutputId
    @ManualOutputId  INT = NULL,
    @ArticleId       INT = NULL,
    @UserId          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    EXEC SIS_ManualOutput_Manage
        @Action = 'LINK_ARTICLE',
        @ManualOutputIds = @ManualOutputIds,
        @ManualOutputId = @ManualOutputId,
        @ArticleId = @ArticleId,
        @UserId = @UserId;
END;
GO
