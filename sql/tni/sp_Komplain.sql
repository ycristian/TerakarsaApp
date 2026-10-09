-- Komplain ukuran PDH TNI AD dari halaman QR /t/{token} (2026-10-06).
--
-- CREATE dipanggil TANPA LOGIN: personel dicari lewat qr_token (bukan id/kode_ref,
-- supaya orang luar hanya bisa mengomplain kartu yang QR-nya ia pegang).
-- No telp & komentar wajib; komentar disimpan apa adanya termasuk newline.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE tni.SIS_Komplain_Manage
    @Action    VARCHAR(20),
    @Token     VARCHAR(50) = NULL,
    @NoTelp    VARCHAR(30) = NULL,
    @Komentar  NVARCHAR(2000) = NULL,
    @UserId    INT = NULL,
    @PerangkatId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Action = 'CREATE'
    BEGIN
        DECLARE @Id INT = (SELECT personel_id FROM tni.personel
                            WHERE qr_token = LTRIM(RTRIM(ISNULL(@Token, ''))) AND deleted_at IS NULL);

        IF @Id IS NULL
        BEGIN
            RAISERROR('Kartu tidak ditemukan.', 16, 1);
            RETURN;
        END

        SET @NoTelp = NULLIF(LTRIM(RTRIM(ISNULL(@NoTelp, ''))), '');
        SET @Komentar = NULLIF(LTRIM(RTRIM(ISNULL(@Komentar, N''))), N'');

        IF @NoTelp IS NULL
        BEGIN
            RAISERROR('No telp wajib diisi.', 16, 1);
            RETURN;
        END

        -- angka, spasi, +, -, minimal 8 digit
        IF @NoTelp LIKE '%[^0-9 +-]%' OR LEN(REPLACE(REPLACE(REPLACE(@NoTelp, ' ', ''), '-', ''), '+', '')) < 8
        BEGIN
            RAISERROR('No telp tidak valid.', 16, 1);
            RETURN;
        END

        IF @Komentar IS NULL
        BEGIN
            RAISERROR('Komentar wajib diisi.', 16, 1);
            RETURN;
        END

        INSERT INTO tni.komplain (personel_id, no_telp, komentar, perangkat_id, created_by)
        VALUES (@Id, @NoTelp, @Komentar, @PerangkatId, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS KomplainId;
        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO

-- Daftar komplain satu personel -- HANYA untuk perangkat terdaftar (berisi no telp).
CREATE OR ALTER PROCEDURE tni.SIS_Komplain_ByPersonel
    @PersonelId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT k.komplain_id  AS KomplainId,
           k.no_telp      AS NoTelp,
           k.komentar     AS Komentar,
           k.created_at   AS CreatedAt,
           pt.nama_petugas        AS PetugasNama
    FROM tni.komplain k
    LEFT JOIN tni.perangkat pt ON pt.perangkat_id = k.perangkat_id
    WHERE k.personel_id = @PersonelId AND k.deleted_at IS NULL
    ORDER BY k.created_at DESC;
END;
GO
