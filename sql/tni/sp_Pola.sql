-- Master pola PDH TNI AD (Prompt 61). Pola = ukuran JADI pakaian, bukan ukuran
-- badan personel -- acuan potong untuk personel TU_SIZING yang tidak hadir
-- pengukuran.
--
-- SATU SET SP untuk KEDUA jenis pola, dibedakan @JenisItem (KEMEJA/CELANA),
-- supaya UI, API, dan DTO tidak dobel. Result set selalu berbentuk sama; kolom
-- yang tidak relevan untuk satu jenis dikembalikan NULL.
--
-- Read terpisah dari mutasi sesuai aturan CLAUDE.md:
--   read   : SIS_Pola_List / SIS_Pola_GetById
--   mutasi : SIS_Pola_Manage (@Action)
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tni.pola_* punya filtered unique index
-- (UX_tni_pola_kemeja_kode / UX_tni_pola_celana_kode).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- LIST
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Pola_List
    @JenisItem  VARCHAR(10),            -- KEMEJA | CELANA
    @OrderId    INT = NULL,             -- untuk JumlahPemakai; NULL = order aktif
    @Search     VARCHAR(50) = NULL,     -- dicocokkan ke kode ATAU kode_alt
    @HanyaAktif BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @JenisItem NOT IN ('KEMEJA','CELANA')
    BEGIN
        RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
        RETURN;
    END

    IF @OrderId IS NULL
        SELECT TOP 1 @OrderId = order_id FROM tni.orders
        WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC;

    IF @JenisItem = 'KEMEJA'
    BEGIN
        SELECT pk.pola_kemeja_id            AS PolaId,
               'KEMEJA'                     AS JenisItem,
               pk.kode                      AS Kode,
               pk.kode_alt                  AS KodeAlt,
               pk.target_gender             AS TargetGender,
               CAST(NULL AS INT)            AS SizeAngka,
               pk.lingkar_dada_acuan        AS LingkarDadaAcuan,
               pk.is_active                 AS IsActive,
               -- ukuran jadi kemeja
               pk.lingkar_kerah             AS LingkarKerah,
               pk.lebar_bahu                AS LebarBahu,
               pk.lingkar_dada              AS LingkarDada,
               pk.lingkar_perut             AS LingkarPerut,
               pk.lingkar_pinggul           AS LingkarPinggul,
               pk.panjang_baju              AS PanjangBaju,
               pk.lingkar_lengan            AS LingkarLengan,
               pk.lingkar_kerung_lengan     AS LingkarKerungLengan,
               pk.panjang_lengan            AS PanjangLengan,
               pk.lingkar_manset            AS LingkarManset,
               -- kolom celana: NULL untuk jenis ini
               CAST(NULL AS DECIMAL(5,1))   AS LingkarPinggang,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarSelangkang,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarPaha,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarLutut,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarKaki,
               CAST(NULL AS DECIMAL(5,1))   AS PanjangCelana,
               (SELECT COUNT(*) FROM tni.v_personel v
                 WHERE v.pola_kemeja_id = pk.pola_kemeja_id
                   AND (@OrderId IS NULL OR v.order_id = @OrderId)) AS JumlahPemakai
        FROM tni.pola_kemeja pk
        WHERE pk.deleted_at IS NULL
          AND (@HanyaAktif = 0 OR pk.is_active = 1)
          AND (@Search IS NULL OR @Search = ''
               OR pk.kode LIKE '%' + @Search + '%'
               OR pk.kode_alt LIKE '%' + @Search + '%')
        ORDER BY pk.lingkar_dada_acuan, pk.target_gender, pk.kode;
    END
    ELSE
    BEGIN
        SELECT pc.pola_celana_id            AS PolaId,
               'CELANA'                     AS JenisItem,
               pc.kode                      AS Kode,
               CAST(NULL AS VARCHAR(30))    AS KodeAlt,
               pc.target_gender             AS TargetGender,
               pc.size_angka                AS SizeAngka,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarDadaAcuan,
               pc.is_active                 AS IsActive,
               -- kolom kemeja: NULL untuk jenis ini
               CAST(NULL AS DECIMAL(5,1))   AS LingkarKerah,
               CAST(NULL AS DECIMAL(5,1))   AS LebarBahu,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarDada,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarPerut,
               pc.lingkar_pinggul           AS LingkarPinggul,
               CAST(NULL AS DECIMAL(5,1))   AS PanjangBaju,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarLengan,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarKerungLengan,
               CAST(NULL AS DECIMAL(5,1))   AS PanjangLengan,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarManset,
               -- ukuran jadi celana
               pc.lingkar_pinggang          AS LingkarPinggang,
               pc.lingkar_selangkang        AS LingkarSelangkang,
               pc.lingkar_paha              AS LingkarPaha,
               pc.lingkar_lutut             AS LingkarLutut,
               pc.lingkar_kaki              AS LingkarKaki,
               pc.panjang_celana            AS PanjangCelana,
               (SELECT COUNT(*) FROM tni.v_personel v
                 WHERE v.pola_celana_id = pc.pola_celana_id
                   AND (@OrderId IS NULL OR v.order_id = @OrderId)) AS JumlahPemakai
        FROM tni.pola_celana pc
        WHERE pc.deleted_at IS NULL
          AND (@HanyaAktif = 0 OR pc.is_active = 1)
          AND (@Search IS NULL OR @Search = ''
               OR pc.kode LIKE '%' + @Search + '%')
        ORDER BY pc.size_angka, pc.target_gender, pc.kode;
    END
END;
GO

-- ============================================================
-- GET BY ID -- bentuk result set sama persis dengan LIST
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Pola_GetById
    @JenisItem VARCHAR(10),
    @Id        INT,
    @OrderId   INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @JenisItem NOT IN ('KEMEJA','CELANA')
    BEGIN
        RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
        RETURN;
    END

    IF @OrderId IS NULL
        SELECT TOP 1 @OrderId = order_id FROM tni.orders
        WHERE is_active = 1 AND deleted_at IS NULL ORDER BY order_id DESC;

    IF @JenisItem = 'KEMEJA'
    BEGIN
        SELECT pk.pola_kemeja_id            AS PolaId,
               'KEMEJA'                     AS JenisItem,
               pk.kode                      AS Kode,
               pk.kode_alt                  AS KodeAlt,
               pk.target_gender             AS TargetGender,
               CAST(NULL AS INT)            AS SizeAngka,
               pk.lingkar_dada_acuan        AS LingkarDadaAcuan,
               pk.is_active                 AS IsActive,
               pk.lingkar_kerah             AS LingkarKerah,
               pk.lebar_bahu                AS LebarBahu,
               pk.lingkar_dada              AS LingkarDada,
               pk.lingkar_perut             AS LingkarPerut,
               pk.lingkar_pinggul           AS LingkarPinggul,
               pk.panjang_baju              AS PanjangBaju,
               pk.lingkar_lengan            AS LingkarLengan,
               pk.lingkar_kerung_lengan     AS LingkarKerungLengan,
               pk.panjang_lengan            AS PanjangLengan,
               pk.lingkar_manset            AS LingkarManset,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarPinggang,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarSelangkang,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarPaha,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarLutut,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarKaki,
               CAST(NULL AS DECIMAL(5,1))   AS PanjangCelana,
               (SELECT COUNT(*) FROM tni.v_personel v
                 WHERE v.pola_kemeja_id = pk.pola_kemeja_id
                   AND (@OrderId IS NULL OR v.order_id = @OrderId)) AS JumlahPemakai
        FROM tni.pola_kemeja pk
        WHERE pk.pola_kemeja_id = @Id AND pk.deleted_at IS NULL;
    END
    ELSE
    BEGIN
        SELECT pc.pola_celana_id            AS PolaId,
               'CELANA'                     AS JenisItem,
               pc.kode                      AS Kode,
               CAST(NULL AS VARCHAR(30))    AS KodeAlt,
               pc.target_gender             AS TargetGender,
               pc.size_angka                AS SizeAngka,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarDadaAcuan,
               pc.is_active                 AS IsActive,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarKerah,
               CAST(NULL AS DECIMAL(5,1))   AS LebarBahu,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarDada,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarPerut,
               pc.lingkar_pinggul           AS LingkarPinggul,
               CAST(NULL AS DECIMAL(5,1))   AS PanjangBaju,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarLengan,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarKerungLengan,
               CAST(NULL AS DECIMAL(5,1))   AS PanjangLengan,
               CAST(NULL AS DECIMAL(5,1))   AS LingkarManset,
               pc.lingkar_pinggang          AS LingkarPinggang,
               pc.lingkar_selangkang        AS LingkarSelangkang,
               pc.lingkar_paha              AS LingkarPaha,
               pc.lingkar_lutut             AS LingkarLutut,
               pc.lingkar_kaki              AS LingkarKaki,
               pc.panjang_celana            AS PanjangCelana,
               (SELECT COUNT(*) FROM tni.v_personel v
                 WHERE v.pola_celana_id = pc.pola_celana_id
                   AND (@OrderId IS NULL OR v.order_id = @OrderId)) AS JumlahPemakai
        FROM tni.pola_celana pc
        WHERE pc.pola_celana_id = @Id AND pc.deleted_at IS NULL;
    END
END;
GO

-- ============================================================
-- MANAGE -- CREATE / UPDATE / SET_AKTIF / DELETE
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Pola_Manage
    @Action              VARCHAR(20),
    @JenisItem           VARCHAR(10),
    @Id                  INT = NULL,
    @Kode                VARCHAR(30) = NULL,
    @KodeAlt             VARCHAR(30) = NULL,
    @TargetGender        VARCHAR(10) = NULL,
    @LingkarDadaAcuan    DECIMAL(5,1) = NULL,   -- wajib untuk KEMEJA
    @SizeAngka           INT = NULL,            -- wajib untuk CELANA
    @IsActive            BIT = NULL,            -- untuk SET_AKTIF
    -- ukuran jadi kemeja
    @LingkarKerah        DECIMAL(5,1) = NULL,
    @LebarBahu           DECIMAL(5,1) = NULL,
    @LingkarDada         DECIMAL(5,1) = NULL,
    @LingkarPerut        DECIMAL(5,1) = NULL,
    @LingkarPinggul      DECIMAL(5,1) = NULL,   -- dipakai kedua jenis
    @PanjangBaju         DECIMAL(5,1) = NULL,
    @LingkarLengan       DECIMAL(5,1) = NULL,
    @LingkarKerungLengan DECIMAL(5,1) = NULL,
    @PanjangLengan       DECIMAL(5,1) = NULL,
    @LingkarManset       DECIMAL(5,1) = NULL,   -- hijab saja
    -- ukuran jadi celana
    @LingkarPinggang     DECIMAL(5,1) = NULL,
    @LingkarSelangkang   DECIMAL(5,1) = NULL,
    @LingkarPaha         DECIMAL(5,1) = NULL,
    @LingkarLutut        DECIMAL(5,1) = NULL,
    @LingkarKaki         DECIMAL(5,1) = NULL,
    @PanjangCelana       DECIMAL(5,1) = NULL,
    @UserId              INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @JenisItem NOT IN ('KEMEJA','CELANA')
    BEGIN
        RAISERROR('Jenis item harus KEMEJA atau CELANA.', 16, 1);
        RETURN;
    END

    -- ---------- validasi bersama CREATE & UPDATE ----------
    IF @Action IN ('CREATE','UPDATE')
    BEGIN
        SET @Kode = LTRIM(RTRIM(@Kode));
        SET @KodeAlt = NULLIF(LTRIM(RTRIM(ISNULL(@KodeAlt,''))), '');

        IF @Kode IS NULL OR @Kode = ''
        BEGIN
            RAISERROR('Kode pola wajib diisi.', 16, 1);
            RETURN;
        END

        IF @JenisItem = 'KEMEJA'
        BEGIN
            IF @TargetGender NOT IN ('P','PG','W','W_PG','WH','WH_PG')
            BEGIN
                RAISERROR('Target gender pola kemeja harus salah satu dari P, PG, W, W_PG, WH, WH_PG.', 16, 1);
                RETURN;
            END
            IF @LingkarDadaAcuan IS NULL
            BEGIN
                RAISERROR('Lingkar dada acuan wajib diisi untuk pola kemeja.', 16, 1);
                RETURN;
            END
            -- lingkar manset hanya berlaku untuk pola hijab
            IF @TargetGender NOT IN ('WH','WH_PG') SET @LingkarManset = NULL;
        END
        ELSE
        BEGIN
            IF @TargetGender NOT IN ('P','W')
            BEGIN
                RAISERROR('Target gender pola celana harus P atau W.', 16, 1);
                RETURN;
            END
            IF @SizeAngka IS NULL
            BEGIN
                RAISERROR('Size angka wajib diisi untuk pola celana.', 16, 1);
                RETURN;
            END
        END

        -- kode unik per jenis (baris hidup)
        IF @JenisItem = 'KEMEJA'
        BEGIN
            IF EXISTS (SELECT 1 FROM tni.pola_kemeja
                        WHERE kode = @Kode AND deleted_at IS NULL
                          AND (@Action = 'CREATE' OR pola_kemeja_id <> @Id))
            BEGIN
                RAISERROR('Kode pola kemeja "%s" sudah dipakai.', 16, 1, @Kode);
                RETURN;
            END
        END
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM tni.pola_celana
                        WHERE kode = @Kode AND deleted_at IS NULL
                          AND (@Action = 'CREATE' OR pola_celana_id <> @Id))
            BEGIN
                RAISERROR('Kode pola celana "%s" sudah dipakai.', 16, 1, @Kode);
                RETURN;
            END
        END
    END

    -- ---------- CREATE ----------
    IF @Action = 'CREATE'
    BEGIN
        IF @JenisItem = 'KEMEJA'
        BEGIN
            INSERT INTO tni.pola_kemeja
                (kode, kode_alt, target_gender, lingkar_dada_acuan, lingkar_kerah, lebar_bahu,
                 lingkar_dada, lingkar_perut, lingkar_pinggul, panjang_baju, lingkar_lengan,
                 lingkar_kerung_lengan, panjang_lengan, lingkar_manset, is_active, created_by)
            VALUES
                (@Kode, @KodeAlt, @TargetGender, @LingkarDadaAcuan, @LingkarKerah, @LebarBahu,
                 @LingkarDada, @LingkarPerut, @LingkarPinggul, @PanjangBaju, @LingkarLengan,
                 @LingkarKerungLengan, @PanjangLengan, @LingkarManset, 1, @UserId);
        END
        ELSE
        BEGIN
            INSERT INTO tni.pola_celana
                (kode, target_gender, size_angka, lingkar_pinggang, lingkar_pinggul,
                 lingkar_selangkang, lingkar_paha, lingkar_lutut, lingkar_kaki,
                 panjang_celana, is_active, created_by)
            VALUES
                (@Kode, @TargetGender, @SizeAngka, @LingkarPinggang, @LingkarPinggul,
                 @LingkarSelangkang, @LingkarPaha, @LingkarLutut, @LingkarKaki,
                 @PanjangCelana, 1, @UserId);
        END

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
        RETURN;
    END

    -- ---------- UPDATE ----------
    IF @Action = 'UPDATE'
    BEGIN
        IF @JenisItem = 'KEMEJA'
        BEGIN
            UPDATE tni.pola_kemeja
            SET kode = @Kode, kode_alt = @KodeAlt, target_gender = @TargetGender,
                lingkar_dada_acuan = @LingkarDadaAcuan,
                lingkar_kerah = @LingkarKerah, lebar_bahu = @LebarBahu,
                lingkar_dada = @LingkarDada, lingkar_perut = @LingkarPerut,
                lingkar_pinggul = @LingkarPinggul, panjang_baju = @PanjangBaju,
                lingkar_lengan = @LingkarLengan, lingkar_kerung_lengan = @LingkarKerungLengan,
                panjang_lengan = @PanjangLengan, lingkar_manset = @LingkarManset,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE pola_kemeja_id = @Id AND deleted_at IS NULL;
        END
        ELSE
        BEGIN
            UPDATE tni.pola_celana
            SET kode = @Kode, target_gender = @TargetGender, size_angka = @SizeAngka,
                lingkar_pinggang = @LingkarPinggang, lingkar_pinggul = @LingkarPinggul,
                lingkar_selangkang = @LingkarSelangkang, lingkar_paha = @LingkarPaha,
                lingkar_lutut = @LingkarLutut, lingkar_kaki = @LingkarKaki,
                panjang_celana = @PanjangCelana,
                updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE pola_celana_id = @Id AND deleted_at IS NULL;
        END

        IF @@ROWCOUNT = 0 RAISERROR('Pola tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- ---------- SET_AKTIF ----------
    -- Menonaktifkan pola TIDAK mengubah personel yang sudah memakainya; pola
    -- nonaktif hanya hilang dari pilihan baru (setoran stok Prompt 64, ubah pola
    -- Prompt 63) dan ditolak saat import (Prompt 62).
    IF @Action = 'SET_AKTIF'
    BEGIN
        IF @IsActive IS NULL
        BEGIN
            RAISERROR('Status aktif wajib diisi.', 16, 1);
            RETURN;
        END

        IF @JenisItem = 'KEMEJA'
            UPDATE tni.pola_kemeja
            SET is_active = @IsActive, updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE pola_kemeja_id = @Id AND deleted_at IS NULL;
        ELSE
            UPDATE tni.pola_celana
            SET is_active = @IsActive, updated_at = SYSDATETIME(), updated_by = @UserId
            WHERE pola_celana_id = @Id AND deleted_at IS NULL;

        IF @@ROWCOUNT = 0 RAISERROR('Pola tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- ---------- DELETE (soft) ----------
    -- Ditolak bila masih dipakai personel atau sudah punya mutasi stok -- master
    -- yang sudah terpakai dinonaktifkan, bukan dihapus.
    IF @Action = 'DELETE'
    BEGIN
        DECLARE @Pemakai INT = 0, @Mutasi INT = 0;

        IF @JenisItem = 'KEMEJA'
        BEGIN
            SELECT @Pemakai = COUNT(*) FROM tni.personel
             WHERE pola_kemeja_id = @Id AND deleted_at IS NULL;
            SELECT @Mutasi = COUNT(*) FROM tni.stok_mutasi
             WHERE pola_kemeja_id = @Id AND deleted_at IS NULL;
        END
        ELSE
        BEGIN
            SELECT @Pemakai = COUNT(*) FROM tni.personel
             WHERE pola_celana_id = @Id AND deleted_at IS NULL;
            SELECT @Mutasi = COUNT(*) FROM tni.stok_mutasi
             WHERE pola_celana_id = @Id AND deleted_at IS NULL;
        END

        IF @Pemakai > 0
        BEGIN
            RAISERROR('Pola dipakai %d personel -- nonaktifkan saja.', 16, 1, @Pemakai);
            RETURN;
        END

        IF @Mutasi > 0
        BEGIN
            RAISERROR('Pola sudah punya %d mutasi stok -- nonaktifkan saja.', 16, 1, @Mutasi);
            RETURN;
        END

        IF @JenisItem = 'KEMEJA'
            UPDATE tni.pola_kemeja
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE pola_kemeja_id = @Id AND deleted_at IS NULL;
        ELSE
            UPDATE tni.pola_celana
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE pola_celana_id = @Id AND deleted_at IS NULL;

        IF @@ROWCOUNT = 0 RAISERROR('Pola tidak ditemukan.', 16, 1);
        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO
