-- Box & scan "Masuk Box" PDH TNI AD (Prompt 67).
--
-- Box DIMILIKI SATUAN; sisa yang sedikit boleh digabung ke BOX GABUNGAN lintas
-- satuan dalam satu rawatan (satuan_id NULL). Isi 44-50 set, kapasitas default 50.
--
-- TIDAK ADA KOLOM STATUS: Terbuka / Tertutup / Terkirim diturunkan dari
-- packed_at dan shipped_at. Kode box TIDAK PERNAH diganti atau didaur ulang.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- MANAGE -- CREATE / CLOSE / UNCLOSE / SHIP / UNSHIP / DELETE
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Box_Manage
    @Action     VARCHAR(20),
    @BoxId      INT = NULL,
    @OrderId    INT = NULL,
    @SatuanId   INT = NULL,        -- NULL + @AreaId = box GABUNGAN
    @AreaId     INT = NULL,
    @Kapasitas  INT = NULL,
    @Alasan     VARCHAR(255) = NULL,
    @UserId     INT = NULL,
    @PerangkatId  INT = NULL      -- perangkat pelaksana (nama petugas = perangkat.nama_petugas), bukan user
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ========================================================
    -- CREATE
    -- ========================================================
    IF @Action = 'CREATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM tni.orders WHERE order_id = @OrderId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Order tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @AreaCode VARCHAR(10), @SatuanCode VARCHAR(10), @Gabungan BIT = 0;

        IF @SatuanId IS NOT NULL
        BEGIN
            -- Box SATUAN: area diturunkan dari satuan, @AreaId diabaikan.
            SELECT @AreaId = a.area_id, @AreaCode = a.area_code, @SatuanCode = s.satuan_code
            FROM tni.satuan s
            JOIN tni.area_rawatan a ON a.area_id = s.area_id AND a.deleted_at IS NULL
            WHERE s.satuan_id = @SatuanId AND s.deleted_at IS NULL AND a.order_id = @OrderId;

            IF @AreaCode IS NULL
            BEGIN
                RAISERROR('Satuan tidak ditemukan di order ini.', 16, 1);
                RETURN;
            END
        END
        ELSE
        BEGIN
            -- Box GABUNGAN: @AreaId wajib.
            SET @Gabungan = 1;

            SELECT @AreaCode = a.area_code
            FROM tni.area_rawatan a
            WHERE a.area_id = @AreaId AND a.deleted_at IS NULL AND a.order_id = @OrderId;

            IF @AreaCode IS NULL
            BEGIN
                RAISERROR('Rawatan wajib dipilih untuk box gabungan.', 16, 1);
                RETURN;
            END
        END

        IF @Kapasitas IS NULL OR @Kapasitas <= 0 SET @Kapasitas = 50;

        DECLARE @NewId INT, @NewCode VARCHAR(30), @Urut INT;

        BEGIN TRY
            BEGIN TRANSACTION;

            -- Kunci penomoran supaya dua HP tidak dapat nomor box yang sama.
            -- Kunci per satuan (box satuan) atau per area (box gabungan).
            DECLARE @Lock VARCHAR(100) = CONCAT('tni_box_urut_',
                CASE WHEN @Gabungan = 1 THEN CONCAT('area_', @AreaId) ELSE CONCAT('satuan_', @SatuanId) END);
            DECLARE @rc INT;

            EXEC @rc = sp_getapplock @Resource = @Lock, @LockMode = 'Exclusive',
                                     @LockOwner = 'Transaction', @LockTimeout = 15000;
            IF @rc < 0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR('Gagal mengunci penomoran box -- coba lagi.', 16, 1);
                RETURN;
            END

            -- NO BOX (alter_72): urut dalam ORDER -- kunci kedua per order,
            -- karena box dari satuan berbeda berebut nomor yang sama.
            DECLARE @LockOrder VARCHAR(100) = CONCAT('tni_box_no_order_', @OrderId);
            EXEC @rc = sp_getapplock @Resource = @LockOrder, @LockMode = 'Exclusive',
                                     @LockOwner = 'Transaction', @LockTimeout = 15000;
            IF @rc < 0
            BEGIN
                ROLLBACK TRANSACTION;
                RAISERROR('Gagal mengunci penomoran box -- coba lagi.', 16, 1);
                RETURN;
            END

            -- TERMASUK box terhapus: no box tidak pernah didaur ulang.
            DECLARE @BoxNo INT = (SELECT ISNULL(MAX(b.box_no), 0) + 1
                                  FROM tni.box b WHERE b.order_id = @OrderId);

            -- MAX(urut) TERMASUK box yang sudah dihapus: nomor box tidak pernah
            -- didaur ulang.
            SELECT @Urut = ISNULL(MAX(b.urut), 0) + 1
            FROM tni.box b
            WHERE b.order_id = @OrderId
              AND b.area_id = @AreaId
              AND ((@Gabungan = 1 AND b.satuan_id IS NULL)
                OR (@Gabungan = 0 AND b.satuan_id = @SatuanId));

            -- 2 digit; >= 100 dibiarkan 3 digit.
            SET @NewCode = CONCAT(@AreaCode, '-',
                                  CASE WHEN @Gabungan = 1 THEN 'GAB' ELSE @SatuanCode END, '-',
                                  CASE WHEN @Urut > 99 THEN CAST(@Urut AS VARCHAR(10))
                                       ELSE RIGHT(CONCAT('0', @Urut), 2) END);

            INSERT INTO tni.box (order_id, area_id, satuan_id, urut, box_code, box_no, kapasitas, created_by)
            VALUES (@OrderId, @AreaId, @SatuanId, @Urut, @NewCode, @BoxNo, @Kapasitas, @UserId);

            SET @NewId = CAST(SCOPE_IDENTITY() AS INT);

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH

        SELECT @NewId AS BoxId, @NewCode AS BoxCode, @Urut AS Urut, @BoxNo AS BoxNo;
        RETURN;
    END

    -- ---------- data box untuk action selain CREATE ----------
    DECLARE @PackedAt DATETIME2, @ShippedAt DATETIME2, @Code VARCHAR(30), @Isi INT;

    SELECT @PackedAt = b.packed_at, @ShippedAt = b.shipped_at, @Code = b.box_code,
           @Isi = (SELECT COUNT(*) FROM tni.personel p
                    WHERE p.box_id = b.box_id AND p.deleted_at IS NULL)
    FROM tni.box b
    WHERE b.box_id = @BoxId AND b.deleted_at IS NULL;

    IF @Code IS NULL
    BEGIN
        RAISERROR('Box tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- ========================================================
    -- CLOSE -- box ditutup, tidak bisa menerima scan lagi
    -- ========================================================
    IF @Action = 'CLOSE'
    BEGIN
        IF @ShippedAt IS NOT NULL
        BEGIN
            RAISERROR('Box %s sudah terkirim.', 16, 1, @Code);
            RETURN;
        END

        IF @PackedAt IS NOT NULL
        BEGIN
            RAISERROR('Box %s sudah ditutup.', 16, 1, @Code);
            RETURN;
        END

        IF @Isi = 0
        BEGIN
            RAISERROR('Box %s masih kosong -- tidak bisa ditutup.', 16, 1, @Code);
            RETURN;
        END

        UPDATE tni.box
        SET packed_at = SYSDATETIME(), packed_by = @UserId, packed_perangkat_id = @PerangkatId,
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE box_id = @BoxId AND deleted_at IS NULL;

        SELECT @Isi AS Isi;
        RETURN;
    END

    -- ========================================================
    -- SHIP
    -- ========================================================
    IF @Action = 'SHIP'
    BEGIN
        IF @PackedAt IS NULL
        BEGIN
            RAISERROR('Box %s belum ditutup -- tutup dulu sebelum dikirim.', 16, 1, @Code);
            RETURN;
        END

        IF @ShippedAt IS NOT NULL
        BEGIN
            RAISERROR('Box %s sudah terkirim.', 16, 1, @Code);
            RETURN;
        END

        UPDATE tni.box
        SET shipped_at = SYSDATETIME(), shipped_by = @UserId, shipped_perangkat_id = @PerangkatId,
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE box_id = @BoxId AND deleted_at IS NULL;

        SELECT @Isi AS Isi;
        RETURN;
    END

    -- ========================================================
    -- UNSHIP -- batal kirim (2026-10-06): box TERKIRIM kembali ke TERTUTUP.
    -- Langsung, tanpa persetujuan; alasan WAJIB dan dicatat di keterangan
    -- (jejak satu-satunya, karena shipped_at/by dikosongkan lagi).
    -- ========================================================
    IF @Action = 'UNSHIP'
    BEGIN
        IF @ShippedAt IS NULL
        BEGIN
            RAISERROR('Box %s belum terkirim.', 16, 1, @Code);
            RETURN;
        END

        SET @Alasan = NULLIF(LTRIM(RTRIM(ISNULL(@Alasan, ''))), '');
        IF @Alasan IS NULL
        BEGIN
            RAISERROR('Alasan batal kirim wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @Jejak VARCHAR(100) = CONCAT('Batal kirim ', FORMAT(SYSDATETIME(), 'dd/MM/yy HH:mm'),
            ISNULL(' oleh ' + (SELECT nama_petugas FROM tni.perangkat WHERE perangkat_id = @PerangkatId), ''), ': ');

        UPDATE tni.box
        SET shipped_at = NULL, shipped_by = NULL, shipped_perangkat_id = NULL,
            keterangan = LEFT(CONCAT(ISNULL(keterangan + ' | ', ''), @Jejak, @Alasan), 255),
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE box_id = @BoxId AND deleted_at IS NULL;

        SELECT @Isi AS Isi;
        RETURN;
    END

    -- ========================================================
    -- UNCLOSE -- batal tutup (2026-10-07): box TERTUTUP kembali TERBUKA
    -- (bisa menerima scan lagi; PDF lama tidak berlaku). Hanya yang BELUM
    -- terkirim -- yang sudah terkirim dibatalkan kirimnya dulu (UNSHIP).
    -- Pola sama dengan UNSHIP: langsung, alasan WAJIB, dicatat di keterangan.
    -- ========================================================
    IF @Action = 'UNCLOSE'
    BEGIN
        IF @ShippedAt IS NOT NULL
        BEGIN
            RAISERROR('Box %s sudah terkirim -- batalkan kirim dulu.', 16, 1, @Code);
            RETURN;
        END

        IF @PackedAt IS NULL
        BEGIN
            RAISERROR('Box %s belum ditutup.', 16, 1, @Code);
            RETURN;
        END

        SET @Alasan = NULLIF(LTRIM(RTRIM(ISNULL(@Alasan, ''))), '');
        IF @Alasan IS NULL
        BEGIN
            RAISERROR('Alasan batal tutup wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @JejakTutup VARCHAR(100) = CONCAT('Batal tutup ', FORMAT(SYSDATETIME(), 'dd/MM/yy HH:mm'),
            ISNULL(' oleh ' + (SELECT nama_petugas FROM tni.perangkat WHERE perangkat_id = @PerangkatId), ''), ': ');

        UPDATE tni.box
        SET packed_at = NULL, packed_by = NULL, packed_perangkat_id = NULL,
            keterangan = LEFT(CONCAT(ISNULL(keterangan + ' | ', ''), @JejakTutup, @Alasan), 255),
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE box_id = @BoxId AND deleted_at IS NULL;

        SELECT @Isi AS Isi;
        RETURN;
    END

    -- ========================================================
    -- DELETE -- hanya box KOSONG & BELUM ditutup. Nomornya tidak dipakai ulang.
    -- ========================================================
    IF @Action = 'DELETE'
    BEGIN
        IF @PackedAt IS NOT NULL OR @ShippedAt IS NOT NULL
        BEGIN
            RAISERROR('Box %s sudah ditutup -- tidak bisa dihapus.', 16, 1, @Code);
            RETURN;
        END

        IF @Isi > 0
        BEGIN
            RAISERROR('Box %s masih berisi %d set -- keluarkan dulu.', 16, 1, @Code, @Isi);
            RETURN;
        END

        UPDATE tni.box
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            keterangan = LEFT(CONCAT(ISNULL(keterangan + ' | ', ''), 'Dihapus: ',
                                     ISNULL(NULLIF(LTRIM(RTRIM(@Alasan)), ''), 'tanpa alasan')), 255)
        WHERE box_id = @BoxId AND deleted_at IS NULL;

        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO

-- ============================================================
-- SCAN MASUK BOX
-- ============================================================
-- @Kode = qr_token ATAU kode_ref (sama dengan Prompt 66).
-- Satu result set; kondisi diperiksa BERURUTAN seperti tabel di Prompt 67.
--
-- 2026-10-07: beda satuan (box satuan) / beda rawatan (box gabungan) TIDAK lagi
-- ditolak -- SP menjawab Hasil = 'KONFIRMASI' (belum menulis apa pun); UI
-- menanyakan "yakin?" lalu memanggil ulang dengan @Paksa = 1.
CREATE OR ALTER PROCEDURE tni.SIS_Scan_MasukBox
    @Kode   VARCHAR(50),
    @BoxId  INT,
    @UserId    INT,
    @PerangkatId INT = NULL,
    @Paksa BIT = 0                 -- 1 = sudah dikonfirmasi beda satuan/rawatan (2026-10-07)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                             WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

    SET @Kode = LTRIM(RTRIM(ISNULL(@Kode, '')));

    DECLARE @Id INT;

    SELECT TOP 1 @Id = personel_id FROM tni.personel
    WHERE order_id = @OrderId AND deleted_at IS NULL AND qr_token = @Kode;

    IF @Id IS NULL
        SELECT TOP 1 @Id = personel_id FROM tni.personel
        WHERE order_id = @OrderId AND deleted_at IS NULL AND kode_ref = @Kode;

    DECLARE @Hasil VARCHAR(20) = NULL, @Pesan VARCHAR(300) = NULL;

    -- ---------- 1. personel tidak ditemukan ----------
    IF @Id IS NULL
    BEGIN
        SELECT 'TIDAK_DIKENAL'                             AS Hasil,
               CONCAT('Kode "', @Kode, '" tidak dikenal.') AS Pesan,
               CAST(NULL AS INT)          AS PersonelId,
               CAST(NULL AS VARCHAR(30))  AS KodeRef,
               CAST(NULL AS VARCHAR(50))  AS Pangkat,
               CAST(NULL AS VARCHAR(150)) AS Nama,
               CAST(NULL AS VARCHAR(150)) AS SatuanName,
               CAST(NULL AS VARCHAR(30))  AS PolaKemejaKode,
               CAST(NULL AS VARCHAR(30))  AS PolaCelanaKode,
               CAST(NULL AS VARCHAR(30))  AS BoxCode,
               CAST(NULL AS INT)          AS Isi,
               CAST(NULL AS INT)          AS Kapasitas,
               -- Empat kolom ini milik scan Set Jadi, tapi WAJIB tetap ada:
               -- TniScanHasilDto dipakai bersama oleh kedua scan, dan EF Core
               -- menolak result set yang kekurangan kolom DTO-nya.
               CAST(NULL AS DATETIME2)    AS SetAt,
               CAST(NULL AS VARCHAR(150)) AS SetByNama,
               CAST(NULL AS INT)          AS SaldoKemeja,
               CAST(NULL AS INT)          AS SaldoCelana;
        RETURN;
    END

    -- ---------- data box & personel ----------
    DECLARE @BoxCode VARCHAR(30), @BoxSatuanId INT, @BoxAreaId INT,
            @BoxPacked DATETIME2, @BoxShipped DATETIME2, @Kapasitas INT, @Isi INT;

    SELECT @BoxCode = b.box_code, @BoxSatuanId = b.satuan_id, @BoxAreaId = b.area_id,
           @BoxPacked = b.packed_at, @BoxShipped = b.shipped_at, @Kapasitas = b.kapasitas,
           @Isi = (SELECT COUNT(*) FROM tni.personel p
                    WHERE p.box_id = b.box_id AND p.deleted_at IS NULL)
    FROM tni.box b
    WHERE b.box_id = @BoxId AND b.deleted_at IS NULL;

    DECLARE @PSatuanId INT, @PAreaId INT, @PSatuanName VARCHAR(150),
            @PSetAt DATETIME2, @PBoxedAt DATETIME2, @PBoxId INT, @PBoxCodeLama VARCHAR(30);

    DECLARE @PAreaCode VARCHAR(10), @BoxSatuanName VARCHAR(150), @BoxAreaCode VARCHAR(10);

    SELECT @PSatuanId = v.satuan_id, @PAreaId = v.area_id, @PSatuanName = v.satuan_name,
           @PAreaCode = v.area_code,
           @PSetAt = v.set_at, @PBoxedAt = v.boxed_at, @PBoxId = v.box_id,
           @PBoxCodeLama = v.box_code
    FROM tni.v_personel v WHERE v.personel_id = @Id;

    SELECT @BoxSatuanName = s.satuan_name FROM tni.satuan s WHERE s.satuan_id = @BoxSatuanId;
    SELECT @BoxAreaCode = a.area_code FROM tni.area_rawatan a WHERE a.area_id = @BoxAreaId;

    -- ---------- 2-9. pemeriksaan berurutan ----------
    IF @BoxCode IS NULL
        SELECT @Hasil = 'DITOLAK', @Pesan = 'Box tidak ditemukan.';
    ELSE IF @BoxPacked IS NOT NULL OR @BoxShipped IS NOT NULL
        SELECT @Hasil = 'DITOLAK', @Pesan = CONCAT('Box ', @BoxCode, ' sudah ditutup.');
    ELSE IF @PSetAt IS NULL
        SELECT @Hasil = 'DITOLAK', @Pesan = 'Belum scan Set Jadi.';
    ELSE IF @PBoxedAt IS NOT NULL AND @PBoxId = @BoxId
        SELECT @Hasil = 'SUDAH', @Pesan = CONCAT('Sudah masuk box ', @BoxCode, ' ',
                                                 FORMAT(@PBoxedAt, 'HH:mm'), '.');
    ELSE IF @PBoxedAt IS NOT NULL
        SELECT @Hasil = 'DITOLAK', @Pesan = CONCAT('Sudah di box ', @PBoxCodeLama, '.');
    ELSE IF @Isi >= @Kapasitas
        SELECT @Hasil = 'DITOLAK', @Pesan = CONCAT('Box ', @BoxCode, ' penuh (', @Isi, '/', @Kapasitas, ').');
    -- 2026-10-07: beda satuan / rawatan DIIZINKAN setelah konfirmasi (@Paksa = 1).
    ELSE IF @Paksa = 0
         AND ((@BoxSatuanId IS NOT NULL AND @BoxSatuanId <> @PSatuanId)
           OR (@BoxSatuanId IS NULL AND @BoxAreaId <> @PAreaId))
        SELECT @Hasil = 'KONFIRMASI',
               @Pesan = CONCAT('Beda ',
                               CASE WHEN @BoxAreaId <> @PAreaId THEN 'rawatan' ELSE 'satuan' END,
                               ': personel ', @PSatuanName, ' (', @PAreaCode, '), box ', @BoxCode, ' untuk ',
                               ISNULL(@BoxSatuanName, 'gabungan'), ' (', @BoxAreaCode, ').');

    -- ---------- 10. OK ----------
    IF @Hasil IS NULL
    BEGIN
        BEGIN TRY
            BEGIN TRANSACTION;

            -- Guard scan bersamaan: hanya baris yang boxed_at MASIH NULL yang terupdate.
            UPDATE p
            SET box_id = @BoxId,
                urut_dalam_box = ISNULL((SELECT MAX(x.urut_dalam_box) FROM tni.personel x
                                          WHERE x.box_id = @BoxId AND x.deleted_at IS NULL), 0) + 1,
                boxed_at = SYSDATETIME(),
                boxed_by = @UserId,
                boxed_perangkat_id = @PerangkatId,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            FROM tni.personel p
            WHERE p.personel_id = @Id AND p.boxed_at IS NULL AND p.deleted_at IS NULL;

            IF @@ROWCOUNT = 0
            BEGIN
                -- HP lain lebih dulu -- hitung ulang hasilnya.
                SELECT @PBoxId = box_id FROM tni.personel WHERE personel_id = @Id;
                IF @PBoxId = @BoxId
                    SELECT @Hasil = 'SUDAH', @Pesan = CONCAT('Sudah masuk box ', @BoxCode, '.');
                ELSE
                    SELECT @Hasil = 'DITOLAK',
                           @Pesan = CONCAT('Sudah di box ',
                                           (SELECT box_code FROM tni.box WHERE box_id = @PBoxId), '.');
            END
            ELSE
            BEGIN
                SELECT @Hasil = 'OK', @Pesan = CONCAT('Masuk box ', @BoxCode, '.');
            END

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
            THROW;
        END CATCH
    END

    -- isi dihitung SESUDAH update
    SET @Isi = (SELECT COUNT(*) FROM tni.personel WHERE box_id = @BoxId AND deleted_at IS NULL);

    SELECT @Hasil              AS Hasil,
           @Pesan              AS Pesan,
           v.personel_id       AS PersonelId,
           v.kode_ref          AS KodeRef,
           v.pangkat           AS Pangkat,
           v.nama              AS Nama,
           v.satuan_name       AS SatuanName,
           v.pola_kemeja_kode  AS PolaKemejaKode,
           v.pola_celana_kode  AS PolaCelanaKode,
           @BoxCode            AS BoxCode,
           @Isi                AS Isi,
           @Kapasitas          AS Kapasitas,
           -- Milik scan Set Jadi; tetap disertakan karena DTO-nya satu.
           -- Saldo NULL karena masuk box TIDAK mengubah stok sama sekali.
           v.set_at            AS SetAt,
           COALESCE(pts.nama_petugas, u.FullName) AS SetByNama,
           CAST(NULL AS INT)   AS SaldoKemeja,
           CAST(NULL AS INT)   AS SaldoCelana
    FROM tni.v_personel v
    LEFT JOIN Users u ON u.Id = v.set_by
    LEFT JOIN tni.perangkat pts ON pts.perangkat_id = v.set_perangkat_id
    WHERE v.personel_id = @Id;
END;
GO

-- ============================================================
-- LIST BOX -- status diturunkan dari packed_at / shipped_at
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Box_List
    @OrderId   INT,
    @AreaId    INT = NULL,
    @SatuanId  INT = NULL,
    @Status    VARCHAR(20) = NULL,   -- TERBUKA | TERTUTUP | TERKIRIM
    @Gabungan  BIT = NULL,           -- 1 = hanya box gabungan, 0 = hanya box satuan
    @Cari      VARCHAR(30) = NULL    -- angka = no box persis; selain itu potongan kode box
AS
BEGIN
    SET NOCOUNT ON;

    SET @Cari = NULLIF(LTRIM(RTRIM(ISNULL(@Cari, ''))), '');
    DECLARE @CariNo INT = TRY_CAST(@Cari AS INT);

    SELECT b.box_id       AS BoxId,
           b.box_code     AS BoxCode,
           b.box_no       AS BoxNo,
           b.area_id      AS AreaId,
           a.area_code    AS AreaCode,
           a.area_name    AS AreaName,
           b.satuan_id    AS SatuanId,
           s.satuan_code  AS SatuanCode,
           ISNULL(s.satuan_name, 'Gabungan') AS SatuanName,
           CAST(CASE WHEN b.satuan_id IS NULL THEN 1 ELSE 0 END AS BIT) AS Gabungan,
           b.urut         AS Urut,
           b.kapasitas    AS Kapasitas,
           x.Isi          AS Isi,
           x.JumlahSatuan AS JumlahSatuan,
           b.packed_at    AS PackedAt,
           COALESCE(ptp.nama_petugas, up.FullName) AS PackedByNama,
           b.shipped_at   AS ShippedAt,
           COALESCE(pth.nama_petugas, us.FullName) AS ShippedByNama,
           b.keterangan   AS Keterangan,
           -- status TURUNAN, bukan kolom
           CASE WHEN b.shipped_at IS NOT NULL THEN 'TERKIRIM'
                WHEN b.packed_at  IS NOT NULL THEN 'TERTUTUP'
                ELSE 'TERBUKA' END AS Status
    FROM tni.box b
    JOIN tni.area_rawatan a ON a.area_id = b.area_id
    LEFT JOIN tni.satuan s  ON s.satuan_id = b.satuan_id
    LEFT JOIN Users up ON up.Id = b.packed_by
    LEFT JOIN Users us ON us.Id = b.shipped_by
    LEFT JOIN tni.perangkat ptp ON ptp.perangkat_id = b.packed_perangkat_id
    LEFT JOIN tni.perangkat pth ON pth.perangkat_id = b.shipped_perangkat_id
    CROSS APPLY (
        SELECT COUNT(*) AS Isi, COUNT(DISTINCT p.satuan_id) AS JumlahSatuan
        FROM tni.personel p
        WHERE p.box_id = b.box_id AND p.deleted_at IS NULL
    ) x
    WHERE b.order_id = @OrderId
      AND b.deleted_at IS NULL
      AND (@AreaId   IS NULL OR b.area_id = @AreaId)
      AND (@SatuanId IS NULL OR b.satuan_id = @SatuanId)
      AND (@Gabungan IS NULL
           OR (@Gabungan = 1 AND b.satuan_id IS NULL)
           OR (@Gabungan = 0 AND b.satuan_id IS NOT NULL))
      AND (@Status IS NULL
           OR (@Status = 'TERKIRIM' AND b.shipped_at IS NOT NULL)
           OR (@Status = 'TERTUTUP' AND b.packed_at IS NOT NULL AND b.shipped_at IS NULL)
           OR (@Status = 'TERBUKA'  AND b.packed_at IS NULL))
      AND (@Cari IS NULL
           OR b.box_no = @CariNo
           OR b.box_code LIKE '%' + @Cari + '%')
    ORDER BY a.area_code, ISNULL(s.satuan_code, 'ZZZ'), b.urut;
END;
GO

-- ============================================================
-- DETAIL BOX -- 3 result set: header, isi, rekap pola
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Box_GetById
    @BoxId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- (1) header
    SELECT b.box_id       AS BoxId,
           b.box_code     AS BoxCode,
           b.box_no       AS BoxNo,
           b.order_id     AS OrderId,
           o.order_name   AS OrderName,
           o.instansi     AS Instansi,
           b.area_id      AS AreaId,
           a.area_code    AS AreaCode,
           a.area_name    AS AreaName,
           b.satuan_id    AS SatuanId,
           s.satuan_code  AS SatuanCode,
           ISNULL(s.satuan_name, 'Gabungan') AS SatuanName,
           CAST(CASE WHEN b.satuan_id IS NULL THEN 1 ELSE 0 END AS BIT) AS Gabungan,
           b.kapasitas    AS Kapasitas,
           x.Isi          AS Isi,
           x.JumlahSatuan AS JumlahSatuan,
           b.packed_at    AS PackedAt,
           COALESCE(ptp.nama_petugas, up.FullName) AS PackedByNama,
           b.shipped_at   AS ShippedAt,
           COALESCE(pth.nama_petugas, us.FullName) AS ShippedByNama,
           b.keterangan   AS Keterangan,
           CASE WHEN b.shipped_at IS NOT NULL THEN 'TERKIRIM'
                WHEN b.packed_at  IS NOT NULL THEN 'TERTUTUP'
                ELSE 'TERBUKA' END AS Status
    FROM tni.box b
    JOIN tni.orders o       ON o.order_id = b.order_id
    JOIN tni.area_rawatan a ON a.area_id = b.area_id
    LEFT JOIN tni.satuan s  ON s.satuan_id = b.satuan_id
    LEFT JOIN Users up ON up.Id = b.packed_by
    LEFT JOIN Users us ON us.Id = b.shipped_by
    LEFT JOIN tni.perangkat ptp ON ptp.perangkat_id = b.packed_perangkat_id
    LEFT JOIN tni.perangkat pth ON pth.perangkat_id = b.shipped_perangkat_id
    CROSS APPLY (
        SELECT COUNT(*) AS Isi, COUNT(DISTINCT p.satuan_id) AS JumlahSatuan
        FROM tni.personel p
        WHERE p.box_id = b.box_id AND p.deleted_at IS NULL
    ) x
    WHERE b.box_id = @BoxId AND b.deleted_at IS NULL;

    -- (2) isi box, urut urut_dalam_box
    SELECT v.personel_id      AS PersonelId,
           v.urut_dalam_box   AS UrutDalamBox,
           v.kode_ref         AS KodeRef,
           v.pangkat          AS Pangkat,
           v.nama             AS Nama,
           v.nrp              AS Nrp,
           v.satuan_code      AS SatuanCode,
           v.satuan_name      AS SatuanName,
           v.pola_kemeja_kode AS PolaKemejaKode,
           v.pola_celana_kode AS PolaCelanaKode,
           v.boxed_at         AS BoxedAt,
           -- 2026-10-07: rawatan per personel -- box bisa berisi rawatan lain
           -- (masuk box beda satuan/rawatan setelah konfirmasi)
           v.area_code        AS AreaCode,
           v.area_name        AS AreaName
    FROM tni.v_personel v
    WHERE v.box_id = @BoxId
    ORDER BY v.urut_dalam_box;

    -- (3) rekap jumlah per pola kemeja & per pola celana
    SELECT 'KEMEJA' AS JenisItem, v.pola_kemeja_kode AS Kode, COUNT(*) AS Jumlah
    FROM tni.v_personel v
    WHERE v.box_id = @BoxId
    GROUP BY v.pola_kemeja_kode
    UNION ALL
    SELECT 'CELANA', v.pola_celana_kode, COUNT(*)
    FROM tni.v_personel v
    WHERE v.box_id = @BoxId
    GROUP BY v.pola_celana_kode
    ORDER BY JenisItem DESC, Kode;
END;
GO

-- ============================================================
-- Box TERBUKA untuk pilihan di layar scan
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Box_Terbuka
    @OrderId  INT,
    @AreaId   INT = NULL,
    @SatuanId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    EXEC tni.SIS_Box_List @OrderId = @OrderId, @AreaId = @AreaId,
                          @SatuanId = @SatuanId, @Status = 'TERBUKA';
END;
GO
