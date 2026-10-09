-- Prompt 70 -- Mutasi employee_cards (CREATE/UPDATE/DEACTIVATE/DELETE) dari admin panel
-- (module HR_ATTENDANCE tab "Kartu Karyawan"). Pendaftaran kartu dari perangkat gate memakai
-- SIS_Gate_RegisterCard (sp_Gate.sql) -- validasi UID-nya memanggil helper yang sama di bawah.
-- Pengambilan data ada di sp_EmployeeCard_Select.sql.
--
-- DEACTIVATE vs DELETE:
--   DEACTIVATE = card_status 'NONAKTIF', BUKAN soft delete. Ini jalur normal untuk kartu
--                hilang/diganti -- barisnya tetap ada sebagai riwayat dan UID-nya bebas
--                didaftarkan lagi (filtered unique index hanya menjaga baris AKTIF).
--   DELETE     = soft delete, HANYA untuk salah input.
--
-- Satu karyawan boleh punya beberapa kartu AKTIF sekaligus (kartu tetap + kartu sementara) --
-- disengaja, tidak dikunci di mana pun.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Normalisasi + validasi UID kartu. Reader USB mengeluarkan 10 digit desimal, tapi nol di
-- depan kadang hilang di perjalanan (dibaca sebagai angka), jadi UID di-pad nol sampai 10
-- digit sebelum disimpan/dibandingkan. Dipakai SIS_EmployeeCard_Manage dan SIS_Gate_RegisterCard.
CREATE OR ALTER PROCEDURE SIS_EmployeeCard_NormalizeUid
    @CardUid     VARCHAR(20),
    @Normalized  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @Normalized = NULL;
    DECLARE @Raw VARCHAR(20) = LTRIM(RTRIM(ISNULL(@CardUid, '')));

    IF @Raw = ''
    BEGIN
        RAISERROR('UID kartu wajib diisi.', 16, 1);
        RETURN;
    END

    IF PATINDEX('%[^0-9]%', @Raw) > 0
    BEGIN
        RAISERROR('UID kartu harus berupa angka saja (10 digit desimal dari reader).', 16, 1);
        RETURN;
    END

    IF LEN(@Raw) > 10
    BEGIN
        RAISERROR('UID kartu maksimal 10 digit, yang terbaca "%s".', 16, 1, @Raw);
        RETURN;
    END

    SET @Normalized = RIGHT('0000000000' + @Raw, 10);
END;
GO

-- Pemilik AKTIF dari sebuah UID, sebagai label siap-tampil ("Nama (KODE)"), atau NULL kalau
-- UID masih bebas. SENGAJA tidak RAISERROR sendiri: RAISERROR severity 16 di procedure
-- bersarang TIDAK menghentikan procedure pemanggil, jadi keputusan gagal/lanjut harus ada di
-- pemanggil. Pesan penolakan menyebut NAMA pemilik supaya satpam/admin bisa menelusuri kartu
-- lamanya, bukan cuma tahu "sudah dipakai".
-- Dipakai SIS_EmployeeCard_Manage dan SIS_Gate_RegisterCard.
CREATE OR ALTER PROCEDURE SIS_EmployeeCard_GetUidOwner
    @CardUid       VARCHAR(20),       -- sudah dinormalisasi
    @ExceptCardId  INT = NULL,        -- kartu yang sedang diedit (jangan dibandingkan dgn dirinya)
    @OwnerLabel    VARCHAR(200) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @OwnerLabel = NULL;

    SELECT TOP 1 @OwnerLabel = e.employee_name + ISNULL(' (' + e.employee_code + ')', '')
    FROM employee_cards ec
    INNER JOIN employees e ON e.employee_id = ec.employee_id
    WHERE ec.card_uid = @CardUid
      AND ec.card_status = 'AKTIF'
      AND ec.deleted_at IS NULL
      AND (@ExceptCardId IS NULL OR ec.employee_card_id <> @ExceptCardId);
END;
GO

CREATE OR ALTER PROCEDURE SIS_EmployeeCard_Manage
    @Action      VARCHAR(20),
    @Id          INT = NULL,
    @EmployeeId  INT = NULL,
    @CardUid     VARCHAR(20) = NULL,
    @CardType    VARCHAR(20) = NULL,       -- TETAP / SEMENTARA
    @Remarks     VARCHAR(255) = NULL,
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(ISNULL(@Remarks, ''))), '');

    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        IF @CardType NOT IN ('TETAP', 'SEMENTARA')
        BEGIN
            RAISERROR('Jenis kartu harus TETAP atau SEMENTARA.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = @EmployeeId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Karyawan tidak ditemukan.', 16, 1);
            RETURN;
        END

        DECLARE @Uid VARCHAR(20);
        EXEC SIS_EmployeeCard_NormalizeUid @CardUid = @CardUid, @Normalized = @Uid OUTPUT;
        IF @Uid IS NULL RETURN;   -- helper sudah RAISERROR
    END

    DECLARE @OwnerLabel VARCHAR(200) = NULL;

    IF @Action = 'CREATE'
    BEGIN
        EXEC SIS_EmployeeCard_GetUidOwner @CardUid = @Uid, @OwnerLabel = @OwnerLabel OUTPUT;
        IF @OwnerLabel IS NOT NULL
        BEGIN
            RAISERROR('Kartu %s sudah aktif untuk %s. Nonaktifkan kartu lamanya dulu.', 16, 1, @Uid, @OwnerLabel);
            RETURN;
        END

        INSERT INTO employee_cards
            (employee_id, card_uid, card_type, card_status, issued_at, issued_by_employee_id, remarks, created_at, created_by)
        VALUES
            (@EmployeeId, @Uid, @CardType, 'AKTIF', SYSDATETIME(), NULL, @Remarks, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM employee_cards WHERE employee_card_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kartu tidak ditemukan.', 16, 1);
            RETURN;
        END

        EXEC SIS_EmployeeCard_GetUidOwner @CardUid = @Uid, @ExceptCardId = @Id, @OwnerLabel = @OwnerLabel OUTPUT;
        IF @OwnerLabel IS NOT NULL
        BEGIN
            RAISERROR('Kartu %s sudah aktif untuk %s. Nonaktifkan kartu lamanya dulu.', 16, 1, @Uid, @OwnerLabel);
            RETURN;
        END

        UPDATE employee_cards
        SET employee_id = @EmployeeId,
            card_uid    = @Uid,
            card_type   = @CardType,
            remarks     = @Remarks,
            updated_at  = SYSDATETIME(),
            updated_by  = @UserId
        WHERE employee_card_id = @Id AND deleted_at IS NULL;
    END

    -- Jalur normal kartu hilang/diganti: riwayat tetap utuh, UID bebas dipakai kartu baru.
    ELSE IF @Action = 'DEACTIVATE'
    BEGIN
        UPDATE employee_cards
        SET card_status = 'NONAKTIF',
            remarks     = ISNULL(@Remarks, remarks),
            updated_at  = SYSDATETIME(),
            updated_by  = @UserId
        WHERE employee_card_id = @Id AND deleted_at IS NULL AND card_status = 'AKTIF';

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Kartu tidak ditemukan atau sudah nonaktif.', 16, 1);
            RETURN;
        END
    END

    -- Hanya untuk salah input.
    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE employee_cards
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE employee_card_id = @Id AND deleted_at IS NULL;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END
END;
GO
