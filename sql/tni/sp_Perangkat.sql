-- Perangkat PDH TNI AD -- otorisasi TANPA LOGIN, seperti stasiun.
--
-- Alur sama dengan stations (Prompt 20):
--   admin (login)   -> GENERATE_PAIRING, dapat kode 5 karakter, berlaku 15 menit
--   perangkat       -> CLAIM_PAIRING, menukar kode dengan perangkat_token baru
--                      (token lama MATI -- satu perangkat aktif per baris)
--   tiap request    -> header X-Tni-Token, divalidasi SIS_Perangkat_GetByToken
--
-- Kode pairing SEKALI PAKAI: satu UPDATE yang sekaligus memvalidasi dan
-- menghanguskan kode, jadi dua perangkat tidak bisa mengklaim kode yang sama.
--
-- 2026-10-06 (alter_75): TIDAK ADA tabel petugas lagi. Setiap perangkat punya
-- SATU nama petugas (tni.perangkat.nama_petugas, wajib). Jejak kerja menyimpan
-- *_perangkat_id; nama yang tampil dibaca dari perangkat. created_by tetap user
-- sistem TNI.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: tabel tni punya filtered index.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================
-- PERANGKAT -- MANAGE
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Perangkat_Manage
    @Action         VARCHAR(20),
    @Id             INT = NULL,
    @PerangkatCode  VARCHAR(30) = NULL,
    @PerangkatName  VARCHAR(150) = NULL,
    @NamaPetugas    VARCHAR(150) = NULL,  -- alter_75: SATU petugas per perangkat, wajib
    @Keterangan     VARCHAR(255) = NULL,
    @IsActive       BIT = NULL,
    @PairingCode    VARCHAR(10) = NULL,   -- digenerate API, SP hanya menyimpan
    @NewToken       VARCHAR(64) = NULL,   -- digenerate API saat klaim
    -- alter_74: menu yang DIIZINKAN, JSON array kode, mis. '["SCAN","BOX"]'.
    -- CREATE: NULL = semua menu. UPDATE: NULL = tidak diubah.
    @Menu           NVARCHAR(MAX) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- ---------- daftar menu yang diminta (CREATE / UPDATE) ----------
    DECLARE @MenuSemua TABLE (code VARCHAR(30) PRIMARY KEY);
    INSERT INTO @MenuSemua VALUES ('PERINTAH_KERJA'),('SCAN'),('BOX'),('STOK'),
                                  ('PERSONEL'),('DASHBOARD'),('IMPORT'),('POLA');

    DECLARE @MenuPilih TABLE (code VARCHAR(30) PRIMARY KEY);

    IF @Action IN ('CREATE', 'UPDATE') AND @Menu IS NOT NULL
    BEGIN
        IF ISJSON(@Menu) <> 1
        BEGIN
            RAISERROR('Daftar menu tidak valid.', 16, 1);
            RETURN;
        END

        INSERT INTO @MenuPilih (code)
        SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM OPENJSON(@Menu);

        DECLARE @MenuSalah VARCHAR(30) =
            (SELECT TOP 1 code FROM @MenuPilih WHERE code NOT IN (SELECT code FROM @MenuSemua));
        IF @MenuSalah IS NOT NULL
        BEGIN
            RAISERROR('Menu tidak dikenal: %s', 16, 1, @MenuSalah);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM @MenuPilih)
        BEGIN
            RAISERROR('Pilih minimal satu menu untuk perangkat ini.', 16, 1);
            RETURN;
        END
    END
    ELSE IF @Action = 'CREATE'
        INSERT INTO @MenuPilih SELECT code FROM @MenuSemua;   -- default: semua menu

    -- nama petugas wajib untuk CREATE & UPDATE
    SET @NamaPetugas = NULLIF(LTRIM(RTRIM(ISNULL(@NamaPetugas, ''))), '');
    IF @Action IN ('CREATE', 'UPDATE') AND @NamaPetugas IS NULL
    BEGIN
        RAISERROR('Nama petugas wajib diisi.', 16, 1);
        RETURN;
    END

    -- ========================================================
    -- CREATE
    -- ========================================================
    IF @Action = 'CREATE'
    BEGIN
        SET @PerangkatCode = NULLIF(LTRIM(RTRIM(ISNULL(@PerangkatCode, ''))), '');
        SET @PerangkatName = NULLIF(LTRIM(RTRIM(ISNULL(@PerangkatName, ''))), '');

        IF @PerangkatCode IS NULL OR @PerangkatName IS NULL
        BEGIN
            RAISERROR('Kode dan nama perangkat wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM tni.perangkat
                   WHERE perangkat_code = @PerangkatCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode perangkat %s sudah dipakai.', 16, 1, @PerangkatCode);
            RETURN;
        END

        DECLARE @Token VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        BEGIN TRAN;

        INSERT INTO tni.perangkat
            (perangkat_code, perangkat_name, nama_petugas, perangkat_token, is_active, keterangan, created_by)
        VALUES
            (@PerangkatCode, @PerangkatName, @NamaPetugas, @Token, ISNULL(@IsActive, 1), @Keterangan, @UserId);

        DECLARE @NewPerangkatId INT = CAST(SCOPE_IDENTITY() AS INT);

        INSERT INTO tni.perangkat_menu (perangkat_id, menu_code, created_by)
        SELECT @NewPerangkatId, code, @UserId FROM @MenuPilih;

        COMMIT;

        SELECT @NewPerangkatId AS PerangkatId;
        RETURN;
    END

    -- ========================================================
    -- UPDATE
    -- ========================================================
    IF @Action = 'UPDATE'
    BEGIN
        SET @PerangkatCode = NULLIF(LTRIM(RTRIM(ISNULL(@PerangkatCode, ''))), '');
        SET @PerangkatName = NULLIF(LTRIM(RTRIM(ISNULL(@PerangkatName, ''))), '');

        IF NOT EXISTS (SELECT 1 FROM tni.perangkat WHERE perangkat_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Perangkat tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @PerangkatCode IS NULL OR @PerangkatName IS NULL
        BEGIN
            RAISERROR('Kode dan nama perangkat wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM tni.perangkat
                   WHERE perangkat_code = @PerangkatCode AND perangkat_id <> @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode perangkat %s sudah dipakai.', 16, 1, @PerangkatCode);
            RETURN;
        END

        BEGIN TRAN;

        UPDATE tni.perangkat
        SET perangkat_code = @PerangkatCode,
            perangkat_name = @PerangkatName,
            nama_petugas   = @NamaPetugas,
            keterangan     = @Keterangan,
            is_active      = ISNULL(@IsActive, is_active),
            updated_at     = SYSDATETIME(),
            updated_by     = @UserId
        WHERE perangkat_id = @Id AND deleted_at IS NULL;

        -- Sinkron menu bila dikirim: yang dicabut di-soft-delete, yang baru ditambah.
        IF @Menu IS NOT NULL
        BEGIN
            UPDATE tni.perangkat_menu
            SET deleted_at = SYSDATETIME(), deleted_by = @UserId
            WHERE perangkat_id = @Id AND deleted_at IS NULL
              AND menu_code NOT IN (SELECT code FROM @MenuPilih);

            INSERT INTO tni.perangkat_menu (perangkat_id, menu_code, created_by)
            SELECT @Id, m.code, @UserId
            FROM @MenuPilih m
            WHERE NOT EXISTS (SELECT 1 FROM tni.perangkat_menu pm
                              WHERE pm.perangkat_id = @Id AND pm.menu_code = m.code
                                AND pm.deleted_at IS NULL);
        END

        COMMIT;
        RETURN;
    END

    -- ========================================================
    -- DELETE (soft)
    -- ========================================================
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM tni.perangkat WHERE perangkat_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Perangkat tidak ditemukan.', 16, 1);
            RETURN;
        END

        -- Token TIDAK dirotasi saat hapus; index unik token tanpa filter
        -- deleted_at sudah menjamin token itu tidak pernah dipakai ulang,
        -- dan GetByToken menolak baris terhapus. Baris perangkat (soft delete)
        -- tetap ada, jadi nama petugasnya tetap tampil di riwayat.
        UPDATE tni.perangkat
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            pairing_code = NULL,
            pairing_code_expires_at = NULL
        WHERE perangkat_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    -- ========================================================
    -- GENERATE_PAIRING -- kode baru menimpa kode lama (kode lama hangus)
    -- ========================================================
    IF @Action = 'GENERATE_PAIRING'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM tni.perangkat
                       WHERE perangkat_id = @Id AND deleted_at IS NULL AND is_active = 1)
        BEGIN
            RAISERROR('Perangkat tidak ditemukan atau nonaktif.', 16, 1);
            RETURN;
        END

        IF @PairingCode IS NULL
        BEGIN
            RAISERROR('Kode pairing kosong.', 16, 1);
            RETURN;
        END

        DECLARE @ExpiresAt DATETIME2 = DATEADD(MINUTE, 15, SYSDATETIME());

        UPDATE tni.perangkat
        SET pairing_code = @PairingCode,
            pairing_code_expires_at = @ExpiresAt,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE perangkat_id = @Id AND deleted_at IS NULL;

        SELECT @PairingCode AS PairingCode, @ExpiresAt AS ExpiresAt;
        RETURN;
    END

    -- ========================================================
    -- CLAIM_PAIRING -- DIPANGGIL TANPA LOGIN oleh perangkat.
    -- Satu UPDATE: validasi + hanguskan kode + rotate token, atomik.
    -- ========================================================
    IF @Action = 'CLAIM_PAIRING'
    BEGIN
        IF @PairingCode IS NULL OR @NewToken IS NULL
        BEGIN
            RAISERROR('Kode pairing tidak valid atau sudah kedaluwarsa.', 16, 1);
            RETURN;
        END

        DECLARE @Claimed TABLE (PerangkatId INT);

        UPDATE tni.perangkat
        SET perangkat_token = @NewToken,
            pairing_code = NULL,
            pairing_code_expires_at = NULL,
            paired_at = SYSDATETIME(),
            last_seen_at = SYSDATETIME(),
            updated_at = SYSDATETIME()
        OUTPUT INSERTED.perangkat_id INTO @Claimed
        WHERE pairing_code = @PairingCode
          AND pairing_code_expires_at > SYSDATETIME()
          AND is_active = 1
          AND deleted_at IS NULL;

        IF NOT EXISTS (SELECT 1 FROM @Claimed)
        BEGIN
            RAISERROR('Kode pairing tidak valid atau sudah kedaluwarsa.', 16, 1);
            RETURN;
        END

        SELECT PerangkatId FROM @Claimed;
        RETURN;
    END

    -- ========================================================
    -- UNPAIR -- token diganti GUID baru (token lama mati). Dipicu admin
    -- maupun perangkat sendiri ("Keluar").
    -- ========================================================
    IF @Action = 'UNPAIR'
    BEGIN
        DECLARE @Fresh VARCHAR(64) = LOWER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        UPDATE tni.perangkat
        SET perangkat_token = @Fresh,
            paired_at = NULL,
            pairing_code = NULL,
            pairing_code_expires_at = NULL,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE perangkat_id = @Id AND deleted_at IS NULL;
        RETURN;
    END

    RAISERROR('Action tidak dikenal: %s', 16, 1, @Action);
END;
GO

-- ============================================================
-- PERANGKAT -- baca
-- perangkat_token TIDAK PERNAH dikembalikan oleh SP daftar; hanya
-- GetByToken (yang sudah memegang token itu) dan hasil klaim.
-- ============================================================
CREATE OR ALTER PROCEDURE tni.SIS_Perangkat_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT p.perangkat_id    AS PerangkatId,
           p.perangkat_code  AS PerangkatCode,
           p.perangkat_name  AS PerangkatName,
           p.is_active       AS IsActive,
           p.keterangan      AS Keterangan,
           p.paired_at       AS PairedAt,
           p.last_seen_at    AS LastSeenAt,
           -- kode pairing hanya ditampilkan selama masih berlaku
           CASE WHEN p.pairing_code_expires_at > SYSDATETIME() THEN p.pairing_code END AS PairingCode,
           CASE WHEN p.pairing_code_expires_at > SYSDATETIME() THEN p.pairing_code_expires_at END AS PairingCodeExpiresAt,
           p.created_at      AS CreatedAt,
           p.nama_petugas    AS NamaPetugas,   -- alter_75
           -- alter_74: kode menu yang diizinkan, dipisah koma
           (SELECT STRING_AGG(pm.menu_code, ',')
              FROM tni.perangkat_menu pm
             WHERE pm.perangkat_id = p.perangkat_id AND pm.deleted_at IS NULL) AS MenuAkses
    FROM tni.perangkat p
    WHERE p.deleted_at IS NULL
    ORDER BY p.perangkat_code;
END;
GO

CREATE OR ALTER PROCEDURE tni.SIS_Perangkat_GetByToken
    @Token VARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    -- Sekaligus mencatat jejak terakhir perangkat ini dipakai.
    UPDATE tni.perangkat
    SET last_seen_at = SYSDATETIME()
    WHERE perangkat_token = @Token AND is_active = 1 AND deleted_at IS NULL;

    SELECT p.perangkat_id    AS PerangkatId,
           p.perangkat_code  AS PerangkatCode,
           p.perangkat_name  AS PerangkatName,
           p.nama_petugas    AS NamaPetugas,   -- alter_75: petugas perangkat ini
           p.paired_at       AS PairedAt,
           -- alter_74: menu yang boleh dibuka perangkat ini, dipisah koma
           (SELECT STRING_AGG(pm.menu_code, ',')
              FROM tni.perangkat_menu pm
             WHERE pm.perangkat_id = p.perangkat_id AND pm.deleted_at IS NULL) AS MenuAkses
    FROM tni.perangkat p
    WHERE p.perangkat_token = @Token
      AND p.is_active = 1
      AND p.deleted_at IS NULL;
END;
GO

