-- Scan "Set Jadi" & halaman QR publik PDH TNI AD (Prompt 66).
--
-- SIS_Scan_SetJadi TIDAK memakai RAISERROR untuk kasus yang dibedakan WARNA di UI
-- (OK hijau / SUDAH kuning / TIDAK_DIKENAL merah) -- semuanya dikembalikan sebagai
-- SATU RESULT SET supaya client tidak perlu membaca pesan exception.
--
-- Stok BOLEH MINUS: setoran mungkin belum dicatat, dan scan tidak pernah diblok
-- karena stok (keputusan owner).
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- SCAN SET JADI
-- ============================================================
-- @Kode boleh qr_token ATAU kode_ref (input manual bila QR rusak).
-- @PerangkatId = perangkat pelaksana; nama petugasnya = tni.perangkat.nama_petugas (alter_75).
-- BUKAN user: created_by/set_by tetap @UserId (user sistem TNI bila tanpa login).
CREATE OR ALTER PROCEDURE tni.SIS_Scan_SetJadi
    @Kode      VARCHAR(50),
    @UserId    INT,
    @PerangkatId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                             WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

    SET @Kode = LTRIM(RTRIM(ISNULL(@Kode, '')));

    -- Cari lewat qr_token dulu, baru kode_ref.
    DECLARE @Id INT;

    SELECT TOP 1 @Id = personel_id
    FROM tni.personel
    WHERE order_id = @OrderId AND deleted_at IS NULL AND qr_token = @Kode;

    IF @Id IS NULL
        SELECT TOP 1 @Id = personel_id
        FROM tni.personel
        WHERE order_id = @OrderId AND deleted_at IS NULL AND kode_ref = @Kode;

    -- ---------- TIDAK DIKENAL ----------
    IF @Id IS NULL
    BEGIN
        SELECT 'TIDAK_DIKENAL'                              AS Hasil,
               CONCAT('Kode "', @Kode, '" tidak dikenal.')  AS Pesan,
               CAST(NULL AS INT)          AS PersonelId,
               CAST(NULL AS VARCHAR(30))  AS KodeRef,
               CAST(NULL AS VARCHAR(50))  AS Pangkat,
               CAST(NULL AS VARCHAR(150)) AS Nama,
               CAST(NULL AS VARCHAR(150)) AS SatuanName,
               CAST(NULL AS VARCHAR(30))  AS PolaKemejaKode,
               CAST(NULL AS VARCHAR(30))  AS PolaCelanaKode,
               CAST(NULL AS DATETIME2)    AS SetAt,
               CAST(NULL AS VARCHAR(150)) AS SetByNama,
               CAST(NULL AS INT)          AS SaldoKemeja,
               CAST(NULL AS INT)          AS SaldoCelana,
               -- Tiga kolom ini milik scan Masuk Box, tapi WAJIB tetap ada:
               -- TniScanHasilDto dipakai bersama oleh kedua scan, dan EF Core
               -- menolak result set yang kekurangan kolom DTO-nya.
               CAST(NULL AS VARCHAR(30))  AS BoxCode,
               CAST(NULL AS INT)          AS Isi,
               CAST(NULL AS INT)          AS Kapasitas;
        RETURN;
    END

    DECLARE @PkId INT, @PcId INT;
    SELECT @PkId = pola_kemeja_id, @PcId = pola_celana_id
    FROM tni.personel WHERE personel_id = @Id;

    DECLARE @Hasil VARCHAR(20) = 'OK';

    -- ---------- OK: catat set jadi + 2 mutasi TERPAKAI ----------
    BEGIN TRY
        BEGIN TRANSACTION;

        -- Guard scan bersamaan: hanya baris yang set_at MASIH NULL yang terupdate.
        -- @@ROWCOUNT = 0 berarti HP lain lebih dulu -> perlakukan sebagai SUDAH.
        UPDATE tni.personel
        SET set_at = SYSDATETIME(),
            set_by = @UserId,
            set_perangkat_id = @PerangkatId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE personel_id = @Id AND set_at IS NULL AND deleted_at IS NULL;

        IF @@ROWCOUNT = 0
        BEGIN
            SET @Hasil = 'SUDAH';
        END
        ELSE
        BEGIN
            -- Stok kemeja & celana berkurang 1 masing-masing.
            INSERT INTO tni.stok_mutasi
                (order_id, jenis_item, pola_kemeja_id, pola_celana_id,
                 jenis_mutasi, qty, personel_id, tanggal, created_by, perangkat_id)
            VALUES
                (@OrderId, 'KEMEJA', @PkId, NULL, 'TERPAKAI', -1, @Id, CAST(SYSDATETIME() AS DATE), @UserId, @PerangkatId),
                (@OrderId, 'CELANA', NULL, @PcId, 'TERPAKAI', -1, @Id, CAST(SYSDATETIME() AS DATE), @UserId, @PerangkatId);
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    -- ---------- hasil ----------
    SELECT @Hasil AS Hasil,
           CASE WHEN @Hasil = 'SUDAH'
                THEN CONCAT('Sudah tercatat ',
                            FORMAT(v.set_at, 'HH:mm'),
                            CASE WHEN COALESCE(pt.nama_petugas, u.FullName) IS NULL THEN ''
                                 ELSE ' oleh ' + COALESCE(pt.nama_petugas, u.FullName) END, '.')
                ELSE 'Set tercatat.'
           END                       AS Pesan,
           v.personel_id             AS PersonelId,
           v.kode_ref                AS KodeRef,
           v.pangkat                 AS Pangkat,
           v.nama                    AS Nama,
           v.satuan_name             AS SatuanName,
           v.pola_kemeja_kode        AS PolaKemejaKode,
           v.pola_celana_kode        AS PolaCelanaKode,
           v.set_at                  AS SetAt,
           -- Nama yang DITAMPILKAN: petugas perangkat bila ada, baru user login.
           COALESCE(pt.nama_petugas, u.FullName) AS SetByNama,
           -- saldo SETELAH dikurangi; boleh minus (setoran belum dicatat)
           sk.saldo                  AS SaldoKemeja,
           sc.saldo                  AS SaldoCelana,
           -- Milik scan Masuk Box; tetap disertakan karena DTO-nya satu.
           CAST(NULL AS VARCHAR(30)) AS BoxCode,
           CAST(NULL AS INT)         AS Isi,
           CAST(NULL AS INT)         AS Kapasitas
    FROM tni.v_personel v
    LEFT JOIN Users u ON u.Id = v.set_by
    LEFT JOIN tni.perangkat pt ON pt.perangkat_id = v.set_perangkat_id
    LEFT JOIN tni.v_stok_pola sk
           ON sk.order_id = v.order_id AND sk.jenis_item = 'KEMEJA' AND sk.pola_id = v.pola_kemeja_id
    LEFT JOIN tni.v_stok_pola sc
           ON sc.order_id = v.order_id AND sc.jenis_item = 'CELANA' AND sc.pola_id = v.pola_celana_id
    WHERE v.personel_id = @Id;
END;
GO

-- ============================================================
-- HALAMAN PUBLIK /t/{token} -- TANPA LOGIN
-- ============================================================
-- HANYA data terbatas -- halaman ini bisa dibuka siapa pun dari internet.
-- 2026-10-06 owner MENGIZINKAN: NRP, size (pola), TB/BB, kategori, rawatan.
-- TETAP TIDAK BOLEH: No HP dan ukuran badan.
CREATE OR ALTER PROCEDURE tni.SIS_Public_ByToken
    @Token VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT v.kode_ref        AS KodeRef,
           v.pangkat         AS Pangkat,
           v.nama            AS Nama,
           v.satuan_name     AS SatuanName,
           v.nrp             AS Nrp,
           v.pola_kemeja_kode AS PolaKemejaKode,
           v.pola_celana_kode AS PolaCelanaKode,
           v.tinggi_badan    AS TinggiBadan,
           v.berat_badan     AS BeratBadan,
           v.kategori        AS Kategori,
           v.area_name       AS AreaName,
           v.status_progres  AS StatusProgres,
           v.set_at          AS SetAt,
           v.box_code        AS BoxCode,
           v.boxed_at        AS BoxedAt,
           v.box_shipped_at  AS ShippedAt
    FROM tni.v_personel v
    WHERE v.qr_token = LTRIM(RTRIM(ISNULL(@Token, '')));
END;
GO

-- ============================================================
-- /t/{token} UNTUK USER LOGIN -- data lengkap
-- ============================================================
-- Hanya menerjemahkan token ke personel_id lalu memakai SP detail yang sudah ada,
-- supaya bentuk datanya persis sama dengan halaman detail personel.
CREATE OR ALTER PROCEDURE tni.SIS_Personel_ByToken
    @Token VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Id INT = (SELECT personel_id FROM tni.v_personel
                        WHERE qr_token = LTRIM(RTRIM(ISNULL(@Token, ''))));

    IF @Id IS NULL RETURN;

    EXEC tni.SIS_Personel_GetById @Id = @Id;
END;
GO

-- ============================================================
-- LOOKUP KARTU UNTUK POP UP KONFIRMASI SCAN (2026-10-06)
-- ============================================================
-- Permintaan owner: scan Set Jadi TIDAK langsung mencatat. Kartu dicari dulu,
-- isinya (sama dengan label yang dicetak) tampil di pop up, baru petugas
-- menekan "Sudah Set Lengkap" -> SIS_Scan_SetJadi.
--
-- @Kode boleh qr_token ATAU kode_ref, hanya di ORDER AKTIF -- aturan pencarian
-- sama persis dengan SIS_Scan_SetJadi. TIDAK mengubah data apa pun.
-- Tidak ketemu -> TIDAK ADA result set (API membalas 404 -> UI "tidak dikenal").
CREATE OR ALTER PROCEDURE tni.SIS_Scan_Lookup
    @Kode VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                             WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

    SET @Kode = LTRIM(RTRIM(ISNULL(@Kode, '')));

    DECLARE @Id INT;

    SELECT TOP 1 @Id = personel_id
    FROM tni.personel
    WHERE order_id = @OrderId AND deleted_at IS NULL AND qr_token = @Kode;

    IF @Id IS NULL
        SELECT TOP 1 @Id = personel_id
        FROM tni.personel
        WHERE order_id = @OrderId AND deleted_at IS NULL AND kode_ref = @Kode;

    IF @Id IS NULL RETURN;

    -- Bentuk data sama dengan detail personel (TniPersonelDetailDto).
    EXEC tni.SIS_Personel_GetById @Id = @Id;
END;
GO
