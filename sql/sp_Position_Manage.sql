-- Mutasi data positions (CREATE/UPDATE/DELETE). Pengambilan data (list/by id)
-- ada di procedure terpisah: sp_Position_Select.sql (SIS_Position_GetAll / SIS_Position_GetById).
-- Catatan: positions tidak punya kolom code / unique index, jadi tidak ada pengecekan duplikat.
--
-- Prompt 58 (lanjutan): satu jabatan bisa dibatasi ke beberapa divisi (division_positions,
-- lihat alter_58b_division_positions.sql). Pemetaannya diatur dari halaman Master Jabatan,
-- dan dipakai membatasi dropdown "Jabatan" saat mendaftar pegawai dari stasiun.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: division_positions punya filtered unique index
-- (UX_divpos_division_position).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Position_Manage
    @Action         VARCHAR(20),
    @Id             INT = NULL,
    @PositionName   VARCHAR(150) = NULL,
    -- Prompt 70: jabatan ini boleh membuka menu satpam di aplikasi gate. Akses melekat pada
    -- JABATAN, bukan pada kartu dan bukan pada user login (aplikasi gate memang tanpa login).
    @IsGateOperator BIT = 0,
    -- Prompt 58 (lanjutan): divisi yang boleh memakai jabatan ini (division_positions).
    -- JSON array id divisi, mis. '[1,3]'. NULL = JANGAN SENTUH pemetaan (caller lama aman);
    -- '[]' = kosongkan, artinya jabatan ini tidak dibatasi ke divisi mana pun -- lihat aturan
    -- fallback di SIS_Position_GetByDivision.
    @DivisionIdsJson NVARCHAR(MAX) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        INSERT INTO positions (position_name, is_gate_operator, created_at, created_by)
        VALUES (@PositionName, ISNULL(@IsGateOperator, 0), SYSDATETIME(), @UserId);

        SET @Id = CAST(SCOPE_IDENTITY() AS INT);

        EXEC SIS_Position_SyncDivisions @PositionId = @Id, @DivisionIdsJson = @DivisionIdsJson, @UserId = @UserId;

        SELECT @Id AS NewId;
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        UPDATE positions
        SET position_name = @PositionName,
            is_gate_operator = ISNULL(@IsGateOperator, 0),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE position_id = @Id AND deleted_at IS NULL;

        EXEC SIS_Position_SyncDivisions @PositionId = @Id, @DivisionIdsJson = @DivisionIdsJson, @UserId = @UserId;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        UPDATE positions
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE position_id = @Id AND deleted_at IS NULL;

        -- Pemetaan ikut dihapus supaya jabatan yang sudah dihapus tidak lagi muncul di
        -- dropdown divisi mana pun.
        UPDATE division_positions
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE position_id = @Id AND deleted_at IS NULL;
    END
END;
GO

-- Sinkronisasi pemetaan jabatan -> divisi. Dipisah supaya CREATE & UPDATE memakai logika yang
-- sama persis. @DivisionIdsJson NULL = tidak melakukan apa-apa (caller lama tidak diam-diam
-- menghapus pemetaan yang sudah ada).
CREATE OR ALTER PROCEDURE SIS_Position_SyncDivisions
    @PositionId      INT,
    @DivisionIdsJson NVARCHAR(MAX) = NULL,
    @UserId          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @DivisionIdsJson IS NULL OR @PositionId IS NULL RETURN;

    DECLARE @Ids TABLE (division_id INT PRIMARY KEY);

    INSERT INTO @Ids (division_id)
    SELECT DISTINCT TRY_CAST(value AS INT)
    FROM OPENJSON(@DivisionIdsJson)
    WHERE TRY_CAST(value AS INT) IS NOT NULL;

    IF EXISTS (
        SELECT 1 FROM @Ids i
        WHERE NOT EXISTS (SELECT 1 FROM divisions d WHERE d.division_id = i.division_id AND d.deleted_at IS NULL)
    )
    BEGIN
        RAISERROR('Divisi yang dipilih tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- Divisi yang dicabut -> soft delete.
    UPDATE dp
    SET dp.deleted_at = SYSDATETIME(), dp.deleted_by = @UserId
    FROM division_positions dp
    WHERE dp.position_id = @PositionId AND dp.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM @Ids i WHERE i.division_id = dp.division_id);

    -- Divisi baru -> insert (baris lama yang sudah soft-delete sengaja tidak dihidupkan
    -- kembali; filtered unique index hanya berlaku untuk baris hidup).
    INSERT INTO division_positions (division_id, position_id, created_at, created_by)
    SELECT i.division_id, @PositionId, SYSDATETIME(), @UserId
    FROM @Ids i
    WHERE NOT EXISTS (
        SELECT 1 FROM division_positions dp
        WHERE dp.position_id = @PositionId AND dp.division_id = i.division_id AND dp.deleted_at IS NULL
    );
END;
GO
