/* =============================================================
   Prompt 80 -- Station Bundling: Scan Stok Bundle.

   SIS_CuttingBundle_Lookup : cari satu bundle cutting dari hasil scan QR /
                              kode yang diketik manual (TIDAK mengubah apa pun)
   SIS_CuttingBundle_Take   : ambil N bundle sekaligus -> stock_status = TAKEN
                              + tulis log workflow Bundling

   ---------------------------------------------------------------
   Kenapa log-nya DITULIS ULANG di sini, bukan memanggil SIS_Bundle_Manage:
   runner seri 78-80 melarang mengubah alur bundle manual ("buat varian baru"),
   dan SIS_Bundle_Manage hanya punya action CREATE yang MEMBUAT bundle baru --
   tidak ada action yang cuma memasangkan log ke bundle yang sudah ada. Blok
   INSERT di bawah karena itu SENGAJA menyalin blok log di sp_Bundle_Manage.sql
   action CREATE (Prompt 17/23/25/34/40, aturan #7/#10/#15/#18 di kepala file itu).
   Kalau blok di sana berubah, blok di sini ikut disesuaikan.

   Prompt 80 dulu membuat log Bundling PENDING karena bundle cutting dibentuk
   jauh sebelum Line diketahui. Prompt 81 MEMBATALKAN itu: Line tujuan dipilih
   saat bundle discan di stasiun Bundling, jadi lognya langsung diterima seperti
   bundle manual. Tidak ada lagi bundle cutting yang beredar tanpa pemilik.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   SIS_CuttingBundle_Lookup

   @Code boleh:
     - URL QR penuh : http://host/b/B26-005692
     - serial       : B26-005692
     - kode cutting : H06-M-03   (tidak unik lintas artikel -> lihat @ArticleId)

   Kode cutting yang cocok di LEBIH DARI SATU artikel ditolak dengan pesan yang
   menyebut artikelnya, supaya operator memakai QR atau serial.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_CuttingBundle_Lookup
    @Code      VARCHAR(300),
    @ArticleId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Key VARCHAR(300) = UPPER(LTRIM(RTRIM(ISNULL(@Code, ''))));

    IF @Key = ''
    BEGIN
        RAISERROR('Kode bundle kosong.', 16, 1);
        RETURN;
    END

    -- Buang bagian URL di depan kalau yang discan adalah link QR ({base}/b/<serial>).
    DECLARE @Pos INT = CHARINDEX('/B/', @Key);
    IF @Pos > 0 SET @Key = SUBSTRING(@Key, @Pos + 3, 300);

    -- Buang query string / slash sisa.
    SET @Key = REPLACE(REPLACE(@Key, '?', '/'), '#', '/');
    IF CHARINDEX('/', @Key) > 0 SET @Key = LEFT(@Key, CHARINDEX('/', @Key) - 1);
    SET @Key = LTRIM(RTRIM(@Key));

    DECLARE @BundleId INT;

    -- 1. serial (unik global)
    SELECT @BundleId = bundle_id
    FROM bundles
    WHERE serial = @Key AND deleted_at IS NULL;

    -- 2. kode cutting (unik per artikel saja)
    IF @BundleId IS NULL
    BEGIN
        DECLARE @Cocok INT = (
            SELECT COUNT(*) FROM bundles
            WHERE cutting_code = @Key AND deleted_at IS NULL
              AND (@ArticleId IS NULL OR article_id = @ArticleId)
        );

        IF @Cocok > 1
        BEGIN
            DECLARE @Artikel VARCHAR(500) = STUFF((
                SELECT ', ' + ISNULL(p.no_po, '') + ' ' + a.article_name
                FROM bundles b
                INNER JOIN articles a ON a.article_id = b.article_id
                INNER JOIN projects p ON p.project_id = a.project_id
                WHERE b.cutting_code = @Key AND b.deleted_at IS NULL
                  AND (@ArticleId IS NULL OR b.article_id = @ArticleId)
                FOR XML PATH('')), 1, 2, '');

            RAISERROR('Kode %s ada di beberapa artikel (%s). Scan QR-nya atau ketik serial bundle.', 16, 1, @Key, @Artikel);
            RETURN;
        END

        SELECT @BundleId = bundle_id
        FROM bundles
        WHERE cutting_code = @Key AND deleted_at IS NULL
          AND (@ArticleId IS NULL OR article_id = @ArticleId);
    END

    IF @BundleId IS NULL
    BEGIN
        RAISERROR('Bundle %s tidak ditemukan.', 16, 1, @Key);
        RETURN;
    END

    -- Bundle manual TIDAK bisa diambil lewat jalur ini (keputusan desain §6: alur
    -- bundle manual tetap seperti semula).
    IF EXISTS (SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND source <> 'CUTTING')
    BEGIN
        RAISERROR('Bukan bundle cutting -- bundle ini dibuat manual, pakai alur bundle biasa.', 16, 1);
        RETURN;
    END

    DECLARE @Status VARCHAR(10), @TakenAt DATETIME2, @TakenBy VARCHAR(150), @Kode VARCHAR(30);
    SELECT @Status = b.stock_status, @TakenAt = b.taken_at, @Kode = b.cutting_code,
           @TakenBy = res.resource_name
    FROM bundles b
    LEFT JOIN resources res ON res.resource_id = b.taken_by_resource_id
    WHERE b.bundle_id = @BundleId;

    IF @Status <> 'STOCK'
    BEGIN
        -- Argumen RAISERROR harus variabel atau konstanta, BUKAN ekspresi (ISNULL/
        -- CONVERT di dalam daftar argumen = syntax error), jadi dirapikan dulu.
        DECLARE @Kapan VARCHAR(40) = ISNULL(CONVERT(VARCHAR(20), @TakenAt, 120), '-');
        SET @TakenBy = ISNULL(@TakenBy, 'Bundling');
        RAISERROR('Bundle %s sudah diambil %s pada %s.', 16, 1, @Kode, @TakenBy, @Kapan);
        RETURN;
    END

    -- Prompt 81: ArticleId + BundlingTargetDivisionId dipakai client untuk memuat pilihan
    -- Line tujuan lewat endpoint resources/{divisionId} yang sudah ada. SENGAJA bukan
    -- SIS_Station_ReceiverOptions: SP itu mengembalikan kolom ResourceId, sedangkan
    -- ResourceLookupDto menuntut Id, jadi endpoint receiver-options melempar 500 dan
    -- client (yang menelan error jadi list kosong) tidak pernah dapat Line. Divisi di
    -- bawah ini dihitung dengan definisi yang SAMA dengan @BundlingTargetDivisionId di
    -- SIS_CuttingBundle_Take, jadi pilihan UI dan validasi SP tidak bisa berbeda.
    SELECT
        b.bundle_id     AS BundleId,
        b.cutting_code  AS CuttingCode,
        b.serial        AS Serial,
        p.no_po         AS NoPo,
        p.project_name  AS ProjectName,
        a.article_name  AS ArticleName,
        spd.size_name   AS SizeName,
        b.qty           AS Qty,
        b.set_no        AS SetNo,
        b.number_from   AS NumberFrom,
        b.number_to     AS NumberTo,
        s.spread_code   AS SpreadCode,
        s.spread_date   AS SpreadDate,
        b.article_id    AS ArticleId,
        (SELECT TOP 1 nx.division_id
         FROM article_workflows nx
         WHERE nx.article_id = b.article_id AND nx.deleted_at IS NULL AND nx.inactive_at IS NULL
           AND nx.sort_order > bw.sort_order
         ORDER BY nx.sort_order ASC) AS BundlingTargetDivisionId
    FROM bundles b
    INNER JOIN spreads s ON s.spread_id = b.spread_id
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN article_workflows bw ON bw.article_id = b.article_id
        AND bw.deleted_at IS NULL AND bw.is_bundling = 1
    WHERE b.bundle_id = @BundleId;
END;
GO

/* ============================================================
   SIS_CuttingBundle_Take

   @BundleIdsJson : [123, 124, ...]  (hasil scan, boleh banyak sekaligus)
   @ResourceId    : resource operator sesi di stasiun Bundling -- dipakai sebagai
                    bundles.taken_by_resource_id DAN pelaksana log Bundling
                    (= @BundlingResourceId di SIS_Bundle_Manage CREATE).
   @UserId        : user sistem stasiun (appsettings Station:SystemUserId) --
                    Employee/resource TIDAK pernah jadi created_by (aturan CLAUDE.md).

   Satu transaksi untuk SEMUA bundle: kalau ada satu yang tidak memenuhi syarat,
   tidak ada yang berubah.

   ---------------------------------------------------------------
   Prompt 81 -- sistem CLAIM (@TargetResourceId WAJIB, @EmployeeId opsional):

   Bundle cutting TIDAK boleh lagi diambil tanpa Line tujuan. @TargetResourceId
   kosong = RAISERROR; jalur "pending" Prompt 80 (log Bundling tanpa penerima)
   sengaja DIHAPUS supaya tidak ada bundle yang beredar tanpa pemilik.
   Konsekuensi yang memang dikehendaki: artikel yang workflow-nya tidak punya step
   sesudah Bundling tidak bisa mengambil bundle sama sekali -- perbaiki workflow-nya
   dulu.

   Claim: bundles.resource_id/employee_id terisi dan log Bundling langsung diterima
   (received_at / received_by_resource_id), mengikuti aturan #10 sp_Bundle_Manage.sql
   (Prompt 25).

   Label penyerahan (BUNDLE_LABEL, berisi nama Line + penjahit) TIDAK dicetak di
   sini: API memanggil SIS_Bundle_ReprintLabel per bundle setelah SP ini sukses,
   supaya result set tidak campur dan SP label yang sudah ada tidak diubah.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_CuttingBundle_Take
    @BundleIdsJson    NVARCHAR(MAX),
    @ResourceId       INT,
    @UserId           INT = NULL,
    @TargetResourceId INT = NULL,
    @EmployeeId       INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT CAST([value] AS INT) AS bundle_id
    INTO #ids
    FROM OPENJSON(ISNULL(@BundleIdsJson, '[]'));

    IF NOT EXISTS (SELECT 1 FROM #ids)
    BEGIN
        RAISERROR('Belum ada bundle yang discan.', 16, 1);
        RETURN;
    END

    IF @ResourceId IS NULL
    BEGIN
        RAISERROR('Operator wajib dipilih.', 16, 1);
        RETURN;
    END

    -- Semua bundle harus ada, hidup, hasil cutting, dan masih di stok.
    DECLARE @Hilang INT = (
        SELECT COUNT(*) FROM #ids i
        WHERE NOT EXISTS (SELECT 1 FROM bundles b WHERE b.bundle_id = i.bundle_id AND b.deleted_at IS NULL)
    );
    IF @Hilang > 0
    BEGIN
        RAISERROR('%d bundle tidak ditemukan. Muat ulang daftar scan.', 16, 1, @Hilang);
        RETURN;
    END

    DECLARE @BukanCutting VARCHAR(30) = (
        SELECT TOP 1 ISNULL(b.cutting_code, b.serial) FROM bundles b
        INNER JOIN #ids i ON i.bundle_id = b.bundle_id
        WHERE b.source <> 'CUTTING'
    );
    IF @BukanCutting IS NOT NULL
    BEGIN
        RAISERROR('Bundle %s bukan bundle cutting.', 16, 1, @BukanCutting);
        RETURN;
    END

    DECLARE @SudahKode VARCHAR(30), @SudahBy VARCHAR(150), @SudahAt DATETIME2;
    SELECT TOP 1 @SudahKode = b.cutting_code, @SudahBy = res.resource_name, @SudahAt = b.taken_at
    FROM bundles b
    INNER JOIN #ids i ON i.bundle_id = b.bundle_id
    LEFT JOIN resources res ON res.resource_id = b.taken_by_resource_id
    WHERE b.stock_status <> 'STOCK';

    IF @SudahKode IS NOT NULL
    BEGIN
        DECLARE @SudahKapan VARCHAR(40) = ISNULL(CONVERT(VARCHAR(20), @SudahAt, 120), '-');
        SET @SudahBy = ISNULL(@SudahBy, 'Bundling');
        RAISERROR('Bundle %s sudah diambil %s pada %s.', 16, 1, @SudahKode, @SudahBy, @SudahKapan);
        RETURN;
    END

    -- Semua bundle harus dari SATU artikel: step Bundling, divisi dan applock-nya
    -- per artikel, dan satu sesi scan di lapangan memang satu artikel.
    DECLARE @ArticleId INT;
    SELECT @ArticleId = MIN(b.article_id) FROM bundles b INNER JOIN #ids i ON i.bundle_id = b.bundle_id;

    IF EXISTS (
        SELECT 1 FROM bundles b INNER JOIN #ids i ON i.bundle_id = b.bundle_id
        WHERE b.article_id <> @ArticleId
    )
    BEGIN
        RAISERROR('Bundle yang discan berasal dari artikel berbeda. Ambil per artikel.', 16, 1);
        RETURN;
    END

    -- Step Bundling implisit artikel ini (pola sp_Bundle_Manage.sql CREATE).
    DECLARE @BundlingStepId INT, @BundlingDivisionId INT, @BundlingSortOrder INT;
    SELECT @BundlingStepId = article_workflow_id, @BundlingDivisionId = division_id,
           @BundlingSortOrder = sort_order
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

    IF @BundlingStepId IS NULL
    BEGIN
        RAISERROR('Workflow artikel belum memiliki step Bundling. Terapkan ulang workflow artikel dulu.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM resources
        WHERE resource_id = @ResourceId AND division_id = @BundlingDivisionId
          AND is_active = 1 AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Operator bukan resource divisi Bundling artikel ini.', 16, 1);
        RETURN;
    END

    DECLARE @BundlingTargetDivisionId INT;
    SELECT TOP 1 @BundlingTargetDivisionId = division_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL
      AND sort_order > @BundlingSortOrder
    ORDER BY sort_order ASC;

    /* ---- Prompt 81: validasi claim (WAJIB) ------------------------------
       Client mengirim 0 untuk "belum dipilih" -- dinormalkan ke NULL dulu. */
    IF ISNULL(@TargetResourceId, 0) <= 0 SET @TargetResourceId = NULL;
    IF ISNULL(@EmployeeId, 0) <= 0 SET @EmployeeId = NULL;

    IF @TargetResourceId IS NULL
    BEGIN
        RAISERROR('Line tujuan wajib dipilih.', 16, 1);
        RETURN;
    END

    -- Line tujuan harus resource divisi PENERIMA log Bundling (= target_division_id
    -- di bawah). Prompt 40 SS7 mengunci pelaksana step berikutnya agar sama dengan
    -- received_by_resource_id, jadi resource di luar divisi itu membuat bundle buntu.
    IF @BundlingTargetDivisionId IS NULL
    BEGIN
        RAISERROR('Workflow artikel belum punya step sesudah Bundling, bundle tidak bisa diklaim ke Line.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM resources
        WHERE resource_id = @TargetResourceId AND division_id = @BundlingTargetDivisionId
          AND is_active = 1 AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Line tujuan tidak valid untuk artikel ini.', 16, 1);
        RETURN;
    END

    -- Pesan sama dengan bundle manual (sp_Bundle_Manage.sql, Prompt 32).
    IF @EmployeeId IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM employees
        WHERE employee_id = @EmployeeId AND resource_id = @TargetResourceId AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Penjahit bukan anggota line ini.', 16, 1);
        RETURN;
    END

    -- Step non-bundle TERAKHIR (mis. Cutting) -- yang di-auto-receive, persis
    -- sp_Bundle_Manage.sql aturan #7 (dipersempit Prompt 23).
    DECLARE @LastNonBundleStepId INT;
    SELECT TOP 1 @LastNonBundleStepId = article_workflow_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL
      AND requires_bundle = 0
    ORDER BY sort_order DESC;

    DECLARE @LockResourceArticle VARCHAR(60) = 'article_workflow_restructure_' + CAST(@ArticleId AS VARCHAR(20));

    BEGIN TRAN;
    BEGIN TRY
        -- Applock per artikel, resource SAMA PERSIS dengan SIS_Bundle_Manage /
        -- SIS_ArticleWorkflow_Restructure / SIS_WorkflowLog_Manage (Prompt 50).
        DECLARE @LockResultArticle INT;
        EXEC @LockResultArticle = sp_getapplock
            @Resource = @LockResourceArticle, @LockMode = 'Exclusive',
            @LockOwner = 'Transaction', @LockTimeout = 10000;

        IF @LockResultArticle < 0
        BEGIN
            RAISERROR('Gagal mengunci artikel. Coba lagi.', 16, 1);
            ROLLBACK TRAN;
            RETURN;
        END

        -- Cek ulang DI DALAM lock: bundle yang sama bisa discan dua perangkat sekaligus.
        IF EXISTS (
            SELECT 1 FROM bundles b INNER JOIN #ids i ON i.bundle_id = b.bundle_id
            WHERE b.stock_status <> 'STOCK' OR b.deleted_at IS NOT NULL
        )
        BEGIN
            RAISERROR('Ada bundle yang baru saja diambil perangkat lain. Scan ulang.', 16, 1);
            ROLLBACK TRAN;
            RETURN;
        END

        -- Prompt 81: Line tujuan (resource_id) & penjahit ikut ditulis di sini -- sama
        -- artinya dengan bundles.resource_id pada bundle manual.
        UPDATE b
        SET stock_status = 'TAKEN',
            taken_at = SYSDATETIME(),
            taken_by_resource_id = @ResourceId,
            resource_id = @TargetResourceId,
            employee_id = @EmployeeId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        FROM bundles b
        INNER JOIN #ids i ON i.bundle_id = b.bundle_id;

        -- Log Bundling per bundle -- Prompt 81: LANGSUNG diterima oleh Line tujuan.
        -- received_by_resource_id = Line (resource divisi TUJUAN), bukan @ResourceId
        -- (resource Bundling), persis aturan #10 sp_Bundle_Manage.sql.
        INSERT INTO article_workflow_logs (
            article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
            qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing,
            remark, target_division_id, received_at, received_by_resource_id, received_remark,
            created_at, created_by
        )
        SELECT
            @BundlingStepId, b.bundle_id, NULL, @BundlingDivisionId, @ResourceId, NULL,
            b.qty, 0, 0, 0,
            NULL, @BundlingTargetDivisionId,
            SYSDATETIME(), @TargetResourceId, 'Otomatis: bundle cutting diklaim Line',
            SYSDATETIME(), @UserId
        FROM bundles b
        INNER JOIN #ids i ON i.bundle_id = b.bundle_id
        ORDER BY b.bundle_seq;

        -- Auto-receive log step non-bundle terakhir (Cutting) yang masih pending --
        -- SAMA PERSIS dengan pembuatan bundle manual.
        UPDATE awl
        SET received_at = SYSDATETIME(),
            received_by_resource_id = @ResourceId,
            received_remark = 'Otomatis: bundle cutting diambil Bundling'
        FROM article_workflow_logs awl
        WHERE awl.article_workflow_id = @LastNonBundleStepId
          AND awl.deleted_at IS NULL
          AND awl.received_at IS NULL
          AND awl.target_division_id IS NOT NULL;

        DECLARE @Count INT = (SELECT COUNT(*) FROM #ids);
        DECLARE @Pcs INT = (SELECT SUM(b.qty) FROM bundles b INNER JOIN #ids i ON i.bundle_id = b.bundle_id);

        COMMIT TRAN;

        SELECT @Count AS TakenCount, @Pcs AS TotalPcs;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO
