/* =============================================================
   Prompt 78 -- Module Cutting: stored procedure.

   Mutasi : SIS_Spread_Manage        (CREATE / UPDATE_HEADER / DELETE / MARK_PRINTED)
            SIS_SpreadBundle_Manage  (UPDATE_QTY / ADD / REMOVE)
            SIS_CuttingBundle_Print  (enqueue stiker -- pola SIS_Bundle_ReprintLabel)
   Hitung : SIS_Cutting_SuggestBundles, SIS_Cutting_NextNumber, SIS_Cutting_NextSpreadCode
   Baca   : SIS_Cutting_Articles, SIS_Cutting_StockSummary, SIS_Cutting_TakenToday,
            SIS_Spread_List, SIS_Spread_Detail

   Aturan yang ditegakkan di SP (bukan cuma di API):
    1. Total qty bundle per SET harus = spreads.sheets_per_set. Ini dijaga di CREATE
       dan di SETIAP action SIS_SpreadBundle_Manage -- karena itu ketiga action
       (UPDATE_QTY/ADD/REMOVE) menerima @BundlesJson berisi qty baru SELURUH bundle
       di set yang disentuh, bukan satu bundle lepas: mengubah satu bundle saja
       secara matematis tidak mungkin menjaga total (lihat uji Prompt 79).
    2. Bundle source='CUTTING' yang sudah stock_status='TAKEN' tidak bisa
       diubah/dihapus dari sisi cutting -- termasuk kalau yang berubah cuma
       rentang nomor atau kode bundle-nya karena pergeseran bundle lain.
    3. bundle_seq urut per SPREAD per SIZE (set 1 dulu, lanjut set 2, dst), jadi
       ADD/REMOVE di set awal ikut menggeser kode bundle set sesudahnya di size
       yang sama -> semua yang bergeser diberi needs_reprint = 1.
    4. Rentang nomor pcs: blok per set FIX (number_from size + (set-1) * lembar),
       jadi ADD/REMOVE tidak pernah menggeser rentang SET lain.
    5. serial & bundle_no digenerate persis seperti bundle manual
       (sql/sp_Bundle_Manage.sql: applock 'bundle_serial_seq', format B{yy}-{6 digit},
       bundle_no urut per project termasuk baris soft-deleted) supaya QR
       {PublicBaseUrl}/b/<serial> dan halaman /b/<serial> tetap jalan tanpa perubahan.
    6. Bundle cutting SENGAJA dibuat TANPA baris article_workflow_logs. Log
       Cutting -> Bundling baru ditulis saat Bundling mengambilnya lewat
       SIS_CuttingBundle_Take (Prompt 80) -- saat dibuat, Line tujuan belum diketahui
       (bundle manual mewajibkan @ResourceId, bundle cutting tidak bisa).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* ============================================================
   SIS_Cutting_SuggestBundles -- saran pembagian bundle per set.

   Algoritma (keputusan desain §3):
     n    = ROUND(lembar / target), minimal 1
     base = lembar / n ; rem = lembar % n
     bundle 1..rem = base + 1, sisanya base      (sisa ke bundle PERTAMA)
     kalau qty terbesar > target + 10  ->  n + 1, ulang
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_SuggestBundles
    @Sheets INT,
    @Target INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF ISNULL(@Target, 0) <= 0 SET @Target = 50;

    IF ISNULL(@Sheets, 0) <= 0
    BEGIN
        SELECT CAST(NULL AS INT) AS BundleSeq, CAST(NULL AS INT) AS Qty WHERE 1 = 0;
        RETURN;
    END

    DECLARE @MaxPer INT = @Target + 10;
    DECLARE @n INT = CAST(ROUND(CAST(@Sheets AS DECIMAL(18, 4)) / @Target, 0) AS INT);
    IF @n < 1 SET @n = 1;

    DECLARE @base INT, @rem INT;

    WHILE 1 = 1
    BEGIN
        SET @base = @Sheets / @n;
        SET @rem = @Sheets % @n;

        -- Qty terbesar = base (+1 kalau ada sisa yang dititipkan ke bundle depan).
        IF @base + CASE WHEN @rem > 0 THEN 1 ELSE 0 END <= @MaxPer BREAK;

        -- Jaga-jaga: n tidak boleh melewati jumlah lembar (qty minimal 1 pcs/bundle).
        IF @n >= @Sheets BREAK;

        SET @n += 1;
    END

    SELECT TOP (@n)
        CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS BundleSeq,
        CAST(@base + CASE WHEN ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) <= @rem THEN 1 ELSE 0 END AS INT) AS Qty
    FROM sys.all_objects
    ORDER BY BundleSeq;
END;
GO

/* ============================================================
   SIS_Cutting_NextNumber -- nomor pcs berikutnya untuk artikel + size.

   Lanjut dari MAX(number_to) spread_sizes artikel+size yang sama pada hamparan
   yang TIDAK dihapus; kalau belum ada sama sekali = 1.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_NextNumber
    @ArticleId     INT,
    @ArticleSizeId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM article_sizes
        WHERE article_size_id = @ArticleSizeId AND article_id = @ArticleId AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Ukuran tidak ditemukan untuk artikel ini.', 16, 1);
        RETURN;
    END

    SELECT ISNULL(MAX(ss.number_to), 0) + 1 AS NextFrom
    FROM spread_sizes ss
    INNER JOIN spreads s ON s.spread_id = ss.spread_id AND s.deleted_at IS NULL
    WHERE ss.article_size_id = @ArticleSizeId;
END;
GO

/* ============================================================
   SIS_Cutting_NextSpreadCode -- kode hamparan berikutnya.

   Format: <huruf bundle project>-H<nn>, mis. A-H01, B-H02 (huruf dari
   projects.bundle_letter, Prompt 27 -- A-Z berputar per project). Project lama
   yang bundle_letter-nya NULL jatuh ke format lama tanpa awalan: H01.
   Huruf dibawa supaya kode bundle (A-H01-M-03) membedakan project, bukan cuma
   artikel -- lihat komentar cutting_code di alter_78_cutting_schema.sql.

   Nomor urut per ARTIKEL, dihitung dari angka SESUDAH 'H' TERAKHIR pada kode
   yang sudah ada; kode manual di luar pola itu diabaikan dalam perhitungan.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_NextSpreadCode
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Angka hamparan = bagian setelah 'H' terakhir ('A-H07' -> 7, 'H07' -> 7).
    DECLARE @Next INT;
    SELECT @Next = ISNULL(MAX(TRY_CAST(
               SUBSTRING(s.spread_code,
                         LEN(s.spread_code) - CHARINDEX('H', REVERSE(s.spread_code)) + 2,
                         18) AS INT)), 0) + 1
    FROM spreads s
    WHERE s.article_id = @ArticleId
      AND s.deleted_at IS NULL
      AND CHARINDEX('H', s.spread_code) > 0;

    IF @Next IS NULL SET @Next = 1;

    DECLARE @Letter CHAR(1);
    SELECT @Letter = p.bundle_letter
    FROM articles a
    INNER JOIN projects p ON p.project_id = a.project_id
    WHERE a.article_id = @ArticleId;

    DECLARE @Nomor VARCHAR(10) = RIGHT('00' + CAST(@Next AS VARCHAR(10)),
        CASE WHEN @Next > 99 THEN LEN(CAST(@Next AS VARCHAR(10))) ELSE 2 END);

    SELECT CASE WHEN @Letter IS NULL THEN '' ELSE @Letter + '-' END + 'H' + @Nomor AS NextCode;
END;
GO

/* ============================================================
   SIS_Cutting_Articles -- dropdown artikel aktif + target pcs/bundle.
   "Aktif" = artikel hidup pada project hidup yang TIDAK berstatus manual
   (ON_HOLD / COMPLETED / CANCELLED) -- sama dengan guard pembuatan bundle
   di sp_Bundle_Manage.sql.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_Articles
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        a.article_id          AS ArticleId,
        a.article_name         AS ArticleName,
        a.bundle_target_qty    AS BundleTargetQty,
        p.project_id           AS ProjectId,
        p.no_po                AS NoPo,
        p.project_name         AS ProjectName,
        (SELECT COUNT(*) FROM spreads s WHERE s.article_id = a.article_id AND s.deleted_at IS NULL) AS SpreadCount
    FROM articles a
    INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
    WHERE a.deleted_at IS NULL
      AND p.manual_status IS NULL
    -- Nomor PO terbaru di ATAS (Prompt 82). Diurutkan dari angka SEBELUM titik
    -- pertama ("318.AGS.2606" -> 318) supaya tetap benar waktu nomornya lewat 999;
    -- PO yang tidak mengikuti pola (atau kosong) jatuh ke urutan teks dan ada di bawah.
    ORDER BY TRY_CAST(LEFT(p.no_po, CHARINDEX('.', p.no_po + '.') - 1) AS INT) DESC,
             p.no_po DESC, a.article_name ASC;
END;
GO

/* ============================================================
   SIS_Spread_Manage -- CREATE / UPDATE_HEADER / DELETE / MARK_PRINTED

   @SizesJson   : [{"articleSizeId":4117,"setCount":6}, ...]
   @BundlesJson : [{"articleSizeId":4117,"setNo":1,"qty":55}, ...]  -- URUT
                  (urutan array = urutan bundle di dalam set)
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Spread_Manage
    @Action        VARCHAR(20),
    @Id            INT = NULL,
    @ArticleId     INT = NULL,
    @SpreadCode    VARCHAR(20) = NULL,
    @SpreadDate    DATE = NULL,
    @SetCount      INT = NULL,
    @SheetsPerSet  INT = NULL,
    @Note          VARCHAR(500) = NULL,
    @SizesJson     NVARCHAR(MAX) = NULL,
    @BundlesJson   NVARCHAR(MAX) = NULL,
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        SET @SpreadCode = NULLIF(LTRIM(RTRIM(@SpreadCode)), '');

        IF @ArticleId IS NULL OR @SpreadCode IS NULL
        BEGIN
            RAISERROR('Artikel dan kode hamparan wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM articles WHERE article_id = @ArticleId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Artikel tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- Project terkunci (manual_status) menolak pembuatan hamparan, sama seperti
        -- pembuatan bundle manual (sp_Bundle_Manage.sql aturan #8).
        DECLARE @LockStatus VARCHAR(20), @LockReason VARCHAR(255);
        SELECT @LockStatus = p.manual_status, @LockReason = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @ArticleId;

        IF @LockStatus IS NOT NULL
        BEGIN
            DECLARE @LockLabel VARCHAR(30) = CASE @LockStatus
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus END;
            DECLARE @LockSuffix VARCHAR(300) = CASE WHEN LTRIM(RTRIM(ISNULL(@LockReason, ''))) <> ''
                THEN ' (Alasan: ' + @LockReason + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel, @LockSuffix);
            RETURN;
        END

        IF ISNULL(@SetCount, 0) <= 0 OR ISNULL(@SheetsPerSet, 0) <= 0
        BEGIN
            RAISERROR('Jumlah set dan lembar per set harus lebih dari 0.', 16, 1);
            RETURN;
        END

        IF @SpreadDate IS NULL SET @SpreadDate = CAST(SYSDATETIME() AS DATE);

        IF EXISTS (
            SELECT 1 FROM spreads
            WHERE article_id = @ArticleId AND spread_code = @SpreadCode AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Kode hamparan %s sudah dipakai di artikel ini.', 16, 1, @SpreadCode);
            RETURN;
        END

        -- ---------- rincian size ----------
        -- numberFrom = nomor pcs awal pilihan user (Prompt 82). NULL/0 = pakai
        -- lanjutan otomatis dari hamparan terakhir artikel + size ini.
        SELECT articleSizeId AS article_size_id, setCount AS set_count,
               NULLIF(numberFrom, 0) AS number_from
        INTO #sizes
        FROM OPENJSON(ISNULL(@SizesJson, '[]'))
             WITH (articleSizeId INT '$.articleSizeId', setCount INT '$.setCount',
                   numberFrom INT '$.numberFrom')
        WHERE ISNULL(setCount, 0) > 0;

        IF NOT EXISTS (SELECT 1 FROM #sizes)
        BEGIN
            RAISERROR('Rincian set per size belum diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM #sizes z
            WHERE NOT EXISTS (
                SELECT 1 FROM article_sizes asz
                WHERE asz.article_size_id = z.article_size_id
                  AND asz.article_id = @ArticleId
                  AND asz.deleted_at IS NULL)
        )
        BEGIN
            RAISERROR('Ada ukuran yang bukan milik artikel ini.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #sizes WHERE number_from < 1)
        BEGIN
            RAISERROR('Nomor awal numbering harus 1 atau lebih.', 16, 1);
            RETURN;
        END

        DECLARE @SumSizeSets INT = (SELECT SUM(set_count) FROM #sizes);
        IF @SumSizeSets <> @SetCount
        BEGIN
            RAISERROR('Rincian size baru %d set dari %d set hamparan.', 16, 1, @SumSizeSets, @SetCount);
            RETURN;
        END

        -- ---------- bundle per set ----------
        SELECT CAST(j.[key] AS INT) AS ord, b.articleSizeId AS article_size_id, b.setNo AS set_no, b.qty
        INTO #b
        FROM OPENJSON(ISNULL(@BundlesJson, '[]')) j
        CROSS APPLY OPENJSON(j.value)
             WITH (articleSizeId INT '$.articleSizeId', setNo INT '$.setNo', qty INT '$.qty') b;

        IF NOT EXISTS (SELECT 1 FROM #b)
        BEGIN
            RAISERROR('Pembagian bundle belum diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM #b WHERE ISNULL(qty, 0) <= 0)
        BEGIN
            RAISERROR('Ada qty bundle yang kosong atau 0.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM #b b
            LEFT JOIN #sizes z ON z.article_size_id = b.article_size_id
            WHERE z.article_size_id IS NULL
               OR b.set_no < 1 OR b.set_no > z.set_count
        )
        BEGIN
            RAISERROR('Ada bundle dengan size atau nomor set yang tidak cocok dengan rincian.', 16, 1);
            RETURN;
        END

        -- Setiap set harus terisi dan totalnya pas.
        DECLARE @BadSet VARCHAR(100), @BadTotal INT;
        SELECT TOP 1
            @BadSet = spd.size_name + ' set ' + CAST(b.set_no AS VARCHAR(10)),
            @BadTotal = SUM(b.qty)
        FROM #b b
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        GROUP BY spd.size_name, b.set_no
        HAVING SUM(b.qty) <> @SheetsPerSet;

        IF @BadSet IS NOT NULL
        BEGIN
            RAISERROR('Total qty %s = %d, harus %d (lembar per set).', 16, 1, @BadSet, @BadTotal, @SheetsPerSet);
            RETURN;
        END

        IF EXISTS (
            SELECT 1
            FROM #sizes z
            LEFT JOIN (SELECT article_size_id, COUNT(DISTINCT set_no) AS sets FROM #b GROUP BY article_size_id) g
                   ON g.article_size_id = z.article_size_id
            WHERE ISNULL(g.sets, 0) <> z.set_count
        )
        BEGIN
            RAISERROR('Ada size yang jumlah setnya belum lengkap di pembagian bundle.', 16, 1);
            RETURN;
        END

        DECLARE @LockResourceArticle VARCHAR(60) = 'article_workflow_restructure_' + CAST(@ArticleId AS VARCHAR(20));

        BEGIN TRAN;
        BEGIN TRY
            -- Applock per artikel, resource SAMA PERSIS dengan SIS_Bundle_Manage /
            -- SIS_ArticleWorkflow_Restructure (sp_Bundle_Manage.sql, Prompt 50).
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

            DECLARE @LockResultSerial INT;
            EXEC @LockResultSerial = sp_getapplock
                @Resource = 'bundle_serial_seq', @LockMode = 'Exclusive',
                @LockOwner = 'Transaction', @LockTimeout = 10000;

            IF @LockResultSerial < 0
            BEGIN
                RAISERROR('Gagal mengunci penomoran serial bundle. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            INSERT INTO spreads (article_id, spread_code, spread_date, set_count, sheets_per_set,
                                 [status], note, created_at, created_by)
            VALUES (@ArticleId, @SpreadCode, @SpreadDate, @SetCount, @SheetsPerSet,
                    'DRAFT', NULLIF(LTRIM(RTRIM(@Note)), ''), SYSDATETIME(), @UserId);

            DECLARE @SpreadId INT = CAST(SCOPE_IDENTITY() AS INT);

            -- Rentang nomor per size: nomor awal dipilih user di form (Prompt 82);
            -- kalau tidak dikirim, lanjut dari hamparan terakhir artikel + size ini.
            DECLARE @ss TABLE (spread_size_id INT, article_size_id INT, set_count INT, number_from INT);

            INSERT INTO spread_sizes (spread_id, article_size_id, set_count, number_from, number_to)
            OUTPUT inserted.spread_size_id, inserted.article_size_id, inserted.set_count, inserted.number_from
                INTO @ss (spread_size_id, article_size_id, set_count, number_from)
            SELECT @SpreadId, z.article_size_id, z.set_count,
                   ISNULL(z.number_from, nx.NextFrom),
                   ISNULL(z.number_from, nx.NextFrom) + z.set_count * @SheetsPerSet - 1
            FROM #sizes z
            CROSS APPLY (
                SELECT ISNULL(MAX(ss2.number_to), 0) + 1 AS NextFrom
                FROM spread_sizes ss2
                INNER JOIN spreads s2 ON s2.spread_id = ss2.spread_id AND s2.deleted_at IS NULL
                WHERE ss2.article_size_id = z.article_size_id
            ) nx;

            -- ---------- bundle ----------
            -- Prompt 82: saring sequence_no = 0 (induk saja) -- serial anak '{serial}-{seq}'
            -- membuat RIGHT(serial, 6) tidak lagi murni angka.
            DECLARE @NextSerialNo INT = (SELECT ISNULL(MAX(CAST(RIGHT(serial, 6) AS INT)), 0) FROM bundles WHERE sequence_no = 0);
            DECLARE @Yy VARCHAR(2) = RIGHT(CAST(YEAR(SYSDATETIME()) AS VARCHAR(4)), 2);

            DECLARE @ProjectId INT = (SELECT project_id FROM articles WHERE article_id = @ArticleId);
            DECLARE @NextBundleNo INT = (
                SELECT ISNULL(MAX(b.bundle_no), 0)
                FROM bundles b
                INNER JOIN articles a ON a.article_id = b.article_id
                WHERE a.project_id = @ProjectId
            );

            ;WITH seq AS (
                SELECT b.ord, b.article_size_id, b.set_no, b.qty,
                       ss.spread_size_id, ss.number_from AS size_from,
                       spd.size_name,
                       ROW_NUMBER() OVER (PARTITION BY b.article_size_id ORDER BY b.set_no, b.ord) AS bundle_seq,
                       SUM(b.qty) OVER (PARTITION BY b.article_size_id, b.set_no
                                        ORDER BY b.ord ROWS UNBOUNDED PRECEDING) - b.qty AS before_in_set,
                       ROW_NUMBER() OVER (ORDER BY spd.sort_order, b.article_size_id, b.set_no, b.ord) AS rn
                FROM #b b
                INNER JOIN @ss ss ON ss.article_size_id = b.article_size_id
                INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
                INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
            )
            SELECT s.*,
                   s.size_from + (s.set_no - 1) * @SheetsPerSet + s.before_in_set AS number_from,
                   @SpreadCode + '-' + s.size_name + '-' + RIGHT('00' + CAST(s.bundle_seq AS VARCHAR(10)), 2) AS cutting_code,
                   'B' + @Yy + '-' + RIGHT('000000' + CAST(@NextSerialNo + s.rn AS VARCHAR(10)), 6) AS serial,
                   @NextBundleNo + s.rn AS bundle_no,
                   ISNULL(bs.max_sort, 0) + ROW_NUMBER() OVER (PARTITION BY s.article_size_id ORDER BY s.set_no, s.ord) AS sort_order
            INTO #ins
            FROM seq s
            OUTER APPLY (
                SELECT MAX(sort_order) AS max_sort FROM bundles
                WHERE article_size_id = s.article_size_id AND deleted_at IS NULL
            ) bs;

            IF EXISTS (SELECT 1 FROM #ins WHERE LEN(cutting_code) > 30)
            BEGIN
                RAISERROR('Kode bundle terlalu panjang. Pakai kode hamparan yang lebih pendek.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            INSERT INTO bundles (
                article_id, article_size_id, serial, bundle_no, qty, sort_order,
                resource_id, employee_id, remarks, created_at, created_by,
                spread_id, spread_size_id, cutting_code, set_no, bundle_seq,
                number_from, number_to, source, stock_status, needs_reprint
            )
            SELECT
                @ArticleId, i.article_size_id, i.serial, i.bundle_no, i.qty, i.sort_order,
                NULL, NULL, NULL, SYSDATETIME(), @UserId,
                @SpreadId, i.spread_size_id, i.cutting_code, i.set_no, i.bundle_seq,
                i.number_from, i.number_from + i.qty - 1, 'CUTTING', 'STOCK', 0
            FROM #ins i
            ORDER BY i.rn;

            DECLARE @Created INT = @@ROWCOUNT;

            -- Prompt 82: bundle hamparan selalu INDUK UTAMA -- root_bundle_id = dirinya
            -- sendiri (default kolom 0, diisi di sini karena identity baru terbit setelah
            -- INSERT set-based di atas).
            UPDATE bundles SET root_bundle_id = bundle_id
            WHERE spread_id = @SpreadId AND root_bundle_id = 0;

            COMMIT TRAN;

            SELECT @SpreadId AS NewId, @Created AS BundleCount;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'UPDATE_HEADER'
    BEGIN
        -- Hanya DRAFT. set_count / sheets_per_set TIDAK bisa diubah di sini: bundle
        -- & rentang nomor sudah dibentuk dari keduanya (hapus hamparan lalu buat ulang).
        DECLARE @CurStatus VARCHAR(10), @CurArticle INT;
        SELECT @CurStatus = [status], @CurArticle = article_id
        FROM spreads WHERE spread_id = @Id AND deleted_at IS NULL;

        IF @CurArticle IS NULL
        BEGIN
            RAISERROR('Hamparan tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @CurStatus <> 'DRAFT'
        BEGIN
            RAISERROR('Hamparan yang sudah dicetak tidak bisa diubah datanya.', 16, 1);
            RETURN;
        END

        SET @SpreadCode = NULLIF(LTRIM(RTRIM(@SpreadCode)), '');
        IF @SpreadCode IS NULL
        BEGIN
            RAISERROR('Kode hamparan wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM spreads
            WHERE article_id = @CurArticle AND spread_code = @SpreadCode
              AND spread_id <> @Id AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Kode hamparan %s sudah dipakai di artikel ini.', 16, 1, @SpreadCode);
            RETURN;
        END

        UPDATE spreads
        SET spread_code = @SpreadCode,
            spread_date = ISNULL(@SpreadDate, spread_date),
            note = NULLIF(LTRIM(RTRIM(@Note)), ''),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE spread_id = @Id;

        -- Kode bundle ikut kode hamparan -> susun ulang + tandai perlu cetak ulang.
        UPDATE b
        SET cutting_code = @SpreadCode + '-' + spd.size_name + '-' + RIGHT('00' + CAST(b.bundle_seq AS VARCHAR(10)), 2),
            needs_reprint = 1,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        FROM bundles b
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE b.spread_id = @Id AND b.deleted_at IS NULL
          AND b.cutting_code <> @SpreadCode + '-' + spd.size_name + '-' + RIGHT('00' + CAST(b.bundle_seq AS VARCHAR(10)), 2);
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM spreads WHERE spread_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Hamparan tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @TakenCount INT = (
            SELECT COUNT(*) FROM bundles
            WHERE spread_id = @Id AND deleted_at IS NULL AND stock_status = 'TAKEN'
        );

        IF @TakenCount > 0
        BEGIN
            RAISERROR('Hamparan tidak bisa dihapus: %d bundle sudah diambil Bundling.', 16, 1, @TakenCount);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            UPDATE bundles
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId,
                delete_reason = 'Hamparan dihapus'
            WHERE spread_id = @Id AND deleted_at IS NULL;

            UPDATE spreads
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE spread_id = @Id;

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'MARK_PRINTED'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM spreads WHERE spread_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Hamparan tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE spreads
        SET [status] = 'PRINTED',
            printed_at = ISNULL(printed_at, SYSDATETIME()),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE spread_id = @Id;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
    END
END;
GO

/* ============================================================
   SIS_SpreadBundle_Manage -- UPDATE_QTY / ADD / REMOVE

   Ketiga action bekerja pada SATU set (spread_size + set_no) dan selalu
   diakhiri guard "total qty set = sheets_per_set" (lihat catatan #1 di kepala
   file). @BundlesJson = [{"bundleId":123,"qty":60}, ...] berisi qty BARU untuk
   bundle yang ikut berubah; bundle lain di set itu dipakai qty-nya yang sekarang.

     UPDATE_QTY : @BundlesJson wajib.
     ADD        : @SpreadSizeId + @SetNo + @Qty (bundle baru di AKHIR set),
                  @BundlesJson opsional untuk menyeimbangkan bundle yang ada.
     REMOVE     : @BundleId (harus bundle TERAKHIR di set, masih STOCK),
                  @BundlesJson opsional untuk menyeimbangkan sisanya.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_SpreadBundle_Manage
    @Action        VARCHAR(20),
    @SpreadSizeId  INT = NULL,
    @SetNo         INT = NULL,
    @BundleId      INT = NULL,
    @Qty           INT = NULL,
    @BundlesJson   NVARCHAR(MAX) = NULL,
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action NOT IN ('UPDATE_QTY', 'ADD', 'REMOVE')
    BEGIN
        RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
        RETURN;
    END

    -- ---------- qty baru yang dikirim ----------
    SELECT bundleId AS bundle_id, qty
    INTO #chg
    FROM OPENJSON(ISNULL(@BundlesJson, '[]'))
         WITH (bundleId INT '$.bundleId', qty INT '$.qty')
    WHERE bundleId IS NOT NULL;

    -- ---------- tentukan set yang disentuh ----------
    IF @Action = 'UPDATE_QTY'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM #chg)
        BEGIN
            RAISERROR('Tidak ada perubahan qty yang dikirim.', 16, 1);
            RETURN;
        END

        SELECT TOP 1 @SpreadSizeId = b.spread_size_id, @SetNo = b.set_no
        FROM bundles b INNER JOIN #chg c ON c.bundle_id = b.bundle_id
        WHERE b.deleted_at IS NULL;
    END
    ELSE IF @Action = 'REMOVE'
    BEGIN
        SELECT @SpreadSizeId = spread_size_id, @SetNo = set_no
        FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL;
    END

    IF @SpreadSizeId IS NULL OR @SetNo IS NULL
    BEGIN
        RAISERROR('Bundle atau set tidak ditemukan.', 16, 1);
        RETURN;
    END

    DECLARE @SpreadId INT, @ArticleId INT, @ArticleSizeId INT, @SheetsPerSet INT,
            @SpreadCode VARCHAR(20), @SizeName VARCHAR(50), @SizeFrom INT, @SizeSets INT;

    SELECT @SpreadId = s.spread_id, @ArticleId = s.article_id, @SheetsPerSet = s.sheets_per_set,
           @SpreadCode = s.spread_code, @ArticleSizeId = ss.article_size_id,
           @SizeFrom = ss.number_from, @SizeSets = ss.set_count, @SizeName = spd.size_name
    FROM spread_sizes ss
    INNER JOIN spreads s ON s.spread_id = ss.spread_id AND s.deleted_at IS NULL
    INNER JOIN article_sizes asz ON asz.article_size_id = ss.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE ss.spread_size_id = @SpreadSizeId;

    IF @SpreadId IS NULL
    BEGIN
        RAISERROR('Hamparan tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @SetNo < 1 OR @SetNo > @SizeSets
    BEGIN
        RAISERROR('Nomor set %d tidak ada di size %s.', 16, 1, @SetNo, @SizeName);
        RETURN;
    END

    -- Semua bundle yang dikirim harus di set yang sama.
    IF EXISTS (
        SELECT 1 FROM bundles b INNER JOIN #chg c ON c.bundle_id = b.bundle_id
        WHERE b.deleted_at IS NULL
          AND (b.spread_size_id <> @SpreadSizeId OR b.set_no <> @SetNo)
    )
    BEGIN
        RAISERROR('Semua bundle yang diubah harus berada di set yang sama.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM #chg WHERE ISNULL(qty, 0) <= 0)
    BEGIN
        RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
        RETURN;
    END

    -- ---------- susunan set yang diinginkan ----------
    -- CREATE TABLE eksplisit, BUKAN SELECT ... INTO: bundle_id ikut NOT NULL dari
    -- tabel bundles kalau pakai INTO, sehingga baris bundle BARU (action ADD,
    -- bundle_id masih NULL) gagal di-insert ke sini.
    CREATE TABLE #want (
        bundle_id INT NULL,
        bundle_seq INT NULL,
        qty_old INT NULL,
        stock_status VARCHAR(10) NULL,
        from_old INT NULL,
        qty_new INT NULL,
        is_new BIT NOT NULL
    );

    INSERT INTO #want (bundle_id, bundle_seq, qty_old, stock_status, from_old, qty_new, is_new)
    SELECT b.bundle_id, b.bundle_seq, b.qty, b.stock_status, b.number_from,
           ISNULL(c.qty, b.qty), 0
    FROM bundles b
    LEFT JOIN #chg c ON c.bundle_id = b.bundle_id
    WHERE b.spread_size_id = @SpreadSizeId AND b.set_no = @SetNo AND b.deleted_at IS NULL;

    IF @Action = 'ADD'
    BEGIN
        IF ISNULL(@Qty, 0) <= 0
        BEGIN
            RAISERROR('Qty bundle baru harus lebih dari 0.', 16, 1);
            RETURN;
        END

        INSERT INTO #want (bundle_id, bundle_seq, qty_old, stock_status, from_old, qty_new, is_new)
        VALUES (NULL, (SELECT ISNULL(MAX(bundle_seq), 0) + 1 FROM #want), 0, 'STOCK', NULL, @Qty, 1);
    END
    ELSE IF @Action = 'REMOVE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM #want WHERE bundle_id = @BundleId)
        BEGIN
            RAISERROR('Bundle tidak ditemukan di set ini.', 16, 1);
            RETURN;
        END

        IF @BundleId <> (SELECT TOP 1 bundle_id FROM #want ORDER BY bundle_seq DESC)
        BEGIN
            RAISERROR('Hanya bundle terakhir di set yang bisa dihapus.', 16, 1);
            RETURN;
        END

        IF (SELECT stock_status FROM #want WHERE bundle_id = @BundleId) <> 'STOCK'
        BEGIN
            RAISERROR('Bundle sudah diambil Bundling, tidak bisa dihapus.', 16, 1);
            RETURN;
        END

        IF (SELECT COUNT(*) FROM #want) <= 1
        BEGIN
            RAISERROR('Set harus punya minimal satu bundle.', 16, 1);
            RETURN;
        END

        DELETE FROM #want WHERE bundle_id = @BundleId;
    END

    -- ---------- guard total ----------
    DECLARE @TotalNew INT = (SELECT SUM(qty_new) FROM #want);
    IF @TotalNew <> @SheetsPerSet
    BEGIN
        RAISERROR('Total qty set ini %d, harus %d (lembar per set). Sesuaikan qty bundle lain di set yang sama.',
                  16, 1, @TotalNew, @SheetsPerSet);
        RETURN;
    END

    -- ---------- rentang nomor baru di dalam set ----------
    DECLARE @SetStart INT = @SizeFrom + (@SetNo - 1) * @SheetsPerSet;

    SELECT w.bundle_id, w.is_new, w.qty_new, w.stock_status, w.qty_old, w.from_old,
           ROW_NUMBER() OVER (ORDER BY w.bundle_seq) AS seq_in_set,
           @SetStart + SUM(w.qty_new) OVER (ORDER BY w.bundle_seq ROWS UNBOUNDED PRECEDING) - w.qty_new AS from_new
    INTO #plan
    FROM #want w;

    -- Bundle yang qty atau rentang nomornya berubah harus masih STOCK.
    IF EXISTS (
        SELECT 1 FROM #plan
        WHERE is_new = 0 AND stock_status <> 'STOCK'
          AND (qty_new <> qty_old OR from_new <> from_old)
    )
    BEGIN
        RAISERROR('Ada bundle yang sudah diambil Bundling di set ini -- qty/rentang nomornya tidak bisa digeser.', 16, 1);
        RETURN;
    END

    -- ADD/REMOVE menggeser bundle_seq (dan kode bundle) SET SESUDAHNYA di size yang
    -- sama -- semuanya harus masih STOCK.
    IF @Action IN ('ADD', 'REMOVE') AND EXISTS (
        SELECT 1 FROM bundles
        WHERE spread_size_id = @SpreadSizeId AND set_no > @SetNo
          AND deleted_at IS NULL AND stock_status <> 'STOCK'
    )
    BEGIN
        RAISERROR('Set sesudahnya di size %s sudah ada bundle yang diambil Bundling -- jumlah bundle di set ini tidak bisa diubah.', 16, 1, @SizeName);
        RETURN;
    END

    BEGIN TRAN;
    BEGIN TRY
        DECLARE @LockResourceArticle VARCHAR(60) = 'article_workflow_restructure_' + CAST(@ArticleId AS VARCHAR(20));
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

        -- 1. qty & rentang nomor bundle yang sudah ada
        UPDATE b
        SET qty = p.qty_new,
            number_from = p.from_new,
            number_to = p.from_new + p.qty_new - 1,
            needs_reprint = 1,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        FROM bundles b
        INNER JOIN #plan p ON p.bundle_id = b.bundle_id
        WHERE p.is_new = 0
          AND (p.qty_new <> p.qty_old OR p.from_new <> p.from_old);

        -- 2. bundle baru (ADD) -- serial & bundle_no seperti bundle manual
        IF EXISTS (SELECT 1 FROM #plan WHERE is_new = 1)
        BEGIN
            DECLARE @LockResultSerial INT;
            EXEC @LockResultSerial = sp_getapplock
                @Resource = 'bundle_serial_seq', @LockMode = 'Exclusive',
                @LockOwner = 'Transaction', @LockTimeout = 10000;

            IF @LockResultSerial < 0
            BEGIN
                RAISERROR('Gagal mengunci penomoran serial bundle. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            -- Prompt 82: saring sequence_no = 0 (induk saja) -- serial anak '{serial}-{seq}'
            -- membuat RIGHT(serial, 6) tidak lagi murni angka.
            DECLARE @NextSerialNo INT = (SELECT ISNULL(MAX(CAST(RIGHT(serial, 6) AS INT)), 0) FROM bundles WHERE sequence_no = 0);
            DECLARE @Yy VARCHAR(2) = RIGHT(CAST(YEAR(SYSDATETIME()) AS VARCHAR(4)), 2);
            DECLARE @ProjectId INT = (SELECT project_id FROM articles WHERE article_id = @ArticleId);
            DECLARE @NextBundleNo INT = (
                SELECT ISNULL(MAX(b2.bundle_no), 0)
                FROM bundles b2 INNER JOIN articles a2 ON a2.article_id = b2.article_id
                WHERE a2.project_id = @ProjectId
            );
            DECLARE @NextSort INT = (
                SELECT ISNULL(MAX(sort_order), 0) FROM bundles
                WHERE article_size_id = @ArticleSizeId AND deleted_at IS NULL
            );

            -- Serial dihitung dulu ke temp supaya bisa dipakai dua kali: sebagai serial
            -- DAN sebagai cutting_code sementara. Placeholder-nya SENGAJA serial (unik
            -- global), bukan string tetap seperti 'TMP' -- UX_bundles_cutting_code unik
            -- per artikel, jadi dua baris placeholder yang sama akan bentrok.
            -- Nilai akhirnya ditimpa penomoran ulang di langkah 4.
            SELECT
                'B' + @Yy + '-' + RIGHT('000000' + CAST(@NextSerialNo + ROW_NUMBER() OVER (ORDER BY p.seq_in_set) AS VARCHAR(10)), 6) AS serial,
                @NextBundleNo + ROW_NUMBER() OVER (ORDER BY p.seq_in_set) AS bundle_no,
                @NextSort + ROW_NUMBER() OVER (ORDER BY p.seq_in_set) AS sort_order,
                p.qty_new, p.from_new
            INTO #newb
            FROM #plan p
            WHERE p.is_new = 1;

            INSERT INTO bundles (
                article_id, article_size_id, serial, bundle_no, qty, sort_order,
                created_at, created_by, spread_id, spread_size_id, cutting_code,
                set_no, bundle_seq, number_from, number_to, source, stock_status, needs_reprint
            )
            SELECT
                @ArticleId, @ArticleSizeId, n.serial, n.bundle_no, n.qty_new, n.sort_order,
                SYSDATETIME(), @UserId, @SpreadId, @SpreadSizeId, n.serial,
                @SetNo, 0, n.from_new, n.from_new + n.qty_new - 1, 'CUTTING', 'STOCK', 1
            FROM #newb n;

            -- Prompt 82: lihat catatan yang sama di cabang CREATE di atas.
            UPDATE bundles SET root_bundle_id = bundle_id
            WHERE spread_id = @SpreadId AND root_bundle_id = 0;
        END

        -- 3. bundle yang dihapus (REMOVE)
        IF @Action = 'REMOVE'
        BEGIN
            UPDATE bundles
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId,
                delete_reason = 'Bundle hamparan dihapus dari sisi cutting'
            WHERE bundle_id = @BundleId;
        END

        -- 4. penomoran ulang bundle_seq + kode bundle untuk SELURUH size di hamparan ini
        --    (bundle_seq urut per spread per size, lintas set).
        ;WITH renum AS (
            SELECT b.bundle_id, b.bundle_seq AS seq_old, b.cutting_code AS code_old,
                   ROW_NUMBER() OVER (ORDER BY b.set_no, b.number_from) AS seq_new
            FROM bundles b
            WHERE b.spread_size_id = @SpreadSizeId AND b.deleted_at IS NULL
        )
        UPDATE b
        SET bundle_seq = r.seq_new,
            cutting_code = @SpreadCode + '-' + @SizeName + '-' + RIGHT('00' + CAST(r.seq_new AS VARCHAR(10)), 2),
            needs_reprint = 1,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        FROM bundles b
        INNER JOIN renum r ON r.bundle_id = b.bundle_id
        WHERE r.seq_old <> r.seq_new
           OR r.code_old <> @SpreadCode + '-' + @SizeName + '-' + RIGHT('00' + CAST(r.seq_new AS VARCHAR(10)), 2);

        COMMIT TRAN;

        SELECT @SpreadId AS SpreadId, @SpreadSizeId AS SpreadSizeId, @SetNo AS SetNo;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

/* ============================================================
   SIS_CuttingBundle_Print -- enqueue stiker bundle cutting.

   Job type BARU: CUTTING_BUNDLE_LABEL (printer & ukuran label mengikuti
   BUNDLE_LABEL lewat print_job_routes -> print_devices). Builder TSPL-nya
   varian baru di TerakarsaApp.Printing -- BUNDLE_LABEL yang lama TIDAK diubah.

   @BundleIdsJson NULL/kosong = semua bundle hidup di hamparan ini.
   Mereset needs_reprint = 0 untuk bundle yang dicetak.
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_CuttingBundle_Print
    @SpreadId       INT,
    @BundleIdsJson  NVARCHAR(MAX) = NULL,
    @PublicBaseUrl  VARCHAR(255) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM spreads WHERE spread_id = @SpreadId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Hamparan tidak ditemukan.', 16, 1);
        RETURN;
    END

    SELECT CAST([value] AS INT) AS bundle_id
    INTO #ids
    FROM OPENJSON(ISNULL(@BundleIdsJson, '[]'));

    DECLARE @HasFilter BIT = CASE WHEN EXISTS (SELECT 1 FROM #ids) THEN 1 ELSE 0 END;

    BEGIN TRAN;
    BEGIN TRY
        INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
        SELECT 'CUTTING_BUNDLE_LABEL', b.bundle_id,
            (SELECT
                b.cutting_code                                   AS cutting_code,
                b.serial                                         AS serial,
                ISNULL(@PublicBaseUrl, '') + '/b/' + b.serial     AS qr_content,
                -- Nomor bundle pendek per project + huruf project (Prompt 27), dicetak
                -- di kiri Size seperti "No. J-27" di stiker penyerahan bundle manual.
                b.bundle_no                                      AS bundle_no,
                p.bundle_letter                                  AS bundle_letter,
                p.no_po                                          AS no_po,
                p.project_name                                   AS project_name,
                a.article_name                                   AS article_name,
                spd.size_name                                    AS size_name,
                b.qty                                            AS qty,
                b.set_no                                         AS set_no,
                spd.size_name + '-' + CAST(b.number_from AS VARCHAR(10)) AS number_from_text,
                spd.size_name + '-' + CAST(b.number_to AS VARCHAR(10))   AS number_to_text,
                s.spread_code                                    AS spread_code,
                s.spread_date                                    AS spread_date
             FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
            'PENDING', SYSDATETIME(), @UserId
        FROM bundles b
        INNER JOIN spreads s ON s.spread_id = b.spread_id
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        WHERE b.spread_id = @SpreadId
          AND b.deleted_at IS NULL
          AND (@HasFilter = 0 OR b.bundle_id IN (SELECT bundle_id FROM #ids))
        ORDER BY spd.sort_order, b.bundle_seq;

        DECLARE @Jobs INT = @@ROWCOUNT;

        UPDATE b
        SET needs_reprint = 0
        FROM bundles b
        WHERE b.spread_id = @SpreadId AND b.deleted_at IS NULL
          AND b.needs_reprint = 1
          AND (@HasFilter = 0 OR b.bundle_id IN (SELECT bundle_id FROM #ids));

        COMMIT TRAN;

        SELECT @Jobs AS JobCount;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO

/* ============================================================
   SIS_Cutting_StockSummary -- landing Stok Bundle (revisi 2026-10-26).

   Dulu: satu baris per (artikel, size) yang SUDAH punya bundle cutting.
   Sekarang: satu baris per (PO, artikel, size) untuk SELURUH size artikel,
   termasuk yang belum dipotong sama sekali -- supaya kolom "Sisa belum cutting"
   (qty PO - qty sudah cutting) bisa dihitung dan halaman bisa difilter per PO.

   Definisi "sudah cutting" SAMA PERSIS dengan kolom Cutting di
   SIS_Report_ArticleSizeProgress (sql/sp_Report_Bundle.sql), yaitu DUA sumber
   yang dijumlahkan:
     a. SELURUH bundle yang lahir dari hamparan, stock_status TIDAK difilter --
        bundle yang sudah diklaim Line tetap terhitung sudah dipotong (CutBundlePcs);
     b. SUM(qty_ok) log step Cutting yang diinput manual dari station
        (tab WIP kartu artikel x step non-bundle) -- CutLogPcs.
   Step Cutting = step non-bundle TERAKHIR artikel, definisi @LastNonBundleStepId
   yang sama dengan SIS_CuttingBundle_Take. Tidak ada dobel hitung: Take menulis
   log step BUNDLING, bukan log step Cutting.

   Baris yang ditampilkan: artikel di project aktif (manual_status IS NULL),
   DITAMBAH project yang sudah ON_HOLD/COMPLETED/CANCELLED tapi masih punya bundle
   cutting -- supaya stok fisik tidak pernah hilang dari layar.

   Result set 1 : angka ringkas global (kartu "Hamparan belum dicetak" dll)
   Result set 2 : per PO per artikel per size
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_StockSummary
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    SELECT
        (SELECT COUNT(*) FROM bundles WHERE source = 'CUTTING' AND stock_status = 'STOCK' AND deleted_at IS NULL) AS StockBundles,
        (SELECT ISNULL(SUM(qty), 0) FROM bundles WHERE source = 'CUTTING' AND stock_status = 'STOCK' AND deleted_at IS NULL) AS StockPcs,
        (SELECT COUNT(*) FROM bundles WHERE source = 'CUTTING' AND stock_status = 'TAKEN' AND deleted_at IS NULL
                                        AND CAST(taken_at AS DATE) = @Today) AS TakenToday,
        (SELECT COUNT(*) FROM spreads WHERE [status] = 'DRAFT' AND deleted_at IS NULL) AS DraftSpreads;

    SELECT
        p.project_id        AS ProjectId,
        p.no_po             AS NoPo,
        p.project_name      AS ProjectName,
        a.article_id        AS ArticleId,
        a.article_name      AS ArticleName,
        a.bundle_target_qty AS BundleTargetQty,
        (SELECT COUNT(*) FROM spreads s WHERE s.article_id = a.article_id AND s.deleted_at IS NULL) AS SpreadCount,
        asz.article_size_id AS ArticleSizeId,
        spd.size_name       AS SizeName,
        spd.sort_order      AS SizeSortOrder,
        asz.qty             AS PoQty,
        cut.CutBundlePcs + lg.CutLogPcs AS CutPcs,
        cut.CutBundlePcs    AS CutBundlePcs,
        lg.CutLogPcs        AS CutLogPcs,
        cut.TotalBundles    AS TotalBundles,
        cut.StockBundles    AS StockBundles,
        cut.TakenBundles    AS TakenBundles,
        cut.StockPcs        AS StockPcs
    FROM article_sizes asz
    INNER JOIN articles a ON a.article_id = asz.article_id AND a.deleted_at IS NULL
    INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    CROSS APPLY (
        SELECT
            ISNULL(SUM(b.qty), 0)                                      AS CutBundlePcs,
            COUNT(b.bundle_id)                                         AS TotalBundles,
            ISNULL(SUM(CASE WHEN b.stock_status = 'STOCK' THEN 1 ELSE 0 END), 0)      AS StockBundles,
            ISNULL(SUM(CASE WHEN b.stock_status = 'TAKEN' THEN 1 ELSE 0 END), 0)      AS TakenBundles,
            ISNULL(SUM(CASE WHEN b.stock_status = 'STOCK' THEN b.qty ELSE 0 END), 0)  AS StockPcs
        FROM bundles b
        WHERE b.article_size_id = asz.article_size_id
          AND b.source = 'CUTTING'
          AND b.deleted_at IS NULL
    ) cut
    -- Step Cutting artikel ini (step non-bundle TERAKHIR yang masih aktif). Artikel
    -- yang semua stepnya ber-bundle tidak punya step ini -> CutLogPcs = 0.
    OUTER APPLY (
        SELECT TOP 1 aw.article_workflow_id
        FROM article_workflows aw
        WHERE aw.article_id = a.article_id
          AND aw.deleted_at IS NULL
          AND aw.inactive_at IS NULL
          AND aw.requires_bundle = 0
        ORDER BY aw.sort_order DESC
    ) cs
    CROSS APPLY (
        SELECT ISNULL(SUM(l.qty_ok), 0) AS CutLogPcs
        FROM article_workflow_logs l
        WHERE cs.article_workflow_id IS NOT NULL
          AND l.article_workflow_id = cs.article_workflow_id
          AND l.article_size_id = asz.article_size_id
          AND l.deleted_at IS NULL
    ) lg
    WHERE asz.deleted_at IS NULL
      AND (p.manual_status IS NULL OR cut.TotalBundles > 0 OR lg.CutLogPcs > 0)
    -- Nomor PO terbaru di ATAS, pola sama dgn SIS_Cutting_Articles.
    ORDER BY TRY_CAST(LEFT(p.no_po, CHARINDEX('.', p.no_po + '.') - 1) AS INT) DESC,
             p.no_po DESC, a.article_name ASC, spd.sort_order ASC;
END;
GO

/* ============================================================
   SIS_Cutting_TakenToday -- panel "Diambil hari ini" (Prompt 80 §4).
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_TakenToday
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    SELECT
        b.bundle_id     AS BundleId,
        b.cutting_code  AS CuttingCode,
        b.serial        AS Serial,
        b.qty           AS Qty,
        p.no_po         AS NoPo,
        a.article_name  AS ArticleName,
        spd.size_name   AS SizeName,
        res.resource_name AS TakenByResourceName,
        b.taken_at      AS TakenAt
    FROM bundles b
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources res ON res.resource_id = b.taken_by_resource_id
    WHERE b.source = 'CUTTING' AND b.deleted_at IS NULL
      AND b.stock_status = 'TAKEN'
      AND CAST(b.taken_at AS DATE) = @Today
    ORDER BY b.taken_at DESC;
END;
GO

/* ============================================================
   SIS_Spread_List -- daftar hamparan (filter artikel, status, tanggal).
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Spread_List
    @ArticleId INT = NULL,
    @Status    VARCHAR(10) = NULL,
    @DateFrom  DATE = NULL,
    @DateTo    DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.spread_id      AS SpreadId,
        s.spread_code    AS SpreadCode,
        s.spread_date    AS SpreadDate,
        s.set_count      AS SetCount,
        s.sheets_per_set AS SheetsPerSet,
        s.[status]       AS Status,
        s.printed_at     AS PrintedAt,
        s.note           AS Note,
        a.article_id     AS ArticleId,
        a.article_name   AS ArticleName,
        p.no_po          AS NoPo,
        p.project_name   AS ProjectName,
        ISNULL(g.total_bundles, 0) AS TotalBundles,
        ISNULL(g.total_pcs, 0)     AS TotalPcs,
        ISNULL(g.stock_bundles, 0) AS StockBundles,
        ISNULL(g.taken_bundles, 0) AS TakenBundles,
        ISNULL(g.needs_reprint, 0) AS NeedsReprintBundles,
        u.FullName       AS CreatedByName,
        s.created_at     AS CreatedAt
    FROM spreads s
    INNER JOIN articles a ON a.article_id = s.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN Users u ON u.Id = s.created_by
    OUTER APPLY (
        SELECT COUNT(*) AS total_bundles, SUM(b.qty) AS total_pcs,
               SUM(CASE WHEN b.stock_status = 'STOCK' THEN 1 ELSE 0 END) AS stock_bundles,
               SUM(CASE WHEN b.stock_status = 'TAKEN' THEN 1 ELSE 0 END) AS taken_bundles,
               SUM(CASE WHEN b.needs_reprint = 1 THEN 1 ELSE 0 END) AS needs_reprint
        FROM bundles b WHERE b.spread_id = s.spread_id AND b.deleted_at IS NULL
    ) g
    WHERE s.deleted_at IS NULL
      AND (@ArticleId IS NULL OR s.article_id = @ArticleId)
      AND (@Status IS NULL OR s.[status] = @Status)
      AND (@DateFrom IS NULL OR s.spread_date >= @DateFrom)
      AND (@DateTo IS NULL OR s.spread_date <= @DateTo)
    ORDER BY s.spread_date DESC, s.spread_id DESC;
END;
GO

/* ============================================================
   SIS_Spread_Detail -- header + sizes + bundles (3 result set).
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Spread_Detail
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.spread_id      AS SpreadId,
        s.spread_code    AS SpreadCode,
        s.spread_date    AS SpreadDate,
        s.set_count      AS SetCount,
        s.sheets_per_set AS SheetsPerSet,
        s.[status]       AS Status,
        s.printed_at     AS PrintedAt,
        s.note           AS Note,
        a.article_id     AS ArticleId,
        a.article_name   AS ArticleName,
        a.bundle_target_qty AS BundleTargetQty,
        p.no_po          AS NoPo,
        p.project_name   AS ProjectName,
        u.FullName       AS CreatedByName,
        s.created_at     AS CreatedAt,
        ISNULL(g.total_bundles, 0) AS TotalBundles,
        ISNULL(g.total_pcs, 0)     AS TotalPcs,
        ISNULL(g.stock_bundles, 0) AS StockBundles,
        ISNULL(g.stock_pcs, 0)     AS StockPcs,
        ISNULL(g.taken_bundles, 0) AS TakenBundles
    FROM spreads s
    INNER JOIN articles a ON a.article_id = s.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN Users u ON u.Id = s.created_by
    OUTER APPLY (
        SELECT COUNT(*) AS total_bundles, SUM(b.qty) AS total_pcs,
               SUM(CASE WHEN b.stock_status = 'STOCK' THEN 1 ELSE 0 END) AS stock_bundles,
               SUM(CASE WHEN b.stock_status = 'STOCK' THEN b.qty ELSE 0 END) AS stock_pcs,
               SUM(CASE WHEN b.stock_status = 'TAKEN' THEN 1 ELSE 0 END) AS taken_bundles
        FROM bundles b WHERE b.spread_id = s.spread_id AND b.deleted_at IS NULL
    ) g
    WHERE s.spread_id = @Id AND s.deleted_at IS NULL;

    SELECT
        ss.spread_size_id   AS SpreadSizeId,
        ss.article_size_id  AS ArticleSizeId,
        spd.size_name       AS SizeName,
        spd.sort_order      AS SizeSortOrder,
        ss.set_count        AS SetCount,
        ss.number_from      AS NumberFrom,
        ss.number_to        AS NumberTo
    FROM spread_sizes ss
    INNER JOIN article_sizes asz ON asz.article_size_id = ss.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    WHERE ss.spread_id = @Id
    ORDER BY spd.sort_order;

    SELECT
        b.bundle_id        AS BundleId,
        b.cutting_code     AS CuttingCode,
        b.serial           AS Serial,
        b.spread_size_id   AS SpreadSizeId,
        spd.size_name      AS SizeName,
        spd.sort_order     AS SizeSortOrder,
        b.set_no           AS SetNo,
        b.bundle_seq       AS BundleSeq,
        b.qty              AS Qty,
        b.number_from      AS NumberFrom,
        b.number_to        AS NumberTo,
        b.stock_status     AS StockStatus,
        b.needs_reprint    AS NeedsReprint,
        b.taken_at         AS TakenAt,
        res.resource_name  AS TakenByResourceName
    FROM bundles b
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources res ON res.resource_id = b.taken_by_resource_id
    WHERE b.spread_id = @Id AND b.deleted_at IS NULL
    ORDER BY spd.sort_order, b.bundle_seq;
END;
GO

/* ============================================================
   SIS_Cutting_ArticleSizes -- baris size artikel untuk form Buat Hamparan,
   sekalian nomor pcs berikutnya per size (rentang numbering dihitung live).
   ============================================================ */
CREATE OR ALTER PROCEDURE SIS_Cutting_ArticleSizes
    @ArticleId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        asz.article_size_id AS ArticleSizeId,
        spd.size_name       AS SizeName,
        spd.sort_order      AS SizeSortOrder,
        asz.qty             AS OrderQty,
        nx.NextFrom         AS NextFrom
    FROM article_sizes asz
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    CROSS APPLY (
        SELECT ISNULL(MAX(ss.number_to), 0) + 1 AS NextFrom
        FROM spread_sizes ss
        INNER JOIN spreads s ON s.spread_id = ss.spread_id AND s.deleted_at IS NULL
        WHERE ss.article_size_id = asz.article_size_id
    ) nx
    WHERE asz.article_id = @ArticleId AND asz.deleted_at IS NULL
    ORDER BY spd.sort_order;
END;
GO
