/* =============================================================
   Module Stok Benang (Prompt 72) -- movement schema `inv`:
   Terima, Ambil (whole/split), Kembali & timbang, Pindah rak, Habis.

   SATU SP mutasi untuk semua jenis: inv.SIS_ThreadMovement_Manage (@Action).
   Setiap action menulis inv.thread_movements DAN memperbarui saldo
   (inv.thread_stocks / inv.thread_split_cones) dalam SATU transaksi.
   Saldo TIDAK BOLEH minus -- ditolak dengan RAISERROR bahasa Indonesia.

   ADJUST / ADJUST_SPLIT TIDAK ada di sini (Prompt 74, stock opname).

   Semua action mengembalikan result set dengan BENTUK SAMA
   (MovementId, ThreadSplitConeId, ConeCode, WeightGram) karena satu DTO
   dipakai bersama di API -- EF Core menolak kalau ada kolom yang hilang.

   ANSI_NULLS / QUOTED_IDENTIFIER wajib ON: tabel inv.* punya filtered index.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE inv.SIS_ThreadMovement_Manage
    @Action         VARCHAR(20),       -- RECEIVE | ISSUE | RETURN | ISSUE_SPLIT | RETURN_SPLIT | MOVE | MOVE_SPLIT | EMPTY
    @ItemId         INT = NULL,
    @SplitConeId    INT = NULL,
    @FromLocationId INT = NULL,
    @ToLocationId   INT = NULL,
    @Qty            INT = NULL,
    @WeightGram     INT = NULL,
    @ResourceId     INT = NULL,
    @ProjectId      INT = NULL,
    @Note           VARCHAR(500) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Action NOT IN ('RECEIVE','ISSUE','RETURN','ISSUE_SPLIT','RETURN_SPLIT','MOVE','MOVE_SPLIT','EMPTY')
    BEGIN
        RAISERROR('Jenis mutasi "%s" tidak dikenal.', 16, 1, @Action);
        RETURN;
    END

    SET @Note = NULLIF(LTRIM(RTRIM(ISNULL(@Note,''))), '');

    DECLARE @MovementId INT = NULL;
    DECLARE @ConeCode VARCHAR(20) = NULL;
    DECLARE @FromCode VARCHAR(20), @ToCode VARCHAR(20);
    DECLARE @Saldo INT;

    -- ---------------- validasi yang dipakai beberapa action ----------------

    -- Action yang bekerja pada SATU kones split: ambil dulu baris & SKU-nya.
    IF @Action IN ('ISSUE_SPLIT','RETURN_SPLIT','MOVE_SPLIT','EMPTY')
    BEGIN
        DECLARE @ConeStatus VARCHAR(10), @ConeWeight INT;

        SELECT @ItemId = thread_item_id,
               @ConeCode = cone_code,
               @ConeStatus = [status],
               @ConeWeight = weight_gram
        FROM inv.thread_split_cones
        WHERE thread_split_cone_id = @SplitConeId AND deleted_at IS NULL;

        IF @ConeCode IS NULL
        BEGIN
            RAISERROR('Kones split tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @ConeStatus = 'EMPTY'
        BEGIN
            RAISERROR('Kones %s sudah ditandai habis.', 16, 1, @ConeCode);
            RETURN;
        END

        IF @Action = 'ISSUE_SPLIT' AND @ConeStatus <> 'IN_STOCK'
        BEGIN
            RAISERROR('Kones %s sedang dipakai di line -- tidak bisa diambil lagi.', 16, 1, @ConeCode);
            RETURN;
        END

        IF @Action = 'RETURN_SPLIT' AND @ConeStatus <> 'ISSUED'
        BEGIN
            RAISERROR('Kones %s tidak sedang dipakai di line, jadi tidak perlu dikembalikan.', 16, 1, @ConeCode);
            RETURN;
        END

        IF @Action = 'MOVE_SPLIT' AND @ConeStatus <> 'IN_STOCK'
        BEGIN
            RAISERROR('Kones %s sedang dipakai di line -- pindahkan setelah kembali ke gudang.', 16, 1, @ConeCode);
            RETURN;
        END
    END
    ELSE
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM inv.thread_items
                        WHERE thread_item_id = @ItemId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('SKU benang tidak ditemukan.', 16, 1);
            RETURN;
        END
    END

    -- Lokasi tujuan: harus ada DAN aktif (rak nonaktif tidak boleh menerima isi baru).
    IF @Action IN ('RECEIVE','RETURN','RETURN_SPLIT','MOVE','MOVE_SPLIT')
    BEGIN
        SELECT @ToCode = code FROM inv.thread_locations
        WHERE thread_location_id = @ToLocationId AND deleted_at IS NULL AND is_active = 1;

        IF @ToCode IS NULL
        BEGIN
            RAISERROR('Rak tujuan tidak dikenal atau sudah nonaktif.', 16, 1);
            RETURN;
        END
    END

    -- Lokasi asal: cukup ada (rak nonaktif tetap boleh dikosongkan).
    IF @Action IN ('ISSUE','MOVE')
    BEGIN
        SELECT @FromCode = code FROM inv.thread_locations
        WHERE thread_location_id = @FromLocationId AND deleted_at IS NULL;

        IF @FromCode IS NULL
        BEGIN
            RAISERROR('Rak asal tidak dikenal.', 16, 1);
            RETURN;
        END
    END

    -- Jumlah kones.
    IF @Action IN ('RECEIVE','ISSUE','MOVE') AND ISNULL(@Qty, 0) <= 0
    BEGIN
        RAISERROR('Jumlah kones harus lebih dari 0.', 16, 1);
        RETURN;
    END

    -- Berat netto.
    IF @Action IN ('RETURN','RETURN_SPLIT') AND ISNULL(@WeightGram, 0) <= 0
    BEGIN
        RAISERROR('Berat netto harus lebih dari 0 gram.', 16, 1);
        RETURN;
    END

    -- Line + project/keterangan untuk pengambilan ke produksi.
    IF @Action IN ('ISSUE','ISSUE_SPLIT')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.resources
                        WHERE resource_id = @ResourceId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Line tujuan wajib dipilih.', 16, 1);
            RETURN;
        END

        IF @ProjectId IS NULL AND @Note IS NULL
        BEGIN
            RAISERROR('Isi project atau keterangan.', 16, 1);
            RETURN;
        END
    END

    IF @ProjectId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.projects
                        WHERE project_id = @ProjectId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Project tidak dikenal.', 16, 1);
        RETURN;
    END

    IF @ResourceId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM dbo.resources
                        WHERE resource_id = @ResourceId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Line tidak dikenal.', 16, 1);
        RETURN;
    END

    -- Semua penolakan di dalam TRY di bawah memakai RAISERROR: eksekusi langsung
    -- pindah ke CATCH, yang me-ROLLBACK lalu THROW ulang pesannya ke API.
    BEGIN TRY
        BEGIN TRANSACTION;

        -- ======================= RECEIVE =======================
        IF @Action = 'RECEIVE'
        BEGIN
            UPDATE inv.thread_stocks
            SET qty_whole = qty_whole + @Qty,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_item_id = @ItemId AND thread_location_id = @ToLocationId AND deleted_at IS NULL;

            IF @@ROWCOUNT = 0
                INSERT INTO inv.thread_stocks (thread_item_id, thread_location_id, qty_whole, created_by)
                VALUES (@ItemId, @ToLocationId, @Qty, @UserId);

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, to_location_id, qty_whole, project_id, note, created_by)
            VALUES ('RECEIVE', @ItemId, @ToLocationId, @Qty, @ProjectId, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
        END

        -- ======================= ISSUE (whole) =======================
        ELSE IF @Action = 'ISSUE'
        BEGIN
            SELECT @Saldo = qty_whole FROM inv.thread_stocks
            WHERE thread_item_id = @ItemId AND thread_location_id = @FromLocationId AND deleted_at IS NULL;

            SET @Saldo = ISNULL(@Saldo, 0);

            IF @Saldo < @Qty
            BEGIN
                RAISERROR('Stok di rak %s hanya %d kones.', 16, 1, @FromCode, @Saldo);
            END

            UPDATE inv.thread_stocks
            SET qty_whole = qty_whole - @Qty,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_item_id = @ItemId AND thread_location_id = @FromLocationId AND deleted_at IS NULL;

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, from_location_id, qty_whole, resource_id, project_id, note, created_by)
            VALUES ('ISSUE', @ItemId, @FromLocationId, -@Qty, @ResourceId, @ProjectId, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
        END

        -- ======================= RETURN (kones kembali = SPLIT baru) =======================
        -- TIDAK ADA kembali sebagai whole: semua yang kembali dari line dianggap
        -- split dan dapat kode + label sendiri (keputusan desain bagian 3).
        ELSE IF @Action = 'RETURN'
        BEGIN
            DECLARE @Lock INT;
            EXEC @Lock = sp_getapplock @Resource = 'thread_split_seq',
                 @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 15000;

            IF @Lock < 0
            BEGIN
                RAISERROR('Sistem sedang membuat kode kones lain, coba lagi sebentar.', 16, 1);
            END

            -- Baris yang sudah di-soft-delete IKUT dihitung supaya kode tidak terpakai dua kali.
            DECLARE @Next INT;
            SELECT @Next = ISNULL(MAX(CAST(SUBSTRING(cone_code, 4, 6) AS INT)), 0) + 1
            FROM inv.thread_split_cones
            WHERE cone_code LIKE 'SP-[0-9][0-9][0-9][0-9][0-9][0-9]';

            SET @ConeCode = 'SP-' + RIGHT('000000' + CAST(@Next AS VARCHAR(10)), 6);

            INSERT INTO inv.thread_split_cones
                (cone_code, thread_item_id, weight_gram, thread_location_id, [status], created_by)
            VALUES (@ConeCode, @ItemId, @WeightGram, @ToLocationId, 'IN_STOCK', @UserId);

            SET @SplitConeId = CAST(SCOPE_IDENTITY() AS INT);

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, thread_split_cone_id, to_location_id,
                 weight_gram, resource_id, project_id, note, created_by)
            VALUES ('RETURN', @ItemId, @SplitConeId, @ToLocationId,
                    @WeightGram, @ResourceId, @ProjectId, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
        END

        -- ======================= ISSUE_SPLIT =======================
        ELSE IF @Action = 'ISSUE_SPLIT'
        BEGIN
            UPDATE inv.thread_split_cones
            SET [status] = 'ISSUED',
                thread_location_id = NULL,
                issued_to_resource_id = @ResourceId,
                issued_project_id = @ProjectId,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_split_cone_id = @SplitConeId;

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, thread_split_cone_id,
                 weight_gram, resource_id, project_id, note, created_by)
            VALUES ('ISSUE_SPLIT', @ItemId, @SplitConeId,
                    @ConeWeight, @ResourceId, @ProjectId, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
            SET @WeightGram = @ConeWeight;
        END

        -- ======================= RETURN_SPLIT (timbang ulang) =======================
        ELSE IF @Action = 'RETURN_SPLIT'
        BEGIN
            -- Benang hanya berkurang saat dipakai: berat kembali tidak boleh naik.
            IF @WeightGram > @ConeWeight
            BEGIN
                RAISERROR('Berat kembali (%d g) lebih besar dari berat terakhir kones %s (%d g).',
                          16, 1, @WeightGram, @ConeCode, @ConeWeight);
            END

            UPDATE inv.thread_split_cones
            SET [status] = 'IN_STOCK',
                weight_gram = @WeightGram,
                thread_location_id = @ToLocationId,
                issued_to_resource_id = NULL,
                issued_project_id = NULL,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_split_cone_id = @SplitConeId;

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, thread_split_cone_id, to_location_id,
                 weight_gram, resource_id, project_id, note, created_by)
            VALUES ('RETURN_SPLIT', @ItemId, @SplitConeId, @ToLocationId,
                    @WeightGram, @ResourceId, @ProjectId, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
        END

        -- ======================= MOVE (whole antar rak) =======================
        ELSE IF @Action = 'MOVE'
        BEGIN
            IF @FromLocationId = @ToLocationId
            BEGIN
                RAISERROR('Rak asal dan rak tujuan sama.', 16, 1);
            END

            SELECT @Saldo = qty_whole FROM inv.thread_stocks
            WHERE thread_item_id = @ItemId AND thread_location_id = @FromLocationId AND deleted_at IS NULL;

            SET @Saldo = ISNULL(@Saldo, 0);

            IF @Saldo < @Qty
            BEGIN
                RAISERROR('Stok di rak %s hanya %d kones.', 16, 1, @FromCode, @Saldo);
            END

            UPDATE inv.thread_stocks
            SET qty_whole = qty_whole - @Qty,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_item_id = @ItemId AND thread_location_id = @FromLocationId AND deleted_at IS NULL;

            UPDATE inv.thread_stocks
            SET qty_whole = qty_whole + @Qty,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_item_id = @ItemId AND thread_location_id = @ToLocationId AND deleted_at IS NULL;

            IF @@ROWCOUNT = 0
                INSERT INTO inv.thread_stocks (thread_item_id, thread_location_id, qty_whole, created_by)
                VALUES (@ItemId, @ToLocationId, @Qty, @UserId);

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, from_location_id, to_location_id, qty_whole, note, created_by)
            VALUES ('MOVE', @ItemId, @FromLocationId, @ToLocationId, @Qty, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
        END

        -- ======================= MOVE_SPLIT =======================
        ELSE IF @Action = 'MOVE_SPLIT'
        BEGIN
            DECLARE @ConeFrom INT = (SELECT thread_location_id FROM inv.thread_split_cones
                                      WHERE thread_split_cone_id = @SplitConeId);

            IF @ConeFrom = @ToLocationId
            BEGIN
                RAISERROR('Kones %s sudah ada di rak itu.', 16, 1, @ConeCode);
            END

            UPDATE inv.thread_split_cones
            SET thread_location_id = @ToLocationId,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_split_cone_id = @SplitConeId;

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, thread_split_cone_id,
                 from_location_id, to_location_id, weight_gram, note, created_by)
            VALUES ('MOVE_SPLIT', @ItemId, @SplitConeId,
                    @ConeFrom, @ToLocationId, @ConeWeight, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
            SET @WeightGram = @ConeWeight;
        END

        -- ======================= EMPTY (kones split dibuang) =======================
        ELSE IF @Action = 'EMPTY'
        BEGIN
            DECLARE @EmptyFrom INT = (SELECT thread_location_id FROM inv.thread_split_cones
                                       WHERE thread_split_cone_id = @SplitConeId);

            UPDATE inv.thread_split_cones
            SET [status] = 'EMPTY',
                thread_location_id = NULL,
                issued_to_resource_id = NULL,
                issued_project_id = NULL,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE thread_split_cone_id = @SplitConeId;

            INSERT INTO inv.thread_movements
                (movement_type, thread_item_id, thread_split_cone_id,
                 from_location_id, weight_gram, note, created_by)
            VALUES ('EMPTY', @ItemId, @SplitConeId, @EmptyFrom, @ConeWeight, @Note, @UserId);

            SET @MovementId = CAST(SCOPE_IDENTITY() AS INT);
            SET @WeightGram = @ConeWeight;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- Bentuk result set SAMA untuk semua action (satu DTO di API).
    SELECT @MovementId  AS MovementId,
           @SplitConeId AS ThreadSplitConeId,
           @ConeCode    AS ConeCode,
           @WeightGram  AS WeightGram;
END;
GO

-- =============================================================
-- BACA: hasil scan label split `TS:<cone_code>`.
-- Bentuk result set SAMA PERSIS dengan bagian SPLIT di
-- inv.SIS_ThreadItem_GetById (DTO dipakai bersama).
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadSplitCone_GetByCode
    @ConeCode    VARCHAR(20) = NULL,
    @SplitConeId INT = NULL          -- alternatif: ambil langsung lewat id
                                     -- (halaman timbang ulang dibuka dari daftar split)
AS
BEGIN
    SET NOCOUNT ON;

    SET @ConeCode = UPPER(LTRIM(RTRIM(ISNULL(@ConeCode,''))));

    -- toleran terhadap isi QR mentah `TS:SP-000412`
    IF LEFT(@ConeCode, 3) = 'TS:' SET @ConeCode = LTRIM(SUBSTRING(@ConeCode, 4, 20));

    SELECT c.thread_split_cone_id  AS ThreadSplitConeId,
           c.cone_code             AS ConeCode,
           c.thread_item_id        AS ThreadItemId,
           c.weight_gram           AS WeightGram,
           c.[status]              AS Status,
           c.thread_location_id    AS ThreadLocationId,
           l.code                  AS LocationCode,
           c.issued_to_resource_id AS IssuedToResourceId,
           r.resource_name         AS IssuedToResourceName,
           c.issued_project_id     AS IssuedProjectId,
           p.project_name          AS IssuedProjectName,
           c.created_at            AS CreatedAt
    FROM inv.thread_split_cones c
    LEFT JOIN inv.thread_locations l ON l.thread_location_id = c.thread_location_id
    LEFT JOIN dbo.resources r        ON r.resource_id = c.issued_to_resource_id
    LEFT JOIN dbo.projects p         ON p.project_id = c.issued_project_id
    WHERE c.deleted_at IS NULL
      AND (   (@SplitConeId IS NOT NULL AND c.thread_split_cone_id = @SplitConeId)
           OR (@SplitConeId IS NULL AND @ConeCode <> '' AND c.cone_code = @ConeCode));
END;
GO

-- =============================================================
-- BACA: stok whole per rak untuk satu SKU (form Ambil & Pindah).
-- Bentuk result set SAMA dengan bagian LOKASI di SIS_ThreadItem_GetById.
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadStock_ByItem
    @ItemId     INT,
    @HanyaAda   BIT = 1        -- 1 = hanya rak yang qty > 0 (untuk form Ambil)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT l.thread_location_id AS ThreadLocationId,
           l.code               AS Code,
           l.name               AS Name,
           ISNULL(st.qty_whole, 0) AS QtyWhole,
           (SELECT COUNT(*) FROM inv.thread_split_cones c
             WHERE c.thread_item_id = @ItemId
               AND c.thread_location_id = l.thread_location_id
               AND c.deleted_at IS NULL
               AND c.[status] = 'IN_STOCK') AS SplitCount
    FROM inv.thread_locations l
    LEFT JOIN inv.thread_stocks st
           ON st.thread_location_id = l.thread_location_id
          AND st.thread_item_id = @ItemId
          AND st.deleted_at IS NULL
    WHERE l.deleted_at IS NULL
      AND (l.is_active = 1 OR ISNULL(st.qty_whole, 0) > 0)
      AND (@HanyaAda = 0 OR ISNULL(st.qty_whole, 0) > 0)
    ORDER BY l.sort_order, l.code;
END;
GO

-- =============================================================
-- BACA: movement terakhir satu SKU (tab Riwayat di detail SKU).
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadMovement_Recent
    @ItemId INT,
    @Top    INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @Top IS NULL OR @Top < 1 OR @Top > 200 SET @Top = 20;

    SELECT TOP (@Top)
           m.thread_movement_id AS MovementId,
           m.movement_type      AS MovementType,
           m.thread_item_id     AS ThreadItemId,
           c.cone_code          AS ConeCode,
           lf.code              AS FromCode,
           lt.code              AS ToCode,
           m.qty_whole          AS QtyWhole,
           m.weight_gram        AS WeightGram,
           m.resource_id        AS ResourceId,
           r.resource_name      AS ResourceName,
           m.project_id         AS ProjectId,
           p.project_name       AS ProjectName,
           m.reason_code        AS ReasonCode,
           m.note               AS Note,
           m.created_at         AS CreatedAt,
           u.FullName           AS CreatedByName
    FROM inv.thread_movements m
    LEFT JOIN inv.thread_split_cones c ON c.thread_split_cone_id = m.thread_split_cone_id
    LEFT JOIN inv.thread_locations lf  ON lf.thread_location_id = m.from_location_id
    LEFT JOIN inv.thread_locations lt  ON lt.thread_location_id = m.to_location_id
    LEFT JOIN dbo.resources r          ON r.resource_id = m.resource_id
    LEFT JOIN dbo.projects p           ON p.project_id = m.project_id
    LEFT JOIN dbo.Users u              ON u.Id = m.created_by
    WHERE m.thread_item_id = @ItemId
      AND m.deleted_at IS NULL
    ORDER BY m.created_at DESC, m.thread_movement_id DESC;
END;
GO

-- =============================================================
-- LOOKUP: line (resources) & project.
-- Tabel dbo HANYA DIBACA. Dibuat di schema inv (bukan memakai
-- SIS_Resource_Manage/SIS_Project_Manage yang paged + banyak kolom)
-- supaya dropdown module ini ringan dan bentuknya stabil.
-- =============================================================
CREATE OR ALTER PROCEDURE inv.SIS_ThreadLookup_Resources
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.resource_id   AS ResourceId,
           r.resource_name AS ResourceName,
           d.division_name AS DivisionName
    FROM dbo.resources r
    INNER JOIN dbo.divisions d ON d.division_id = r.division_id
    WHERE r.deleted_at IS NULL
      AND r.is_active = 1
      AND d.deleted_at IS NULL
    ORDER BY d.division_name, r.resource_name;
END;
GO

CREATE OR ALTER PROCEDURE inv.SIS_ThreadLookup_Projects
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.project_id   AS ProjectId,
           p.project_name AS ProjectName,
           p.no_po        AS NoPo
    FROM dbo.projects p
    WHERE p.deleted_at IS NULL
      AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED','CANCELLED')
    ORDER BY p.is_urgent DESC, p.project_id DESC;
END;
GO
