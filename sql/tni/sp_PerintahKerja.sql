-- Perintah Kerja & cetak kartu personel PDH TNI AD (Prompt 65).
--
-- SP ini HANYA menyediakan DATA MENTAH untuk saran prioritas. Algoritma greedy
-- "bisa dibuat" dihitung di API (TniPerintahKerjaService), BUKAN di SQL --
-- sifatnya saran, bukan validasi, dan supaya mudah diubah tanpa alter SP.
--
-- Cetak TIDAK MENGUNCI stok dan TIDAK membuat mutasi stok apa pun. Mutasi
-- TERPAKAI baru lahir saat scan Set Jadi (Prompt 66).
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- DATA -- 3 result set: kandidat + stok bebas kemeja + stok bebas celana
-- ============================================================
-- Kandidat = personel order aktif berstatus BELUM_CETAK.
CREATE OR ALTER PROCEDURE tni.SIS_PerintahKerja_Data
    @OrderId  INT,
    @AreaId   INT = NULL,
    @SatuanId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- (1) kandidat, urut kode_ref (urutan yang dipakai greedy di API)
    SELECT v.personel_id      AS PersonelId,
           v.kode_ref         AS KodeRef,
           v.pangkat          AS Pangkat,
           v.nama             AS Nama,
           v.area_id          AS AreaId,
           v.area_code        AS AreaCode,
           v.area_name        AS AreaName,
           v.satuan_id        AS SatuanId,
           v.satuan_code      AS SatuanCode,
           v.satuan_name      AS SatuanName,
           v.pola_kemeja_id   AS PolaKemejaId,
           v.pola_kemeja_kode AS PolaKemejaKode,
           v.pola_celana_id   AS PolaCelanaId,
           v.pola_celana_kode AS PolaCelanaKode
    FROM tni.v_personel v
    WHERE v.order_id = @OrderId
      AND v.status_progres = 'BELUM_CETAK'
      AND (@AreaId   IS NULL OR v.area_id   = @AreaId)
      AND (@SatuanId IS NULL OR v.satuan_id = @SatuanId)
    ORDER BY v.satuan_code, v.kode_ref;

    -- (2) stok bebas kemeja per pola
    SELECT s.pola_id   AS PolaId,
           s.kode      AS Kode,
           s.stok_bebas AS StokBebas,
           s.saldo     AS Saldo
    FROM tni.v_stok_pola s
    WHERE s.order_id = @OrderId AND s.jenis_item = 'KEMEJA';

    -- (3) stok bebas celana per pola
    SELECT s.pola_id   AS PolaId,
           s.kode      AS Kode,
           s.stok_bebas AS StokBebas,
           s.saldo     AS Saldo
    FROM tni.v_stok_pola s
    WHERE s.order_id = @OrderId AND s.jenis_item = 'CELANA';
END;
GO

-- ============================================================
-- DIJATAH -- kartu sudah tercetak tapi belum di-scan Set Jadi
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_PerintahKerja_Dijatah
    @OrderId  INT,
    @SatuanId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT v.personel_id      AS PersonelId,
           v.kode_ref         AS KodeRef,
           v.pangkat          AS Pangkat,
           v.nama             AS Nama,
           v.pola_kemeja_kode AS PolaKemejaKode,
           v.pola_celana_kode AS PolaCelanaKode,
           v.printed_at       AS PrintedAt,
           v.print_count      AS PrintCount,
           COALESCE(ptc.nama_petugas, u.FullName) AS PrintedByNama
    FROM tni.v_personel v
    LEFT JOIN Users u ON u.Id = v.printed_by
    LEFT JOIN tni.perangkat ptc ON ptc.perangkat_id = v.printed_perangkat_id
    WHERE v.order_id = @OrderId
      AND v.satuan_id = @SatuanId
      AND v.status_progres = 'DICETAK'
    ORDER BY v.kode_ref;
END;
GO

-- ============================================================
-- CETAK -- buat print job + tandai printed_at
-- ============================================================
-- Berlaku untuk personel berstatus APA PUN (dipakai juga untuk cetak ulang).
-- Satu transaksi, urut kode_ref.
-- payload dirakit dengan FOR JSON PATH, bentuknya TniKartuPayload.
CREATE OR ALTER PROCEDURE tni.SIS_Personel_Cetak
    @PersonelIds NVARCHAR(MAX),      -- JSON array id, mis. '[1,2,3]'
    @QrBaseUrl   VARCHAR(200),
    @UserId      INT,
    @PerangkatId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PersonelIds IS NULL OR ISJSON(@PersonelIds) <> 1
    BEGIN
        RAISERROR('Daftar personel tidak valid.', 16, 1);
        RETURN;
    END

    SELECT DISTINCT TRY_CAST(value AS INT) AS personel_id
    INTO #ids
    FROM OPENJSON(@PersonelIds)
    WHERE TRY_CAST(value AS INT) IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM #ids)
    BEGIN
        RAISERROR('Tidak ada personel yang dipilih.', 16, 1);
        RETURN;
    END

    -- Hanya personel HIDUP di order AKTIF.
    DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                             WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

    DECLARE @Judul VARCHAR(200) = (
        SELECT UPPER(CONCAT(o.order_name, CASE WHEN o.instansi IS NULL THEN '' ELSE ' - ' + o.instansi END))
        FROM tni.orders o WHERE o.order_id = @OrderId);

    DECLARE @N INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Daftar yang benar-benar akan dicetak, urut kode_ref.
        SELECT v.personel_id, v.kode_ref
        INTO #cetak
        FROM tni.v_personel v
        JOIN #ids i ON i.personel_id = v.personel_id
        WHERE v.order_id = @OrderId;

        INSERT INTO dbo.print_jobs (job_type, ref_id, payload, created_by)
        SELECT 'TNI_KARTU',
               v.personel_id,
               (
                   SELECT v.kode_ref                        AS kodeRef,
                          @Judul                            AS judulOrder,
                          v.satuan_name                     AS satuanName,
                          v.area_name                       AS areaName,
                          v.pangkat                         AS pangkat,
                          v.nama                            AS nama,
                          v.nrp                             AS nrp,
                          v.no_hp                           AS noHp,
                          v.tinggi_badan                    AS tinggiBadan,
                          v.berat_badan                     AS beratBadan,
                          v.pola_kemeja_kode                AS polaKemeja,
                          v.pola_celana_kode                AS polaCelana,
                          v.kategori                        AS kategori,
                          CONCAT(@QrBaseUrl, '/t/', v.qr_token) AS qrContent,
                          -- 8 ukuran badan kemeja, urutan seperti di kartu
                          (SELECT k.label, k.nilai
                             FROM (VALUES
                                ('Lingkar Leher',       v.lingkar_leher),
                                ('Lebar Bahu',          v.lebar_bahu),
                                ('Lingkar Dada',        v.lingkar_dada),
                                ('Lingkar Perut',       v.lingkar_perut),
                                ('Panjang Badan Depan', v.panjang_badan_depan),
                                ('Panjang Lengan',      v.panjang_lengan),
                                ('Lingkar Lengan',      v.lingkar_lengan),
                                ('Lingkar Ketiak',      v.lingkar_ketiak)
                             ) k(label, nilai)
                             FOR JSON PATH)              AS ukuranKemeja,
                          -- 7 ukuran badan celana
                          (SELECT c.label, c.nilai
                             FROM (VALUES
                                ('Lingkar Pinggang',     v.lingkar_pinggang_celana),
                                ('Lingkar Pinggul',      v.lingkar_pinggul),
                                ('Lingkar Pesak',        v.lingkar_pesak),
                                ('Lingkar Paha',         v.lingkar_paha),
                                ('Lingkar Lutut',        v.lingkar_lutut),
                                ('Lingkar Celana Bawah', v.lingkar_celana_bawah),
                                ('Panjang Celana',       v.panjang_celana)
                             ) c(label, nilai)
                             FOR JSON PATH)              AS ukuranCelana
                   FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
               ),
               @UserId
        FROM tni.v_personel v
        JOIN #cetak c ON c.personel_id = v.personel_id
        ORDER BY v.kode_ref;

        SET @N = @@ROWCOUNT;

        -- Tandai sudah dicetak. print_count naik tiap kali dicetak (termasuk ulang).
        UPDATE p
        SET printed_at  = SYSDATETIME(),
            printed_by  = @UserId,
            printed_perangkat_id = @PerangkatId,
            print_count = p.print_count + 1,
            updated_at  = SYSDATETIME(),
            updated_by  = @UserId
        FROM tni.personel p
        JOIN #cetak c ON c.personel_id = p.personel_id
        WHERE p.deleted_at IS NULL;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH

    SELECT @N AS JumlahJob;
END;
GO

-- ============================================================
-- LEPAS CETAK -- kartu fisik batal dikerjakan sekarang
-- ============================================================
-- Mengembalikan personel ke BELUM_CETAK supaya stok bebasnya kembali.
-- HANYA untuk yang belum Set Jadi; yang sudah set dilewati dan dilaporkan.
-- print_count SENGAJA tidak dikurangi (jejak berapa kali kartu pernah keluar).
CREATE OR ALTER PROCEDURE tni.SIS_Personel_LepasCetak
    @PersonelIds NVARCHAR(MAX),
    @UserId      INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PersonelIds IS NULL OR ISJSON(@PersonelIds) <> 1
    BEGIN
        RAISERROR('Daftar personel tidak valid.', 16, 1);
        RETURN;
    END

    SELECT DISTINCT TRY_CAST(value AS INT) AS personel_id
    INTO #ids
    FROM OPENJSON(@PersonelIds)
    WHERE TRY_CAST(value AS INT) IS NOT NULL;

    DECLARE @OrderId INT = (SELECT TOP 1 order_id FROM tni.orders
                             WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC);

    -- yang dilewati karena sudah Set Jadi
    DECLARE @Dilewati NVARCHAR(MAX) =
        (SELECT STRING_AGG(v.kode_ref, ', ') WITHIN GROUP (ORDER BY v.kode_ref)
         FROM tni.v_personel v
         JOIN #ids i ON i.personel_id = v.personel_id
         WHERE v.order_id = @OrderId AND v.set_at IS NOT NULL);

    UPDATE p
    SET printed_at = NULL,
        printed_by = NULL,
        updated_at = SYSDATETIME(),
        updated_by = @UserId
    FROM tni.personel p
    JOIN #ids i ON i.personel_id = p.personel_id
    WHERE p.order_id = @OrderId
      AND p.deleted_at IS NULL
      AND p.set_at IS NULL
      AND p.printed_at IS NOT NULL;

    SELECT @@ROWCOUNT AS JumlahDilepas,
           @Dilewati  AS DilewatiKodeRef;
END;
GO
