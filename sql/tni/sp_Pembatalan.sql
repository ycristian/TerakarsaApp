-- Pengajuan & persetujuan pembatalan scan PDH TNI AD (Prompt 68).
--
-- Scan TIDAK BISA dihapus langsung. Staff (module TNI_PDH) mengajukan
-- pembatalan dengan alasan; user module TNI_PDH_APPROVE memutus.
--
--   BOX -> personel keluar dari box, kembali "Dapat set". Box yang sudah
--          DITUTUP otomatis TERBUKA lagi (PDF lama tidak berlaku).
--          2026-10-07: BOX TIDAK PERLU PERSETUJUAN -- AJUKAN jenis BOX langsung
--          dieksekusi (baris pembatalan dibuat berstatus DISETUJUI sebagai jejak).
--   SET -> personel kembali "Kartu tercetak"; kemeja & celana kembali ke stok
--          lewat dua mutasi BONGKAR +1. Baris TERPAKAI TIDAK PERNAH dihapus.
--
-- Box yang sudah TERKIRIM tidak bisa dibatalkan.
-- Status personel SELALU dibaca dari tni.v_personel.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- MANAGE -- AJUKAN / SETUJUI / TOLAK
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Pembatalan_Manage
    @Action     VARCHAR(20),
    @Id         INT = NULL,
    @PersonelId INT = NULL,
    @Jenis      VARCHAR(10) = NULL,     -- SET | BOX
    @Alasan     VARCHAR(500) = NULL,
    @Catatan    VARCHAR(500) = NULL,
    @UserId     INT = NULL,
    @PerangkatId  INT = NULL      -- perangkat pengaju (nama petugas dari perangkat); pengaju sebenarnya
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ========================================================
    -- AJUKAN
    -- ========================================================
    IF @Action = 'AJUKAN'
    BEGIN
        SET @Jenis  = UPPER(LTRIM(RTRIM(ISNULL(@Jenis, ''))));
        SET @Alasan = NULLIF(LTRIM(RTRIM(ISNULL(@Alasan, ''))), '');

        IF @Jenis NOT IN ('SET','BOX')
        BEGIN
            RAISERROR('Jenis pembatalan harus SET atau BOX.', 16, 1);
            RETURN;
        END

        IF @Alasan IS NULL
        BEGIN
            RAISERROR('Alasan pembatalan wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @Status VARCHAR(20), @BoxId INT, @BoxCode VARCHAR(30),
                @Shipped DATETIME2, @KodeRef VARCHAR(30);

        SELECT @Status  = v.status_progres,
               @BoxId   = v.box_id,
               @BoxCode = v.box_code,
               @Shipped = v.box_shipped_at,
               @KodeRef = v.kode_ref
        FROM tni.v_personel v
        WHERE v.personel_id = @PersonelId;

        IF @KodeRef IS NULL
        BEGIN
            RAISERROR('Personel tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- Satu pengajuan MENUNGGU per personel per jenis. (BOX sejak 2026-10-07
        -- langsung dieksekusi, jadi tidak pernah menunggu -- lihat di bawah.)
        IF @Jenis = 'SET'
           AND EXISTS (SELECT 1 FROM tni.pembatalan
                   WHERE personel_id = @PersonelId AND jenis = @Jenis
                     AND [status] = 'MENUNGGU' AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Sudah ada pengajuan pembatalan yang menunggu persetujuan.', 16, 1);
            RETURN;
        END

        IF @Jenis = 'BOX'
        BEGIN
            IF @Status NOT IN ('MASUK_BOX','TERKIRIM')
            BEGIN
                RAISERROR('%s belum masuk box.', 16, 1, @KodeRef);
                RETURN;
            END

            IF @Shipped IS NOT NULL
            BEGIN
                RAISERROR('Box sudah terkirim, tidak bisa dibatalkan.', 16, 1);
                RETURN;
            END

            -- ----------------------------------------------------
            -- 2026-10-07 permintaan owner: KELUAR DARI BOX TIDAK PERLU
            -- PERSETUJUAN. Baris pembatalan tetap dibuat (jejak + alasan +
            -- box asal) tetapi langsung berstatus DISETUJUI dan dieksekusi
            -- sama persis dengan SETUJUI jenis BOX. Pengajuan BOX lama yang
            -- masih MENUNGGU ikut ditutup (DISETUJUI) karena sudah terwakili.
            -- ----------------------------------------------------
            DECLARE @Packed DATETIME2 = (SELECT packed_at FROM tni.box WHERE box_id = @BoxId);
            DECLARE @BoxNewId INT;

            BEGIN TRY
                BEGIN TRANSACTION;

                INSERT INTO tni.pembatalan
                    (personel_id, jenis, alasan, [status], box_id_asal,
                     diputus_oleh, diputus_at, catatan_keputusan, created_by, perangkat_id)
                VALUES (@PersonelId, 'BOX', @Alasan, 'DISETUJUI', @BoxId,
                        @UserId, SYSDATETIME(), 'Langsung -- keluar box tanpa persetujuan',
                        @UserId, @PerangkatId);

                SET @BoxNewId = CAST(SCOPE_IDENTITY() AS INT);

                UPDATE tni.pembatalan
                SET [status] = 'DISETUJUI',
                    diputus_oleh = @UserId,
                    diputus_at = SYSDATETIME(),
                    catatan_keputusan = CONCAT('Terwakili pembatalan langsung #', @BoxNewId),
                    updated_at = SYSDATETIME(),
                    updated_by = @UserId
                WHERE personel_id = @PersonelId AND jenis = 'BOX'
                  AND [status] = 'MENUNGGU' AND deleted_at IS NULL;

                -- Box tertutup dibuka lagi: PDF lama tidak berlaku.
                IF @Packed IS NOT NULL
                BEGIN
                    DECLARE @NoteLangsung VARCHAR(255) = CONCAT('Dibuka ulang karena pembatalan #', @BoxNewId);

                    UPDATE tni.box
                    SET packed_at  = NULL,
                        packed_by  = NULL,
                        packed_perangkat_id = NULL,
                        keterangan = LEFT(CASE WHEN keterangan IS NULL OR LTRIM(RTRIM(keterangan)) = ''
                                               THEN @NoteLangsung ELSE CONCAT(keterangan, '; ', @NoteLangsung) END, 255),
                        updated_at = SYSDATETIME(),
                        updated_by = @UserId
                    WHERE box_id = @BoxId;
                END

                UPDATE tni.personel
                SET box_id         = NULL,
                    urut_dalam_box = NULL,
                    boxed_at       = NULL,
                    boxed_by       = NULL,
                    boxed_perangkat_id = NULL,
                    updated_at     = SYSDATETIME(),
                    updated_by     = @UserId
                WHERE personel_id = @PersonelId;

                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
                THROW;
            END CATCH

            SELECT @BoxNewId AS PembatalanId, @KodeRef AS KodeRef, 'BOX' AS Jenis,
                   @BoxCode AS BoxCode,
                   CAST(CASE WHEN @Packed IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS BoxDibukaUlang;
            RETURN;
        END
        ELSE
        BEGIN
            -- SET: harus sudah set jadi DAN tidak lagi di box.
            IF @Status IN ('MASUK_BOX','TERKIRIM')
            BEGIN
                RAISERROR('Batalkan masuk box dulu.', 16, 1);
                RETURN;
            END

            IF @Status <> 'SET_JADI'
            BEGIN
                RAISERROR('%s belum ditandai set jadi.', 16, 1, @KodeRef);
                RETURN;
            END
        END

        INSERT INTO tni.pembatalan (personel_id, jenis, alasan, [status], box_id_asal, created_by, perangkat_id)
        VALUES (@PersonelId, @Jenis, @Alasan, 'MENUNGGU',
                CASE WHEN @Jenis = 'BOX' THEN @BoxId END, @UserId, @PerangkatId);

        DECLARE @NewId INT = CAST(SCOPE_IDENTITY() AS INT);

        SELECT @NewId AS PembatalanId, @KodeRef AS KodeRef, @Jenis AS Jenis,
               @BoxCode AS BoxCode, CAST(0 AS BIT) AS BoxDibukaUlang;
        RETURN;
    END

    -- ========================================================
    -- SETUJUI -- periksa ULANG semua kondisi (data bisa berubah
    -- sejak diajukan). Tidak valid -> tolak, status tetap MENUNGGU.
    -- ========================================================
    IF @Action = 'SETUJUI'
    BEGIN
        SET @Catatan = NULLIF(LTRIM(RTRIM(ISNULL(@Catatan, ''))), '');

        DECLARE @PJenis VARCHAR(10), @PPersonel INT, @PStatusRow VARCHAR(20);

        SELECT @PJenis = pb.jenis, @PPersonel = pb.personel_id, @PStatusRow = pb.[status]
        FROM tni.pembatalan pb
        WHERE pb.pembatalan_id = @Id AND pb.deleted_at IS NULL;

        IF @PJenis IS NULL
        BEGIN
            RAISERROR('Pengajuan pembatalan tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @PStatusRow <> 'MENUNGGU'
        BEGIN
            RAISERROR('Pengajuan ini sudah diputus.', 16, 1);
            RETURN;
        END

        DECLARE @SStatus VARCHAR(20), @SBoxId INT, @SBoxCode VARCHAR(30),
                @SShipped DATETIME2, @SPacked DATETIME2, @SKodeRef VARCHAR(30),
                @SOrderId INT, @SKemeja INT, @SCelana INT;

        SELECT @SStatus  = v.status_progres,
               @SBoxId   = v.box_id,
               @SBoxCode = v.box_code,
               @SShipped = v.box_shipped_at,
               @SPacked  = v.box_packed_at,
               @SKodeRef = v.kode_ref,
               @SOrderId = v.order_id,
               @SKemeja  = v.pola_kemeja_id,
               @SCelana  = v.pola_celana_id
        FROM tni.v_personel v
        WHERE v.personel_id = @PPersonel;

        IF @SKodeRef IS NULL
        BEGIN
            RAISERROR('Personel pengajuan ini sudah tidak ada.', 16, 1);
            RETURN;
        END

        IF @PJenis = 'BOX'
        BEGIN
            IF @SStatus NOT IN ('MASUK_BOX','TERKIRIM')
            BEGIN
                RAISERROR('%s sudah tidak ada di box -- pembatalan tidak perlu lagi.', 16, 1, @SKodeRef);
                RETURN;
            END

            IF @SShipped IS NOT NULL
            BEGIN
                RAISERROR('Box %s sudah terkirim, tidak bisa dibatalkan.', 16, 1, @SBoxCode);
                RETURN;
            END

            BEGIN TRY
                BEGIN TRANSACTION;

                -- Box tertutup dibuka lagi: PDF lama tidak berlaku.
                IF @SPacked IS NOT NULL
                BEGIN
                    DECLARE @Note VARCHAR(255) = CONCAT('Dibuka ulang karena pembatalan #', @Id);

                    UPDATE tni.box
                    SET packed_at  = NULL,
                        packed_by  = NULL,
                        keterangan = LEFT(CASE WHEN keterangan IS NULL OR LTRIM(RTRIM(keterangan)) = ''
                                               THEN @Note ELSE CONCAT(keterangan, '; ', @Note) END, 255),
                        updated_at = SYSDATETIME(),
                        updated_by = @UserId
                    WHERE box_id = @SBoxId;
                END

                UPDATE tni.personel
                SET box_id         = NULL,
                    urut_dalam_box = NULL,
                    boxed_at       = NULL,
                    boxed_by       = NULL,
                    updated_at     = SYSDATETIME(),
                    updated_by     = @UserId
                WHERE personel_id = @PPersonel;

                UPDATE tni.pembatalan
                SET [status]          = 'DISETUJUI',
                    box_id_asal       = ISNULL(box_id_asal, @SBoxId),
                    diputus_oleh      = @UserId,
                    diputus_at        = SYSDATETIME(),
                    catatan_keputusan = @Catatan,
                    updated_at        = SYSDATETIME(),
                    updated_by        = @UserId
                WHERE pembatalan_id = @Id;

                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
                THROW;
            END CATCH

            SELECT @Id AS PembatalanId, @SKodeRef AS KodeRef, 'BOX' AS Jenis,
                   @SBoxCode AS BoxCode,
                   CAST(CASE WHEN @SPacked IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS BoxDibukaUlang;
            RETURN;
        END

        -- ---- SET ----
        IF @SStatus IN ('MASUK_BOX','TERKIRIM')
        BEGIN
            RAISERROR('Batalkan masuk box dulu.', 16, 1);
            RETURN;
        END

        IF @SStatus <> 'SET_JADI'
        BEGIN
            RAISERROR('%s sudah tidak berstatus set jadi -- pembatalan tidak perlu lagi.', 16, 1, @SKodeRef);
            RETURN;
        END

        DECLARE @AlasanMutasi VARCHAR(500) = CONCAT('Pembatalan #', @Id);

        BEGIN TRY
            BEGIN TRANSACTION;

            UPDATE tni.personel
            SET set_at     = NULL,
                set_by     = NULL,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE personel_id = @PPersonel;

            -- Pengembalian stok SELALU lewat BONGKAR; TERPAKAI tidak dihapus.
            INSERT INTO tni.stok_mutasi
                (order_id, jenis_item, pola_kemeja_id, pola_celana_id,
                 jenis_mutasi, qty, alasan, personel_id, created_by)
            VALUES
                (@SOrderId, 'KEMEJA', @SKemeja, NULL, 'BONGKAR', 1, @AlasanMutasi, @PPersonel, @UserId),
                (@SOrderId, 'CELANA', NULL, @SCelana, 'BONGKAR', 1, @AlasanMutasi, @PPersonel, @UserId);

            UPDATE tni.pembatalan
            SET [status]          = 'DISETUJUI',
                diputus_oleh      = @UserId,
                diputus_at        = SYSDATETIME(),
                catatan_keputusan = @Catatan,
                updated_at        = SYSDATETIME(),
                updated_by        = @UserId
            WHERE pembatalan_id = @Id;

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        SELECT @Id AS PembatalanId, @SKodeRef AS KodeRef, 'SET' AS Jenis,
               CAST(NULL AS VARCHAR(30)) AS BoxCode,
               CAST(0 AS BIT) AS BoxDibukaUlang;
        RETURN;
    END

    -- ========================================================
    -- TOLAK -- catatan WAJIB
    -- ========================================================
    IF @Action = 'TOLAK'
    BEGIN
        SET @Catatan = NULLIF(LTRIM(RTRIM(ISNULL(@Catatan, ''))), '');

        IF @Catatan IS NULL
        BEGIN
            RAISERROR('Catatan wajib diisi saat menolak pengajuan.', 16, 1);
            RETURN;
        END

        DECLARE @TJenis VARCHAR(10), @TStatus VARCHAR(20), @TKodeRef VARCHAR(30);

        SELECT @TJenis = pb.jenis, @TStatus = pb.[status], @TKodeRef = v.kode_ref
        FROM tni.pembatalan pb
        LEFT JOIN tni.v_personel v ON v.personel_id = pb.personel_id
        WHERE pb.pembatalan_id = @Id AND pb.deleted_at IS NULL;

        IF @TJenis IS NULL
        BEGIN
            RAISERROR('Pengajuan pembatalan tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @TStatus <> 'MENUNGGU'
        BEGIN
            RAISERROR('Pengajuan ini sudah diputus.', 16, 1);
            RETURN;
        END

        UPDATE tni.pembatalan
        SET [status]          = 'DITOLAK',
            diputus_oleh      = @UserId,
            diputus_at        = SYSDATETIME(),
            catatan_keputusan = @Catatan,
            updated_at        = SYSDATETIME(),
            updated_by        = @UserId
        WHERE pembatalan_id = @Id;

        SELECT @Id AS PembatalanId, @TKodeRef AS KodeRef, @TJenis AS Jenis,
               CAST(NULL AS VARCHAR(30)) AS BoxCode,
               CAST(0 AS BIT) AS BoxDibukaUlang;
        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO

-- ============================================================
-- LIST -- MENUNGGU terlama dulu, riwayat terbaru dulu
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Pembatalan_List
    @OrderId    INT,
    @Status     VARCHAR(20) = NULL,   -- MENUNGGU | DISETUJUI | DITOLAK
    @PageNumber INT = 1,
    @PageSize   INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    SELECT pb.pembatalan_id     AS PembatalanId,
           pb.personel_id       AS PersonelId,
           pb.jenis             AS Jenis,
           pb.[status]          AS Status,
           v.kode_ref           AS KodeRef,
           v.pangkat            AS Pangkat,
           v.nama               AS Nama,
           v.satuan_code        AS SatuanCode,
           v.satuan_name        AS SatuanName,
           v.area_code          AS AreaCode,
           v.status_progres     AS StatusProgres,
           v.pola_kemeja_kode   AS PolaKemejaKode,
           v.pola_celana_kode   AS PolaCelanaKode,
           ba.box_code          AS BoxCodeAsal,
           v.box_code           AS BoxCodeSekarang,
           -- box asal masih tertutup? -> UI memperingatkan box akan terbuka lagi
           CAST(CASE WHEN ba.packed_at IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS BoxAsalTertutup,
           pb.alasan            AS Alasan,
           pb.created_at        AS DiajukanAt,
           COALESCE(ptj.nama_petugas, uc.FullName) AS DiajukanOlehNama,
           pb.diputus_at        AS DiputusAt,
           ud.FullName          AS DiputusOlehNama,
           pb.catatan_keputusan AS CatatanKeputusan,
           COUNT(*) OVER ()     AS TotalCount
    FROM tni.pembatalan pb
    JOIN tni.v_personel v   ON v.personel_id = pb.personel_id
    LEFT JOIN tni.box ba    ON ba.box_id = pb.box_id_asal
    LEFT JOIN Users uc      ON uc.Id = pb.created_by
    LEFT JOIN tni.perangkat ptj ON ptj.perangkat_id = pb.perangkat_id
    LEFT JOIN Users ud      ON ud.Id = pb.diputus_oleh
    WHERE v.order_id = @OrderId
      AND pb.deleted_at IS NULL
      AND (@Status IS NULL OR pb.[status] = @Status)
    -- MENUNGGU selalu di atas; yang menunggu terlama dulu (antre),
    -- yang sudah diputus terbaru dulu (riwayat).
    ORDER BY CASE WHEN pb.[status] = 'MENUNGGU' THEN 0 ELSE 1 END,
             CASE WHEN pb.[status] = 'MENUNGGU' THEN pb.created_at END ASC,
             pb.diputus_at DESC,
             pb.pembatalan_id DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- RIWAYAT SATU PERSONEL -- dipakai detail personel, /t/{token}, sheet scan
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Pembatalan_ByPersonel
    @PersonelId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT pb.pembatalan_id     AS PembatalanId,
           pb.personel_id       AS PersonelId,
           pb.jenis             AS Jenis,
           pb.[status]          AS Status,
           v.kode_ref           AS KodeRef,
           v.pangkat            AS Pangkat,
           v.nama               AS Nama,
           v.satuan_code        AS SatuanCode,
           v.satuan_name        AS SatuanName,
           v.area_code          AS AreaCode,
           v.status_progres     AS StatusProgres,
           v.pola_kemeja_kode   AS PolaKemejaKode,
           v.pola_celana_kode   AS PolaCelanaKode,
           ba.box_code          AS BoxCodeAsal,
           v.box_code           AS BoxCodeSekarang,
           CAST(CASE WHEN ba.packed_at IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS BoxAsalTertutup,
           pb.alasan            AS Alasan,
           pb.created_at        AS DiajukanAt,
           COALESCE(ptj.nama_petugas, uc.FullName) AS DiajukanOlehNama,
           pb.diputus_at        AS DiputusAt,
           ud.FullName          AS DiputusOlehNama,
           pb.catatan_keputusan AS CatatanKeputusan,
           0                    AS TotalCount
    FROM tni.pembatalan pb
    JOIN tni.v_personel v   ON v.personel_id = pb.personel_id
    LEFT JOIN tni.box ba    ON ba.box_id = pb.box_id_asal
    LEFT JOIN Users uc      ON uc.Id = pb.created_by
    LEFT JOIN tni.perangkat ptj ON ptj.perangkat_id = pb.perangkat_id
    LEFT JOIN Users ud      ON ud.Id = pb.diputus_oleh
    WHERE pb.personel_id = @PersonelId
      AND pb.deleted_at IS NULL
    ORDER BY pb.pembatalan_id DESC;
END;
GO
