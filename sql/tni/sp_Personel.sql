-- Beranda module & halaman Personel PDH TNI AD (Prompt 63).
--
-- SELURUH status diambil dari tni.v_personel.status_progres -- JANGAN menulis
-- ulang logika CASE status di sini.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- BERANDA -- satu baris angka untuk layar 1
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Beranda_Summary
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        COUNT(*)                                                                  AS Total,
        SUM(CASE WHEN v.status_progres <> 'BELUM_CETAK' THEN 1 ELSE 0 END)         AS Dicetak,
        SUM(CASE WHEN v.status_progres IN ('SET_JADI','MASUK_BOX','TERKIRIM')
                 THEN 1 ELSE 0 END)                                               AS DapatSet,
        SUM(CASE WHEN v.status_progres IN ('MASUK_BOX','TERKIRIM') THEN 1 ELSE 0 END) AS MasukBox,
        SUM(CASE WHEN v.status_progres = 'TERKIRIM'    THEN 1 ELSE 0 END)          AS Terkirim,
        -- sudah dapat set tapi belum masuk box
        SUM(CASE WHEN v.status_progres = 'SET_JADI'    THEN 1 ELSE 0 END)          AS SetBelumBox,
        -- kartu sudah dicetak tapi belum di-scan set
        SUM(CASE WHEN v.status_progres = 'DICETAK'     THEN 1 ELSE 0 END)          AS KartuBelumScan,
        SUM(CASE WHEN v.status_data = 'PERLU_REVIEW'   THEN 1 ELSE 0 END)          AS PerluReview,
        -- tabel pembatalan sudah ada sejak Prompt 60 walau halamannya di Prompt 68
        (SELECT COUNT(*)
           FROM tni.pembatalan pb
           JOIN tni.personel p2 ON p2.personel_id = pb.personel_id AND p2.deleted_at IS NULL
          WHERE p2.order_id = @OrderId AND pb.[status] = 'MENUNGGU' AND pb.deleted_at IS NULL)
                                                                                  AS PembatalanMenunggu
    FROM tni.v_personel v
    WHERE v.order_id = @OrderId;
END;
GO

-- ============================================================
-- LIST -- paging + cari + filter
-- ============================================================
-- @Search dicocokkan ke kode_ref (AWALAN), nrp (AWALAN), atau nama (LIKE).
CREATE OR ALTER PROCEDURE tni.SIS_Personel_List
    @OrderId     INT,
    @Search      VARCHAR(150) = NULL,
    @AreaId      INT = NULL,
    @SatuanId    INT = NULL,
    @Status      VARCHAR(20) = NULL,
    @PerluReview BIT = 0,
    @PageNumber  INT = 1,
    @PageSize    INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    SET @Search = NULLIF(LTRIM(RTRIM(ISNULL(@Search, ''))), '');

    ;WITH f AS (
        SELECT v.*
        FROM tni.v_personel v
        WHERE v.order_id = @OrderId
          AND (@AreaId   IS NULL OR v.area_id   = @AreaId)
          AND (@SatuanId IS NULL OR v.satuan_id = @SatuanId)
          AND (@Status   IS NULL OR v.status_progres = @Status)
          AND (@PerluReview = 0 OR v.status_data = 'PERLU_REVIEW')
          AND (@Search IS NULL
               OR v.kode_ref LIKE @Search + '%'
               OR v.nrp      LIKE @Search + '%'
               OR v.nama     LIKE '%' + @Search + '%')
    )
    SELECT f.personel_id        AS PersonelId,
           f.kode_ref           AS KodeRef,
           f.pangkat            AS Pangkat,
           f.nama               AS Nama,
           f.nrp                AS Nrp,
           f.area_id            AS AreaId,
           f.satuan_id          AS SatuanId,
           f.satuan_code        AS SatuanCode,
           f.satuan_name        AS SatuanName,
           f.pola_kemeja_kode   AS PolaKemejaKode,
           f.pola_celana_kode   AS PolaCelanaKode,
           f.status_progres     AS StatusProgres,
           f.box_code           AS BoxCode,
           f.status_data        AS StatusData,
           COUNT(*) OVER ()     AS TotalCount
    FROM f
    ORDER BY f.kode_ref
    OFFSET (@PageNumber - 1) * @PageSize ROWS
    FETCH NEXT @PageSize ROWS ONLY;
END;
GO

-- ============================================================
-- GET BY ID -- detail lengkap
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Personel_GetById
    @Id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT v.personel_id              AS PersonelId,
           v.order_id                 AS OrderId,
           v.kode_ref                 AS KodeRef,
           v.no_urut                  AS NoUrut,
           v.qr_token                 AS QrToken,
           v.pangkat                  AS Pangkat,
           v.nama                     AS Nama,
           v.nrp                      AS Nrp,
           v.no_hp                    AS NoHp,
           v.gender                   AS Gender,
           v.tinggi_badan             AS TinggiBadan,
           v.berat_badan              AS BeratBadan,
           v.kategori                 AS Kategori,
           v.area_id                  AS AreaId,
           v.area_code                AS AreaCode,
           v.area_name                AS AreaName,
           v.satuan_id                AS SatuanId,
           v.satuan_code              AS SatuanCode,
           v.satuan_name              AS SatuanName,
           -- pola yang dipakai
           v.pola_kemeja_id           AS PolaKemejaId,
           v.pola_kemeja_kode         AS PolaKemejaKode,
           v.pola_celana_id           AS PolaCelanaId,
           v.pola_celana_kode         AS PolaCelanaKode,
           -- ukuran JADI pola kemeja (untuk perbandingan dengan ukuran badan)
           pk.lingkar_kerah           AS PolaKemejaLingkarKerah,
           pk.lebar_bahu              AS PolaKemejaLebarBahu,
           pk.lingkar_dada            AS PolaKemejaLingkarDada,
           pk.lingkar_perut           AS PolaKemejaLingkarPerut,
           pk.lingkar_pinggul         AS PolaKemejaLingkarPinggul,
           pk.panjang_baju            AS PolaKemejaPanjangBaju,
           pk.lingkar_lengan          AS PolaKemejaLingkarLengan,
           pk.lingkar_kerung_lengan   AS PolaKemejaLingkarKerungLengan,
           pk.panjang_lengan          AS PolaKemejaPanjangLengan,
           pk.lingkar_manset          AS PolaKemejaLingkarManset,
           -- ukuran JADI pola celana
           pc.lingkar_pinggang        AS PolaCelanaLingkarPinggang,
           pc.lingkar_pinggul         AS PolaCelanaLingkarPinggul,
           pc.lingkar_selangkang      AS PolaCelanaLingkarSelangkang,
           pc.lingkar_paha            AS PolaCelanaLingkarPaha,
           pc.lingkar_lutut           AS PolaCelanaLingkarLutut,
           pc.lingkar_kaki            AS PolaCelanaLingkarKaki,
           pc.panjang_celana          AS PolaCelanaPanjangCelana,
           -- 8 ukuran badan kemeja
           v.lingkar_leher            AS LingkarLeher,
           v.lebar_bahu               AS LebarBahu,
           v.lingkar_dada             AS LingkarDada,
           v.lingkar_perut            AS LingkarPerut,
           v.panjang_badan_depan      AS PanjangBadanDepan,
           v.panjang_lengan           AS PanjangLengan,
           v.lingkar_lengan           AS LingkarLengan,
           v.lingkar_ketiak           AS LingkarKetiak,
           -- 7 ukuran badan celana
           v.lingkar_pinggang_celana  AS LingkarPinggangCelana,
           v.lingkar_pinggul          AS LingkarPinggul,
           v.lingkar_pesak            AS LingkarPesak,
           v.lingkar_paha             AS LingkarPaha,
           v.lingkar_lutut            AS LingkarLutut,
           v.lingkar_celana_bawah     AS LingkarCelanaBawah,
           v.panjang_celana           AS PanjangCelana,
           -- arsip isian form
           v.size_baju_isian          AS SizeBajuIsian,
           v.size_celana_isian        AS SizeCelanaIsian,
           v.email_pengisi            AS EmailPengisi,
           v.submitted_at             AS SubmittedAt,
           -- review
           v.status_data              AS StatusData,
           v.catatan_review           AS CatatanReview,
           -- jejak alur + nama pelaku
           v.status_progres           AS StatusProgres,
           v.printed_at               AS PrintedAt,
           COALESCE(ptp.nama_petugas, up.FullName) AS PrintedByNama,
           v.print_count              AS PrintCount,
           v.set_at                   AS SetAt,
           COALESCE(pts.nama_petugas, us.FullName) AS SetByNama,
           v.boxed_at                 AS BoxedAt,
           COALESCE(ptb.nama_petugas, ub.FullName) AS BoxedByNama,
           v.box_id                   AS BoxId,
           v.box_code                 AS BoxCode,
           v.urut_dalam_box           AS UrutDalamBox,
           v.box_packed_at            AS BoxPackedAt,
           v.box_shipped_at           AS BoxShippedAt
    FROM tni.v_personel v
    JOIN tni.pola_kemeja pk ON pk.pola_kemeja_id = v.pola_kemeja_id
    JOIN tni.pola_celana pc ON pc.pola_celana_id = v.pola_celana_id
    LEFT JOIN Users up ON up.Id = v.printed_by
    LEFT JOIN Users us ON us.Id = v.set_by
    LEFT JOIN Users ub ON ub.Id = v.boxed_by
    -- Nama yang DITAMPILKAN: petugas perangkat (perangkat.nama_petugas) bila ada, baru user login.
    LEFT JOIN tni.perangkat ptp ON ptp.perangkat_id = v.printed_perangkat_id
    LEFT JOIN tni.perangkat pts ON pts.perangkat_id = v.set_perangkat_id
    LEFT JOIN tni.perangkat ptb ON ptb.perangkat_id = v.boxed_perangkat_id
    WHERE v.personel_id = @Id;
END;
GO

-- ============================================================
-- MANAGE -- UPDATE / SET_POLA / MARK_REVIEWED / DELETE
-- ============================================================
-- Satuan, kode_ref, dan qr_token TIDAK BISA diubah dari action mana pun di sini
-- (kode_ref sudah tercetak di kartu fisik, token sudah jadi isi QR).
CREATE OR ALTER PROCEDURE tni.SIS_Personel_Manage
    @Action        VARCHAR(20),
    @Id            INT,
    @Nrp           VARCHAR(30) = NULL,
    @Nama          VARCHAR(150) = NULL,
    @Pangkat       VARCHAR(50) = NULL,
    @NoHp          VARCHAR(30) = NULL,
    @Gender        VARCHAR(20) = NULL,
    @PolaKemejaId  INT = NULL,
    @PolaCelanaId  INT = NULL,
    @Catatan       VARCHAR(500) = NULL,
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OrderId INT, @SetAt DATETIME2, @PrintedAt DATETIME2, @KodeRef VARCHAR(30);

    SELECT @OrderId = order_id, @SetAt = set_at, @PrintedAt = printed_at, @KodeRef = kode_ref
    FROM tni.personel
    WHERE personel_id = @Id AND deleted_at IS NULL;

    IF @OrderId IS NULL
    BEGIN
        RAISERROR('Personel tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- ---------- UPDATE identitas ----------
    IF @Action = 'UPDATE'
    BEGIN
        SET @Nrp  = LTRIM(RTRIM(ISNULL(@Nrp, '')));
        SET @Nama = LTRIM(RTRIM(ISNULL(@Nama, '')));

        IF @Nrp = ''
        BEGIN
            RAISERROR('NRP wajib diisi.', 16, 1);
            RETURN;
        END

        IF @Nama = ''
        BEGIN
            RAISERROR('Nama wajib diisi.', 16, 1);
            RETURN;
        END

        IF @Gender NOT IN ('PRIA','WANITA_HIJAB','WANITA_NON_HIJAB')
        BEGIN
            RAISERROR('Gender harus PRIA, WANITA_HIJAB, atau WANITA_NON_HIJAB.', 16, 1);
            RETURN;
        END

        -- NRP unik di order aktif; pesan menyebut kode_ref pemiliknya.
        DECLARE @PemilikKode VARCHAR(30), @PemilikNama VARCHAR(150);

        SELECT TOP 1 @PemilikKode = kode_ref, @PemilikNama = nama
        FROM tni.personel
        WHERE order_id = @OrderId AND nrp = @Nrp AND personel_id <> @Id AND deleted_at IS NULL;

        IF @PemilikKode IS NOT NULL
        BEGIN
            RAISERROR('NRP %s sudah dipakai %s (%s).', 16, 1, @Nrp, @PemilikKode, @PemilikNama);
            RETURN;
        END

        UPDATE tni.personel
        SET nrp = @Nrp, nama = @Nama, pangkat = @Pangkat, no_hp = @NoHp, gender = @Gender,
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE personel_id = @Id AND deleted_at IS NULL;

        RETURN;
    END

    -- ---------- SET_POLA ----------
    IF @Action = 'SET_POLA'
    BEGIN
        IF @SetAt IS NOT NULL
        BEGIN
            RAISERROR('Set sudah jadi -- ajukan pembatalan set dulu.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM tni.pola_kemeja
                        WHERE pola_kemeja_id = @PolaKemejaId AND deleted_at IS NULL AND is_active = 1)
        BEGIN
            RAISERROR('Pola kemeja tidak ditemukan atau nonaktif.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM tni.pola_celana
                        WHERE pola_celana_id = @PolaCelanaId AND deleted_at IS NULL AND is_active = 1)
        BEGIN
            RAISERROR('Pola celana tidak ditemukan atau nonaktif.', 16, 1);
            RETURN;
        END

        UPDATE tni.personel
        SET pola_kemeja_id = @PolaKemejaId, pola_celana_id = @PolaCelanaId,
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE personel_id = @Id AND deleted_at IS NULL;

        RETURN;
    END

    -- ---------- MARK_REVIEWED ----------
    IF @Action = 'MARK_REVIEWED'
    BEGIN
        UPDATE tni.personel
        SET status_data = 'DIPERBAIKI',
            -- catatan baru DITAMBAHKAN, catatan import tidak dibuang
            catatan_review = LEFT(
                CONCAT(ISNULL(catatan_review + ' | ', ''),
                       'Diperbaiki ', CONVERT(VARCHAR(16), SYSDATETIME(), 120),
                       CASE WHEN NULLIF(LTRIM(RTRIM(ISNULL(@Catatan,''))),'') IS NULL
                            THEN '' ELSE CONCAT(': ', @Catatan) END), 500),
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE personel_id = @Id AND deleted_at IS NULL;

        RETURN;
    END

    -- ---------- DELETE (soft) ----------
    -- Hanya bila kartu BELUM PERNAH dicetak -- kartu fisik yang sudah keluar tidak
    -- boleh kehilangan data pemiliknya. Alasan wajib, disimpan ke catatan_review.
    IF @Action = 'DELETE'
    BEGIN
        IF @PrintedAt IS NOT NULL
        BEGIN
            RAISERROR('Kartu %s sudah pernah dicetak -- personel tidak bisa dihapus.', 16, 1, @KodeRef);
            RETURN;
        END

        IF NULLIF(LTRIM(RTRIM(ISNULL(@Catatan,''))),'') IS NULL
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        UPDATE tni.personel
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            catatan_review = LEFT(CONCAT(ISNULL(catatan_review + ' | ', ''),
                                         'Dihapus: ', @Catatan), 500)
        WHERE personel_id = @Id AND deleted_at IS NULL;

        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO

-- ============================================================
-- Pilihan filter: area + satuan order aktif
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Wilayah_List
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT a.area_id     AS AreaId,
           a.area_code   AS AreaCode,
           a.area_name   AS AreaName,
           s.satuan_id   AS SatuanId,
           s.satuan_code AS SatuanCode,
           s.satuan_name AS SatuanName
    FROM tni.area_rawatan a
    LEFT JOIN tni.satuan s ON s.area_id = a.area_id AND s.deleted_at IS NULL
    WHERE a.order_id = @OrderId AND a.deleted_at IS NULL
    ORDER BY a.area_code, s.satuan_code;
END;
GO
