/* =============================================================
   Module Stok Benang (Prompt 74) -- stock opname schema `inv`.

   PRINSIP: opname TIDAK PERNAH menulis inv.thread_stocks. Saat sesi ditutup,
   setiap selisih dijadikan movement lewat inv.SIS_ThreadMovement_Manage
   (dipanggil dengan INSERT ... EXEC supaya result set-nya tidak bocor ke
   client), dan movement itu menunjuk baris opname-nya + membawa reason_code.

   Rekonsiliasi MOVE memakai pemasangan "greedy" set-based: rak minus dan rak
   plus satu SKU masing-masing diberi rentang kumulatif, lalu dipasangkan pada
   bagian yang tumpang tindih. Hasilnya sama dengan menjodohkan satu-satu dari
   atas, tanpa cursor.

   ANSI_NULLS / QUOTED_IDENTIFIER wajib ON (filtered index di tabel inv.*).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================
-- MUTASI SESI OPNAME
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadOpname_Manage
    @Action          VARCHAR(20),       -- OPEN | ADD_LINE | COUNT | LOCATION_DONE
                                        -- | PREVIEW_CLOSE | CLOSE | CANCEL
    @SessionId       INT = NULL,
    @LocationId      INT = NULL,
    @ItemId          INT = NULL,
    @LineId          INT = NULL,
    @CountedQty      INT = NULL,
    @LocationIdsJson NVARCHAR(MAX) = NULL,   -- OPEN: [1,2,3]; kosong/NULL = semua rak aktif
    @SplitFoundJson  NVARCHAR(MAX) = NULL,   -- COUNT: [{"split_cone_id":1,"is_found":true}]
    @ResolutionsJson NVARCHAR(MAX) = NULL,   -- CLOSE: lihat komentar di action CLOSE
    @Note            VARCHAR(500) = NULL,
    @UserId          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Action NOT IN ('OPEN','ADD_LINE','COUNT','LOCATION_DONE','PREVIEW_CLOSE','CLOSE','CANCEL')
    BEGIN
        RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
        RETURN;
    END

    SET @Note = NULLIF(LTRIM(RTRIM(ISNULL(@Note,''))), '');

    -- ============================= OPEN =============================
    IF @Action = 'OPEN'
    BEGIN
        IF EXISTS (SELECT 1 FROM inv.thread_opname_sessions
                    WHERE [status] = 'OPEN' AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Masih ada sesi opname yang berjalan -- tutup atau batalkan dulu.', 16, 1);
            RETURN;
        END

        DECLARE @Racks TABLE (thread_location_id INT PRIMARY KEY);

        IF @LocationIdsJson IS NULL OR LTRIM(RTRIM(@LocationIdsJson)) IN ('', '[]')
            INSERT INTO @Racks (thread_location_id)
            SELECT thread_location_id FROM inv.thread_locations
            WHERE deleted_at IS NULL AND is_active = 1;
        ELSE
            INSERT INTO @Racks (thread_location_id)
            SELECT DISTINCT l.thread_location_id
            FROM OPENJSON(@LocationIdsJson) j
            INNER JOIN inv.thread_locations l ON l.thread_location_id = CAST(j.value AS INT)
            WHERE l.deleted_at IS NULL;

        IF NOT EXISTS (SELECT 1 FROM @Racks)
        BEGIN
            RAISERROR('Tidak ada rak yang bisa diopname.', 16, 1);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            -- Nomor sesi per tahun: SO26-0001.
            DECLARE @Lock INT;
            EXEC @Lock = sp_getapplock @Resource = 'thread_opname_seq',
                 @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;

            IF @Lock < 0
            BEGIN
                RAISERROR('Sistem sedang membuat nomor sesi lain, coba lagi sebentar.', 16, 1);
            END

            DECLARE @Yy VARCHAR(2) = RIGHT(CONVERT(VARCHAR(4), YEAR(SYSDATETIME())), 2);
            DECLARE @Next INT;
            SELECT @Next = ISNULL(MAX(CAST(RIGHT(session_no, 4) AS INT)), 0) + 1
            FROM inv.thread_opname_sessions
            WHERE session_no LIKE 'SO' + @Yy + '-[0-9][0-9][0-9][0-9]';

            DECLARE @SessionNo VARCHAR(20) = 'SO' + @Yy + '-' + RIGHT('0000' + CAST(@Next AS VARCHAR(10)), 4);

            INSERT INTO inv.thread_opname_sessions (session_no, [status], note, created_by)
            VALUES (@SessionNo, 'OPEN', @Note, @UserId);

            DECLARE @NewSessionId INT = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO inv.thread_opname_locations
                (thread_opname_session_id, thread_location_id, [status], created_by)
            SELECT @NewSessionId, r.thread_location_id, 'PENDING', @UserId
            FROM @Racks r;

            -- Satu baris per SKU yang punya isi di rak itu (whole > 0 ATAU split IN_STOCK).
            -- system_qty = snapshot saldo saat sesi dibuka.
            INSERT INTO inv.thread_opname_lines
                (thread_opname_session_id, thread_location_id, thread_item_id,
                 system_qty, split_expected, created_by)
            SELECT @NewSessionId, x.thread_location_id, x.thread_item_id,
                   x.qty_whole, x.split_count, @UserId
            FROM (
                SELECT r.thread_location_id,
                       i.thread_item_id,
                       ISNULL(st.qty_whole, 0) AS qty_whole,
                       (SELECT COUNT(*) FROM inv.thread_split_cones c
                         WHERE c.thread_item_id = i.thread_item_id
                           AND c.thread_location_id = r.thread_location_id
                           AND c.deleted_at IS NULL
                           AND c.[status] = 'IN_STOCK') AS split_count
                FROM @Racks r
                CROSS JOIN inv.thread_items i
                LEFT JOIN inv.thread_stocks st
                       ON st.thread_item_id = i.thread_item_id
                      AND st.thread_location_id = r.thread_location_id
                      AND st.deleted_at IS NULL
                WHERE i.deleted_at IS NULL
            ) x
            WHERE x.qty_whole > 0 OR x.split_count > 0;

            -- Checklist kones split per baris.
            INSERT INTO inv.thread_opname_splits
                (thread_opname_line_id, thread_split_cone_id, created_by)
            SELECT l.thread_opname_line_id, c.thread_split_cone_id, @UserId
            FROM inv.thread_opname_lines l
            INNER JOIN inv.thread_split_cones c
                    ON c.thread_item_id = l.thread_item_id
                   AND c.thread_location_id = l.thread_location_id
                   AND c.deleted_at IS NULL
                   AND c.[status] = 'IN_STOCK'
            WHERE l.thread_opname_session_id = @NewSessionId;

            COMMIT TRANSACTION;

            SELECT @NewSessionId AS Value;
            RETURN;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    -- ---------- validasi sesi untuk action selain OPEN ----------
    -- COUNT hanya mengirim @LineId; sesinya diturunkan dari baris itu.
    IF @SessionId IS NULL AND @LineId IS NOT NULL
        SELECT @SessionId = thread_opname_session_id FROM inv.thread_opname_lines
        WHERE thread_opname_line_id = @LineId AND deleted_at IS NULL;

    DECLARE @SessionStatus VARCHAR(10) =
        (SELECT [status] FROM inv.thread_opname_sessions
          WHERE thread_opname_session_id = @SessionId AND deleted_at IS NULL);

    IF @SessionStatus IS NULL
    BEGIN
        RAISERROR('Sesi opname tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Action <> 'PREVIEW_CLOSE' AND @SessionStatus <> 'OPEN'
    BEGIN
        RAISERROR('Sesi opname sudah ditutup.', 16, 1);
        RETURN;
    END

    -- ============================= ADD_LINE =============================
    -- Untuk SKU yang ADA fisik tapi sistem 0 di rak itu (hasil scan saat opname).
    -- Ini juga jalur masuk STOK AWAL gudang: buka opname, ADD_LINE semua SKU,
    -- tutup dengan alasan STOK_AWAL.
    IF @Action = 'ADD_LINE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_opname_locations
                        WHERE thread_opname_session_id = @SessionId
                          AND thread_location_id = @LocationId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Rak itu tidak termasuk dalam sesi opname ini.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM inv.thread_items
                        WHERE thread_item_id = @ItemId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU benang tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @AdaLine INT = (SELECT thread_opname_line_id FROM inv.thread_opname_lines
                                 WHERE thread_opname_session_id = @SessionId
                                   AND thread_location_id = @LocationId
                                   AND thread_item_id = @ItemId
                                   AND deleted_at IS NULL);

        IF @AdaLine IS NOT NULL
        BEGIN
            -- Sudah ada: kembalikan id-nya saja supaya UI tinggal menyorot barisnya.
            SELECT @AdaLine AS Value;
            RETURN;
        END

        DECLARE @SysQty INT = ISNULL((SELECT qty_whole FROM inv.thread_stocks
                                       WHERE thread_item_id = @ItemId
                                         AND thread_location_id = @LocationId
                                         AND deleted_at IS NULL), 0);

        DECLARE @SplitAda INT = (SELECT COUNT(*) FROM inv.thread_split_cones
                                  WHERE thread_item_id = @ItemId
                                    AND thread_location_id = @LocationId
                                    AND deleted_at IS NULL AND [status] = 'IN_STOCK');

        INSERT INTO inv.thread_opname_lines
            (thread_opname_session_id, thread_location_id, thread_item_id,
             system_qty, split_expected, created_by)
        VALUES (@SessionId, @LocationId, @ItemId, @SysQty, @SplitAda, @UserId);

        DECLARE @NewLineId INT = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO inv.thread_opname_splits (thread_opname_line_id, thread_split_cone_id, created_by)
        SELECT @NewLineId, c.thread_split_cone_id, @UserId
        FROM inv.thread_split_cones c
        WHERE c.thread_item_id = @ItemId
          AND c.thread_location_id = @LocationId
          AND c.deleted_at IS NULL AND c.[status] = 'IN_STOCK';

        SELECT @NewLineId AS Value;
        RETURN;
    END

    -- ============================= COUNT =============================
    IF @Action = 'COUNT'
    BEGIN
        IF @CountedQty IS NULL OR @CountedQty < 0
        BEGIN
            RAISERROR('Jumlah fisik harus 0 atau lebih.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM inv.thread_opname_lines
                        WHERE thread_opname_line_id = @LineId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Baris opname tidak ditemukan.', 16, 1);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE inv.thread_opname_lines
            SET counted_qty = @CountedQty,
                counted_at = SYSDATETIME(),
                counted_by = @UserId,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE thread_opname_line_id = @LineId;

            IF @SplitFoundJson IS NOT NULL AND LTRIM(RTRIM(@SplitFoundJson)) NOT IN ('', '[]')
            BEGIN
                DECLARE @Found TABLE (split_cone_id INT PRIMARY KEY, is_found BIT);

                INSERT INTO @Found (split_cone_id, is_found)
                SELECT CAST(j.split_cone_id AS INT), CAST(j.is_found AS BIT)
                FROM OPENJSON(@SplitFoundJson)
                     WITH (split_cone_id INT '$.split_cone_id', is_found BIT '$.is_found') j;

                -- Kones yang belum punya baris checklist di baris ini ikut dibuat:
                -- kones yang menurut sistem ada di rak LAIN tapi ternyata ditemukan di sini
                -- (jadi usulan MOVE_SPLIT saat preview).
                INSERT INTO inv.thread_opname_splits
                    (thread_opname_line_id, thread_split_cone_id, created_by)
                SELECT @LineId, f.split_cone_id, @UserId
                FROM @Found f
                INNER JOIN inv.thread_split_cones c
                        ON c.thread_split_cone_id = f.split_cone_id AND c.deleted_at IS NULL
                WHERE NOT EXISTS (
                    SELECT 1 FROM inv.thread_opname_splits s
                    WHERE s.thread_opname_line_id = @LineId
                      AND s.thread_split_cone_id = f.split_cone_id
                      AND s.deleted_at IS NULL);

                UPDATE s
                SET s.is_found = f.is_found,
                    s.updated_at = SYSDATETIME(), s.updated_by = @UserId
                FROM inv.thread_opname_splits s
                INNER JOIN @Found f ON f.split_cone_id = s.thread_split_cone_id
                WHERE s.thread_opname_line_id = @LineId AND s.deleted_at IS NULL;
            END

            -- split_found = jumlah kones yang dicentang ada.
            UPDATE l
            SET split_found = (SELECT COUNT(*) FROM inv.thread_opname_splits s
                                WHERE s.thread_opname_line_id = l.thread_opname_line_id
                                  AND s.deleted_at IS NULL AND s.is_found = 1)
            FROM inv.thread_opname_lines l
            WHERE l.thread_opname_line_id = @LineId;

            -- Rak jadi DRAFT begitu ada satu baris dihitung (kecuali sudah DONE).
            UPDATE inv.thread_opname_locations
            SET [status] = 'DRAFT', updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_opname_session_id = @SessionId
              AND thread_location_id = (SELECT thread_location_id FROM inv.thread_opname_lines
                                         WHERE thread_opname_line_id = @LineId)
              AND [status] = 'PENDING'
              AND deleted_at IS NULL;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        SELECT @LineId AS Value;
        RETURN;
    END

    -- ============================= LOCATION_DONE =============================
    IF @Action = 'LOCATION_DONE'
    BEGIN
        DECLARE @Belum INT = (SELECT COUNT(*) FROM inv.thread_opname_lines
                               WHERE thread_opname_session_id = @SessionId
                                 AND thread_location_id = @LocationId
                                 AND counted_qty IS NULL
                                 AND deleted_at IS NULL);

        IF @Belum > 0
        BEGIN
            RAISERROR('Masih ada %d SKU belum dihitung di rak ini.', 16, 1, @Belum);
            RETURN;
        END

        UPDATE inv.thread_opname_locations
        SET [status] = 'DONE', updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE thread_opname_session_id = @SessionId
          AND thread_location_id = @LocationId
          AND deleted_at IS NULL;

        SELECT @LocationId AS Value;
        RETURN;
    END

    -- ============================= CANCEL =============================
    IF @Action = 'CANCEL'
    BEGIN
        IF EXISTS (SELECT 1 FROM inv.thread_movements
                    WHERE opname_line_id IN (SELECT thread_opname_line_id FROM inv.thread_opname_lines
                                              WHERE thread_opname_session_id = @SessionId)
                      AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Sesi ini sudah menghasilkan mutasi -- tidak bisa dibatalkan.', 16, 1);
            RETURN;
        END

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE s SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            FROM inv.thread_opname_splits s
            INNER JOIN inv.thread_opname_lines l ON l.thread_opname_line_id = s.thread_opname_line_id
            WHERE l.thread_opname_session_id = @SessionId AND s.deleted_at IS NULL;

            UPDATE inv.thread_opname_lines SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE thread_opname_session_id = @SessionId AND deleted_at IS NULL;

            UPDATE inv.thread_opname_locations SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE thread_opname_session_id = @SessionId AND deleted_at IS NULL;

            UPDATE inv.thread_opname_sessions SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE thread_opname_session_id = @SessionId AND deleted_at IS NULL;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        SELECT @SessionId AS Value;
        RETURN;
    END

    -- ============================= PREVIEW_CLOSE =============================
    -- HANYA SELECT. Satu result set berisi usulan; proposal_id hanya nomor urut
    -- sementara supaya client bisa menandai usulan yang diubah/ditolak.
    IF @Action = 'PREVIEW_CLOSE'
    BEGIN
        ;WITH d AS (
            SELECT l.thread_opname_line_id, l.thread_item_id, l.thread_location_id,
                   l.system_qty, l.counted_qty,
                   l.counted_qty - l.system_qty AS diff
            FROM inv.thread_opname_lines l
            WHERE l.thread_opname_session_id = @SessionId
              AND l.deleted_at IS NULL
              AND l.counted_qty IS NOT NULL
        ),
        minus AS (
            SELECT d.*, -d.diff AS amt,
                   SUM(-d.diff) OVER (PARTITION BY d.thread_item_id
                                      ORDER BY d.thread_location_id
                                      ROWS UNBOUNDED PRECEDING) AS cum_end
            FROM d WHERE d.diff < 0
        ),
        plus AS (
            SELECT d.*, d.diff AS amt,
                   SUM(d.diff) OVER (PARTITION BY d.thread_item_id
                                     ORDER BY d.thread_location_id
                                     ROWS UNBOUNDED PRECEDING) AS cum_end
            FROM d WHERE d.diff > 0
        ),
        -- Pemasangan greedy: rentang kumulatif minus vs plus yang tumpang tindih.
        pairs AS (
            SELECT m.thread_opname_line_id AS from_line_id,
                   m.thread_item_id,
                   m.thread_location_id AS from_location_id,
                   p.thread_location_id AS to_location_id,
                   p.thread_opname_line_id AS to_line_id,
                   LEAST(m.cum_end, p.cum_end)
                     - GREATEST(m.cum_end - m.amt, p.cum_end - p.amt) AS qty
            FROM minus m
            INNER JOIN plus p ON p.thread_item_id = m.thread_item_id
            WHERE LEAST(m.cum_end, p.cum_end)
                    - GREATEST(m.cum_end - m.amt, p.cum_end - p.amt) > 0
        ),
        sisa AS (
            SELECT d.thread_opname_line_id, d.thread_item_id, d.thread_location_id,
                   d.system_qty, d.counted_qty, d.diff,
                   d.diff
                     + ISNULL((SELECT SUM(qty) FROM pairs p WHERE p.from_line_id = d.thread_opname_line_id), 0)
                     - ISNULL((SELECT SUM(qty) FROM pairs p WHERE p.to_line_id = d.thread_opname_line_id), 0) AS sisa_diff
            FROM d
        )
        SELECT ROW_NUMBER() OVER (ORDER BY u.urut, u.thread_item_id, u.from_location_id, u.to_location_id) AS ProposalId,
               u.Kind,
               u.ActionUsulan        AS ActionUsulan,
               u.thread_opname_line_id AS LineId,
               u.thread_item_id      AS ThreadItemId,
               i.sku_code            AS SkuCode,
               i.color_name          AS ColorName,
               i.color_code          AS ColorCode,
               t.name                AS TypeName,
               b.name                AS BrandName,
               u.from_location_id    AS FromLocationId,
               lf.code               AS FromCode,
               u.to_location_id      AS ToLocationId,
               lt.code               AS ToCode,
               u.qty                 AS Qty,
               u.system_qty          AS SystemQty,
               u.counted_qty         AS CountedQty,
               u.split_cone_id       AS ThreadSplitConeId,
               c.cone_code           AS ConeCode,
               c.weight_gram         AS WeightGram,
               u.reason_required     AS ReasonRequired
        FROM (
            -- 1. usulan MOVE (stok total tidak berubah)
            SELECT 1 AS urut, 'WHOLE' AS Kind, 'MOVE' AS ActionUsulan,
                   p.from_line_id AS thread_opname_line_id, p.thread_item_id,
                   p.from_location_id, p.to_location_id, p.qty,
                   NULL AS system_qty, NULL AS counted_qty,
                   NULL AS split_cone_id, CAST(0 AS BIT) AS reason_required
            FROM pairs p

            UNION ALL
            -- 2. sisa selisih per rak = ADJUST (alasan WAJIB)
            SELECT 2, 'WHOLE', 'ADJUST',
                   s.thread_opname_line_id, s.thread_item_id,
                   CASE WHEN s.sisa_diff < 0 THEN s.thread_location_id END,
                   CASE WHEN s.sisa_diff > 0 THEN s.thread_location_id END,
                   s.sisa_diff,
                   s.system_qty, s.counted_qty,
                   NULL, CAST(1 AS BIT)
            FROM sisa s
            WHERE s.sisa_diff <> 0

            UNION ALL
            -- 3. kones split tidak ditemukan -> ADJUST_SPLIT (jadi EMPTY), alasan WAJIB
            SELECT 3, 'SPLIT', 'ADJUST_SPLIT',
                   l.thread_opname_line_id, l.thread_item_id,
                   l.thread_location_id, NULL, NULL,
                   NULL, NULL,
                   sp.thread_split_cone_id, CAST(1 AS BIT)
            FROM inv.thread_opname_splits sp
            INNER JOIN inv.thread_opname_lines l ON l.thread_opname_line_id = sp.thread_opname_line_id
            INNER JOIN inv.thread_split_cones c2 ON c2.thread_split_cone_id = sp.thread_split_cone_id
            WHERE l.thread_opname_session_id = @SessionId
              AND l.deleted_at IS NULL AND sp.deleted_at IS NULL
              AND sp.is_found = 0
              AND c2.thread_location_id = l.thread_location_id   -- memang seharusnya di rak ini

            UNION ALL
            -- 4. kones split ditemukan di rak LAIN -> MOVE_SPLIT (bukan selisih)
            SELECT 4, 'SPLIT', 'MOVE_SPLIT',
                   l.thread_opname_line_id, l.thread_item_id,
                   c2.thread_location_id, l.thread_location_id, NULL,
                   NULL, NULL,
                   sp.thread_split_cone_id, CAST(0 AS BIT)
            FROM inv.thread_opname_splits sp
            INNER JOIN inv.thread_opname_lines l ON l.thread_opname_line_id = sp.thread_opname_line_id
            INNER JOIN inv.thread_split_cones c2 ON c2.thread_split_cone_id = sp.thread_split_cone_id
            WHERE l.thread_opname_session_id = @SessionId
              AND l.deleted_at IS NULL AND sp.deleted_at IS NULL
              AND sp.is_found = 1
              AND ISNULL(c2.thread_location_id, -1) <> l.thread_location_id
        ) u
        INNER JOIN inv.thread_items i  ON i.thread_item_id = u.thread_item_id
        INNER JOIN inv.thread_types t  ON t.thread_type_id = i.thread_type_id
        INNER JOIN inv.thread_brands b ON b.thread_brand_id = i.thread_brand_id
        LEFT JOIN inv.thread_locations lf ON lf.thread_location_id = u.from_location_id
        LEFT JOIN inv.thread_locations lt ON lt.thread_location_id = u.to_location_id
        LEFT JOIN inv.thread_split_cones c ON c.thread_split_cone_id = u.split_cone_id
        ORDER BY u.urut, i.color_name, u.from_location_id, u.to_location_id;

        RETURN;
    END

    -- ============================= CLOSE =============================
    -- @ResolutionsJson: array objek
    --   {"line_id":1,"action":"MOVE|ADJUST|NONE|MOVE_SPLIT|ADJUST_SPLIT",
    --    "qty":2,"from_location_id":1,"to_location_id":2,
    --    "split_cone_id":9,"reason_code":"HILANG","note":"..."}
    -- line_id pada MOVE = baris rak ASAL (yang minus).
    -- CATATAN: action MOVE_SPLIT & ADJUST_SPLIT adalah TAMBAHAN atas skema di prompt --
    -- tanpa itu resolusi kones split tidak bisa diwakili sama sekali.
    IF @Action = 'CLOSE'
    BEGIN
        DECLARE @BelumSemua INT = (SELECT COUNT(*) FROM inv.thread_opname_lines
                                    WHERE thread_opname_session_id = @SessionId
                                      AND counted_qty IS NULL AND deleted_at IS NULL);

        IF @BelumSemua > 0
        BEGIN
            RAISERROR('Masih ada %d SKU belum dihitung.', 16, 1, @BelumSemua);
            RETURN;
        END

        DECLARE @Res TABLE (
            res_id INT IDENTITY(1,1) PRIMARY KEY,
            line_id INT,
            [action] VARCHAR(20),
            qty INT,
            from_location_id INT,
            to_location_id INT,
            split_cone_id INT,
            reason_code VARCHAR(30),
            note VARCHAR(500)
        );

        IF @ResolutionsJson IS NOT NULL AND LTRIM(RTRIM(@ResolutionsJson)) NOT IN ('', '[]')
            INSERT INTO @Res (line_id, [action], qty, from_location_id, to_location_id,
                              split_cone_id, reason_code, note)
            SELECT j.line_id, UPPER(LTRIM(RTRIM(j.[action]))), j.qty,
                   j.from_location_id, j.to_location_id, j.split_cone_id,
                   NULLIF(LTRIM(RTRIM(ISNULL(j.reason_code,''))), ''),
                   NULLIF(LTRIM(RTRIM(ISNULL(j.note,''))), '')
            FROM OPENJSON(@ResolutionsJson)
                 WITH (line_id INT '$.line_id',
                       [action] VARCHAR(20) '$.action',
                       qty INT '$.qty',
                       from_location_id INT '$.from_location_id',
                       to_location_id INT '$.to_location_id',
                       split_cone_id INT '$.split_cone_id',
                       reason_code VARCHAR(30) '$.reason_code',
                       note VARCHAR(500) '$.note') j;

        -- ---------- validasi ULANG di SP (client tidak dipercaya) ----------

        IF EXISTS (SELECT 1 FROM @Res r
                    WHERE r.[action] NOT IN ('MOVE','ADJUST','NONE','MOVE_SPLIT','ADJUST_SPLIT'))
        BEGIN
            RAISERROR('Ada resolusi dengan action yang tidak dikenal.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Res r
                    LEFT JOIN inv.thread_opname_lines l
                           ON l.thread_opname_line_id = r.line_id
                          AND l.thread_opname_session_id = @SessionId
                          AND l.deleted_at IS NULL
                    WHERE l.thread_opname_line_id IS NULL)
        BEGIN
            RAISERROR('Ada resolusi yang menunjuk baris opname di luar sesi ini.', 16, 1);
            RETURN;
        END

        -- alasan wajib untuk ADJUST & ADJUST_SPLIT
        IF EXISTS (SELECT 1 FROM @Res r
                    WHERE r.[action] IN ('ADJUST','ADJUST_SPLIT') AND r.reason_code IS NULL)
        BEGIN
            RAISERROR('Setiap penyesuaian stok wajib punya alasan.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Res r
                    WHERE r.[action] IN ('ADJUST','ADJUST_SPLIT')
                      AND NOT EXISTS (SELECT 1 FROM inv.thread_reason_codes rc
                                       WHERE rc.code = r.reason_code AND rc.deleted_at IS NULL))
        BEGIN
            RAISERROR('Ada alasan penyesuaian yang tidak dikenal.', 16, 1);
            RETURN;
        END

        -- alasan dengan requires_note = 1 (mis. LAINNYA) -> keterangan wajib
        DECLARE @ReasonTanpaNote VARCHAR(30) =
            (SELECT TOP 1 r.reason_code FROM @Res r
              INNER JOIN inv.thread_reason_codes rc ON rc.code = r.reason_code
              WHERE r.[action] IN ('ADJUST','ADJUST_SPLIT')
                AND rc.requires_note = 1 AND r.note IS NULL);

        IF @ReasonTanpaNote IS NOT NULL
        BEGIN
            RAISERROR('Alasan "%s" wajib diisi keterangannya.', 16, 1, @ReasonTanpaNote);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Res r WHERE r.[action] = 'MOVE'
                    AND (ISNULL(r.qty,0) <= 0 OR r.from_location_id IS NULL OR r.to_location_id IS NULL
                         OR r.from_location_id = r.to_location_id))
        BEGIN
            RAISERROR('Usulan pindah rak harus punya rak asal, rak tujuan berbeda, dan jumlah lebih dari 0.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM @Res r WHERE r.[action] = 'ADJUST' AND ISNULL(r.qty,0) = 0)
        BEGIN
            RAISERROR('Penyesuaian dengan jumlah 0 tidak perlu dicatat.', 16, 1);
            RETURN;
        END

        -- MOVE tidak boleh melebihi minus rak asalnya
        IF EXISTS (
            SELECT 1
            FROM (SELECT r.from_location_id, l.thread_item_id, SUM(r.qty) AS qty_move
                  FROM @Res r
                  INNER JOIN inv.thread_opname_lines l ON l.thread_opname_line_id = r.line_id
                  WHERE r.[action] = 'MOVE'
                  GROUP BY r.from_location_id, l.thread_item_id) m
            INNER JOIN inv.thread_opname_lines ls
                    ON ls.thread_opname_session_id = @SessionId
                   AND ls.thread_location_id = m.from_location_id
                   AND ls.thread_item_id = m.thread_item_id
                   AND ls.deleted_at IS NULL
            WHERE m.qty_move > (ls.system_qty - ls.counted_qty))
        BEGIN
            RAISERROR('Jumlah pindah rak melebihi kekurangan di rak asalnya.', 16, 1);
            RETURN;
        END

        -- Hasil akhir per rak HARUS sama dengan counted_qty.
        DECLARE @SalahSaldo INT = (
            SELECT COUNT(*)
            FROM inv.thread_opname_lines l
            OUTER APPLY (
                SELECT ISNULL(SUM(x.delta), 0) AS delta
                FROM (
                    SELECT -r.qty AS delta
                    FROM @Res r
                    INNER JOIN inv.thread_opname_lines lr ON lr.thread_opname_line_id = r.line_id
                    WHERE r.[action] = 'MOVE'
                      AND lr.thread_item_id = l.thread_item_id
                      AND r.from_location_id = l.thread_location_id
                    UNION ALL
                    SELECT r.qty
                    FROM @Res r
                    INNER JOIN inv.thread_opname_lines lr ON lr.thread_opname_line_id = r.line_id
                    WHERE r.[action] = 'MOVE'
                      AND lr.thread_item_id = l.thread_item_id
                      AND r.to_location_id = l.thread_location_id
                    UNION ALL
                    SELECT r.qty
                    FROM @Res r
                    WHERE r.[action] = 'ADJUST' AND r.line_id = l.thread_opname_line_id
                ) x
            ) agg
            WHERE l.thread_opname_session_id = @SessionId
              AND l.deleted_at IS NULL
              AND l.counted_qty IS NOT NULL
              AND l.system_qty + agg.delta <> l.counted_qty);

        IF @SalahSaldo > 0
        BEGIN
            RAISERROR('Resolusi belum menutup selisih di %d baris -- periksa lagi usulannya.', 16, 1, @SalahSaldo);
            RETURN;
        END

        -- ---------- posting ----------
        BEGIN TRY
            BEGIN TRANSACTION;

            -- Penampung result set SIS_ThreadMovement_Manage: INSERT ... EXEC dipakai supaya
            -- result set tiap mutasi TIDAK ikut terkirim ke client sebagai hasil CLOSE.
            --
            -- PENTING: karena itu, action CLOSE sendiri TIDAK BOLEH dipanggil lewat
            -- INSERT ... EXEC (INSERT-EXEC tidak bisa bersarang -- SQL Server lalu
            -- melempar "Cannot use the ROLLBACK statement within an INSERT-EXEC
            -- statement"). API memanggilnya lewat EF SqlQueryRaw (perintah biasa), dan
            -- sql/inv/test_74_opname.sql juga memakai EXEC biasa untuk CLOSE.
            DECLARE @MvOut TABLE (MovementId INT, ThreadSplitConeId INT, ConeCode VARCHAR(20), WeightGram INT);

            DECLARE @i INT = 1, @n INT = (SELECT ISNULL(MAX(res_id), 0) FROM @Res);
            DECLARE @rAction VARCHAR(20), @rLine INT, @rQty INT, @rFrom INT, @rTo INT,
                    @rCone INT, @rReason VARCHAR(30), @rNote VARCHAR(500), @rItem INT,
                    @rLoc INT, @MvId INT;

            WHILE @i <= @n
            BEGIN
                SELECT @rAction = [action], @rLine = line_id, @rQty = qty,
                       @rFrom = from_location_id, @rTo = to_location_id,
                       @rCone = split_cone_id, @rReason = reason_code, @rNote = note
                FROM @Res WHERE res_id = @i;

                IF @rAction IS NULL
                BEGIN
                    SET @i += 1;
                    CONTINUE;
                END

                -- EXEC tidak menerima subquery sebagai nilai parameter -- ambil dulu
                -- ke variabel (pelajaran sama seperti EXEC proc @P = CONCAT(...)).
                SELECT @rItem = thread_item_id, @rLoc = thread_location_id
                FROM inv.thread_opname_lines
                WHERE thread_opname_line_id = @rLine;

                DELETE FROM @MvOut;
                SET @MvId = NULL;

                IF @rAction = 'MOVE'
                BEGIN
                    INSERT INTO @MvOut
                    EXEC inv.SIS_ThreadMovement_Manage
                        @Action = 'MOVE', @ItemId = @rItem,
                        @FromLocationId = @rFrom, @ToLocationId = @rTo,
                        @Qty = @rQty, @Note = @rNote,
                        @OpnameLineId = @rLine, @UserId = @UserId;
                END
                ELSE IF @rAction = 'ADJUST'
                BEGIN
                    INSERT INTO @MvOut
                    EXEC inv.SIS_ThreadMovement_Manage
                        @Action = 'ADJUST', @ItemId = @rItem, @LocationId = @rLoc,
                        @Qty = @rQty, @ReasonCode = @rReason, @Note = @rNote,
                        @OpnameLineId = @rLine, @UserId = @UserId;
                END
                ELSE IF @rAction = 'ADJUST_SPLIT'
                BEGIN
                    INSERT INTO @MvOut
                    EXEC inv.SIS_ThreadMovement_Manage
                        @Action = 'ADJUST_SPLIT', @SplitConeId = @rCone,
                        @ReasonCode = @rReason, @Note = @rNote,
                        @OpnameLineId = @rLine, @UserId = @UserId;
                END
                ELSE IF @rAction = 'MOVE_SPLIT'
                BEGIN
                    INSERT INTO @MvOut
                    EXEC inv.SIS_ThreadMovement_Manage
                        @Action = 'MOVE_SPLIT', @SplitConeId = @rCone,
                        @ToLocationId = @rTo, @Note = @rNote,
                        @OpnameLineId = @rLine, @UserId = @UserId;
                END

                SELECT TOP 1 @MvId = MovementId FROM @MvOut;

                UPDATE inv.thread_opname_lines
                SET resolution = CASE WHEN @rAction LIKE 'MOVE%' THEN 'MOVE'
                                      WHEN @rAction LIKE 'ADJUST%' THEN 'ADJUST'
                                      ELSE 'NONE' END,
                    resolved_movement_id = ISNULL(@MvId, resolved_movement_id),
                    updated_at = SYSDATETIME(), updated_by = @UserId
                WHERE thread_opname_line_id = @rLine;

                SET @i += 1;
            END

            -- Baris tanpa selisih & tanpa resolusi = NONE.
            UPDATE inv.thread_opname_lines
            SET resolution = 'NONE', updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_opname_session_id = @SessionId
              AND deleted_at IS NULL
              AND resolution IS NULL;

            UPDATE inv.thread_opname_locations
            SET [status] = 'DONE', updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_opname_session_id = @SessionId AND deleted_at IS NULL AND [status] <> 'DONE';

            UPDATE inv.thread_opname_sessions
            SET [status] = 'CLOSED',
                closed_at = SYSDATETIME(),
                closed_by = @UserId,
                note = ISNULL(@Note, note),
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_opname_session_id = @SessionId;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        SELECT @SessionId AS Value;
        RETURN;
    END
END;
GO

-- =============================================================
-- BACA
-- =============================================================

-- Sesi OPEN (kalau ada) + progres per rak. @Bagian membatasi ke satu result set
-- karena EF Core hanya bisa membaca satu per pemanggilan.
CREATE OR ALTER PROCEDURE inv.SIS_ThreadOpname_Current
    @Bagian VARCHAR(10) = NULL        -- SESI | RAK | NULL = keduanya
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SessionId INT = (SELECT TOP 1 thread_opname_session_id
                              FROM inv.thread_opname_sessions
                              WHERE [status] = 'OPEN' AND deleted_at IS NULL
                              ORDER BY thread_opname_session_id DESC);

    IF @Bagian IS NULL OR @Bagian = 'SESI'
        SELECT s.thread_opname_session_id AS SessionId,
               s.session_no              AS SessionNo,
               s.[status]                AS Status,
               s.started_at              AS StartedAt,
               s.closed_at               AS ClosedAt,
               u.FullName                AS StartedByName,
               s.note                    AS Note,
               (SELECT COUNT(*) FROM inv.thread_opname_locations ol
                 WHERE ol.thread_opname_session_id = s.thread_opname_session_id
                   AND ol.deleted_at IS NULL) AS TotalRak,
               (SELECT COUNT(*) FROM inv.thread_opname_locations ol
                 WHERE ol.thread_opname_session_id = s.thread_opname_session_id
                   AND ol.deleted_at IS NULL AND ol.[status] = 'DONE') AS RakSelesai,
               (SELECT COUNT(*) FROM inv.thread_opname_lines l
                 WHERE l.thread_opname_session_id = s.thread_opname_session_id
                   AND l.deleted_at IS NULL) AS TotalSku,
               (SELECT COUNT(*) FROM inv.thread_opname_lines l
                 WHERE l.thread_opname_session_id = s.thread_opname_session_id
                   AND l.deleted_at IS NULL AND l.counted_qty IS NOT NULL) AS SkuDihitung,
               (SELECT COUNT(*) FROM inv.thread_opname_lines l
                 WHERE l.thread_opname_session_id = s.thread_opname_session_id
                   AND l.deleted_at IS NULL AND l.counted_qty IS NOT NULL
                   AND l.counted_qty <> l.system_qty) AS SkuSelisih
        FROM inv.thread_opname_sessions s
        LEFT JOIN dbo.Users u ON u.Id = s.created_by
        WHERE s.thread_opname_session_id = @SessionId;

    IF @Bagian IS NULL OR @Bagian = 'RAK'
        SELECT ol.thread_opname_session_id AS SessionId,
               ol.thread_location_id       AS ThreadLocationId,
               l.code                      AS Code,
               l.name                      AS Name,
               ol.[status]                 AS Status,
               (SELECT COUNT(*) FROM inv.thread_opname_lines ln
                 WHERE ln.thread_opname_session_id = ol.thread_opname_session_id
                   AND ln.thread_location_id = ol.thread_location_id
                   AND ln.deleted_at IS NULL) AS TotalSku,
               (SELECT COUNT(*) FROM inv.thread_opname_lines ln
                 WHERE ln.thread_opname_session_id = ol.thread_opname_session_id
                   AND ln.thread_location_id = ol.thread_location_id
                   AND ln.deleted_at IS NULL AND ln.counted_qty IS NOT NULL) AS SkuDihitung,
               (SELECT COUNT(*) FROM inv.thread_opname_lines ln
                 WHERE ln.thread_opname_session_id = ol.thread_opname_session_id
                   AND ln.thread_location_id = ol.thread_location_id
                   AND ln.deleted_at IS NULL AND ln.counted_qty IS NOT NULL
                   AND ln.counted_qty <> ln.system_qty) AS SkuSelisih
        FROM inv.thread_opname_locations ol
        INNER JOIN inv.thread_locations l ON l.thread_location_id = ol.thread_location_id
        WHERE ol.thread_opname_session_id = @SessionId
          AND ol.deleted_at IS NULL
        ORDER BY l.sort_order, l.code;
END;
GO

-- Baris satu rak dalam satu sesi (+ checklist split sebagai result set kedua
-- lewat @Bagian = 'SPLIT').
CREATE OR ALTER PROCEDURE inv.SIS_ThreadOpname_Lines
    @SessionId  INT,
    @LocationId INT = NULL,
    @Bagian     VARCHAR(10) = NULL     -- LINE | SPLIT | NULL = keduanya
AS
BEGIN
    SET NOCOUNT ON;

    IF @Bagian IS NULL OR @Bagian = 'LINE'
        SELECT l.thread_opname_line_id AS LineId,
               l.thread_opname_session_id AS SessionId,
               l.thread_location_id   AS ThreadLocationId,
               loc.code               AS LocationCode,
               l.thread_item_id       AS ThreadItemId,
               i.sku_code             AS SkuCode,
               i.color_name           AS ColorName,
               i.color_code           AS ColorCode,
               i.cone_size            AS ConeSize,
               i.photo_path           AS PhotoPath,
               t.name                 AS TypeName,
               b.name                 AS BrandName,
               l.system_qty           AS SystemQty,
               l.counted_qty          AS CountedQty,
               l.split_expected       AS SplitExpected,
               l.split_found          AS SplitFound,
               l.resolution           AS Resolution,
               l.counted_at           AS CountedAt,
               u.FullName             AS CountedByName
        FROM inv.thread_opname_lines l
        INNER JOIN inv.thread_items i    ON i.thread_item_id = l.thread_item_id
        INNER JOIN inv.thread_types t    ON t.thread_type_id = i.thread_type_id
        INNER JOIN inv.thread_brands b   ON b.thread_brand_id = i.thread_brand_id
        INNER JOIN inv.thread_locations loc ON loc.thread_location_id = l.thread_location_id
        LEFT JOIN dbo.Users u            ON u.Id = l.counted_by
        WHERE l.thread_opname_session_id = @SessionId
          AND (@LocationId IS NULL OR l.thread_location_id = @LocationId)
          AND l.deleted_at IS NULL
        ORDER BY loc.sort_order, loc.code, i.color_name;

    IF @Bagian IS NULL OR @Bagian = 'SPLIT'
        SELECT sp.thread_opname_split_id AS OpnameSplitId,
               sp.thread_opname_line_id  AS LineId,
               sp.thread_split_cone_id   AS ThreadSplitConeId,
               c.cone_code               AS ConeCode,
               c.weight_gram             AS WeightGram,
               sp.is_found               AS IsFound,
               lc.code                   AS SystemLocationCode
        FROM inv.thread_opname_splits sp
        INNER JOIN inv.thread_opname_lines l ON l.thread_opname_line_id = sp.thread_opname_line_id
        INNER JOIN inv.thread_split_cones c  ON c.thread_split_cone_id = sp.thread_split_cone_id
        LEFT JOIN inv.thread_locations lc    ON lc.thread_location_id = c.thread_location_id
        WHERE l.thread_opname_session_id = @SessionId
          AND (@LocationId IS NULL OR l.thread_location_id = @LocationId)
          AND l.deleted_at IS NULL AND sp.deleted_at IS NULL
        ORDER BY c.cone_code;
END;
GO

-- Riwayat sesi (bentuk result set SAMA dengan bagian SESI di _Current).
CREATE OR ALTER PROCEDURE inv.SIS_ThreadOpname_List
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Top IS NULL OR @Top < 1 OR @Top > 200 SET @Top = 50;

    SELECT TOP (@Top)
           s.thread_opname_session_id AS SessionId,
           s.session_no              AS SessionNo,
           s.[status]                AS Status,
           s.started_at              AS StartedAt,
           s.closed_at               AS ClosedAt,
           u.FullName                AS StartedByName,
           s.note                    AS Note,
           (SELECT COUNT(*) FROM inv.thread_opname_locations ol
             WHERE ol.thread_opname_session_id = s.thread_opname_session_id
               AND ol.deleted_at IS NULL) AS TotalRak,
           (SELECT COUNT(*) FROM inv.thread_opname_locations ol
             WHERE ol.thread_opname_session_id = s.thread_opname_session_id
               AND ol.deleted_at IS NULL AND ol.[status] = 'DONE') AS RakSelesai,
           (SELECT COUNT(*) FROM inv.thread_opname_lines l
             WHERE l.thread_opname_session_id = s.thread_opname_session_id
               AND l.deleted_at IS NULL) AS TotalSku,
           (SELECT COUNT(*) FROM inv.thread_opname_lines l
             WHERE l.thread_opname_session_id = s.thread_opname_session_id
               AND l.deleted_at IS NULL AND l.counted_qty IS NOT NULL) AS SkuDihitung,
           (SELECT COUNT(*) FROM inv.thread_opname_lines l
             WHERE l.thread_opname_session_id = s.thread_opname_session_id
               AND l.deleted_at IS NULL AND l.counted_qty IS NOT NULL
               AND l.counted_qty <> l.system_qty) AS SkuSelisih
    FROM inv.thread_opname_sessions s
    LEFT JOIN dbo.Users u ON u.Id = s.created_by
    WHERE s.deleted_at IS NULL
    ORDER BY s.thread_opname_session_id DESC;
END;
GO

-- Satu sesi (biasanya CLOSED): header + baris dengan resolusi & movement-nya.
CREATE OR ALTER PROCEDURE inv.SIS_ThreadOpname_GetById
    @SessionId INT,
    @Bagian    VARCHAR(10) = NULL      -- SESI | HASIL | NULL = keduanya
AS
BEGIN
    SET NOCOUNT ON;

    IF @Bagian IS NULL OR @Bagian = 'SESI'
        SELECT s.thread_opname_session_id AS SessionId,
               s.session_no              AS SessionNo,
               s.[status]                AS Status,
               s.started_at              AS StartedAt,
               s.closed_at               AS ClosedAt,
               u.FullName                AS StartedByName,
               s.note                    AS Note,
               (SELECT COUNT(*) FROM inv.thread_opname_locations ol
                 WHERE ol.thread_opname_session_id = s.thread_opname_session_id
                   AND ol.deleted_at IS NULL) AS TotalRak,
               (SELECT COUNT(*) FROM inv.thread_opname_locations ol
                 WHERE ol.thread_opname_session_id = s.thread_opname_session_id
                   AND ol.deleted_at IS NULL AND ol.[status] = 'DONE') AS RakSelesai,
               (SELECT COUNT(*) FROM inv.thread_opname_lines l
                 WHERE l.thread_opname_session_id = s.thread_opname_session_id
                   AND l.deleted_at IS NULL) AS TotalSku,
               (SELECT COUNT(*) FROM inv.thread_opname_lines l
                 WHERE l.thread_opname_session_id = s.thread_opname_session_id
                   AND l.deleted_at IS NULL AND l.counted_qty IS NOT NULL) AS SkuDihitung,
               (SELECT COUNT(*) FROM inv.thread_opname_lines l
                 WHERE l.thread_opname_session_id = s.thread_opname_session_id
                   AND l.deleted_at IS NULL AND l.counted_qty IS NOT NULL
                   AND l.counted_qty <> l.system_qty) AS SkuSelisih
        FROM inv.thread_opname_sessions s
        LEFT JOIN dbo.Users u ON u.Id = s.created_by
        WHERE s.thread_opname_session_id = @SessionId;

    IF @Bagian IS NULL OR @Bagian = 'HASIL'
        SELECT l.thread_opname_line_id AS LineId,
               loc.code                AS LocationCode,
               i.sku_code              AS SkuCode,
               i.color_name            AS ColorName,
               i.color_code            AS ColorCode,
               l.system_qty            AS SystemQty,
               l.counted_qty           AS CountedQty,
               l.split_expected        AS SplitExpected,
               l.split_found           AS SplitFound,
               l.resolution            AS Resolution,
               m.movement_type         AS MovementType,
               m.qty_whole             AS MovementQty,
               m.reason_code           AS ReasonCode,
               rc.name                 AS ReasonName,
               m.note                  AS Note,
               mf.code                 AS MovementFromCode,
               mt.code                 AS MovementToCode,
               u.FullName              AS CountedByName,
               l.counted_at            AS CountedAt
        FROM inv.thread_opname_lines l
        INNER JOIN inv.thread_items i       ON i.thread_item_id = l.thread_item_id
        INNER JOIN inv.thread_locations loc ON loc.thread_location_id = l.thread_location_id
        LEFT JOIN inv.thread_movements m     ON m.thread_movement_id = l.resolved_movement_id
        LEFT JOIN inv.thread_reason_codes rc ON rc.code = m.reason_code
        LEFT JOIN inv.thread_locations mf     ON mf.thread_location_id = m.from_location_id
        LEFT JOIN inv.thread_locations mt     ON mt.thread_location_id = m.to_location_id
        LEFT JOIN dbo.Users u                ON u.Id = l.counted_by
        WHERE l.thread_opname_session_id = @SessionId
          AND l.deleted_at IS NULL
        ORDER BY loc.sort_order, loc.code, i.color_name;
END;
GO

-- Daftar kategori alasan ADJUST (dropdown saat tutup sesi).
CREATE OR ALTER PROCEDURE inv.SIS_ThreadReasonCode_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT code          AS Code,
           name          AS Name,
           requires_note AS RequiresNote,
           sort_order    AS SortOrder
    FROM inv.thread_reason_codes
    WHERE deleted_at IS NULL
    ORDER BY sort_order, name;
END;
GO
