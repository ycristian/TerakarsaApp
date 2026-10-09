-- Prompt 58: PIC line mengelola pegawainya sendiri dari perangkat stasiun
-- (CREATE / UPDATE / SETINACTIVE / REACTIVATE). Pintu masuk MANDIRI, terpisah dari
-- SIS_Employee_Manage (MASTER_EMPLOYEE) dan SIS_PpicEmployee_Manage (PPIC_EMPLOYEE) --
-- pola sama dengan Prompt 53: guard cakupan ditegakkan DI SINI, bukan hanya di controller.
-- Pengambilan data ada di procedure terpisah: sp_StationEmployee_Select.sql.
--
-- Divisi & line SELALU dari token perangkat + operator sesi (@DivisionId/@ResourceId) --
-- client tidak pernah mengirim division_id. @UserId = user sistem station_system.
--
-- Tidak ada DELETE di sini: dari stasiun pegawai hanya bisa dinonaktifkan (data absen & log
-- lama tidak pernah disentuh). Hapus permanen tetap wewenang Master Karyawan.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: employees punya filtered unique index
-- (UX_employees_code) dan filtered index no. telp (IX_employees_phone_no).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_StationEmployee_Manage
    -- CREATE / UPDATE / SETINACTIVE / REACTIVATE
    @Action         VARCHAR(20),
    @Id             INT = NULL,
    @DivisionId     INT = NULL,
    @ResourceId     INT = NULL,
    @EmployeeName   VARCHAR(150) = NULL,
    -- VARCHAR(30) (bukan 20 seperti kolomnya): yang masuk masih bentuk tampilan dari keyboard
    -- HP ("+62 812-2345-6789"), baru dipangkas jadi digit di bawah.
    @PhoneNo        VARCHAR(30) = NULL,
    @PositionId     INT = NULL,
    -- Tanggal mulai kerja. NULL = hari ini (pegawai didaftar di hari pertamanya).
    @JoinDate       DATE = NULL,
    @InactiveDate   DATE = NULL,
    @InactiveReason VARCHAR(20) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS date);

    IF @ResourceId IS NULL OR @DivisionId IS NULL
    BEGIN
        RAISERROR('Operator wajib dipilih.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (
        SELECT 1 FROM resources
        WHERE resource_id = @ResourceId AND division_id = @DivisionId AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Line ini tidak terdaftar di divisi stasiun.', 16, 1);
        RETURN;
    END

    -- Normalisasi no. telp: buang semua non-digit, awalan 62 jadi 0. Disimpan HANYA digit
    -- supaya pencarian & pengecekan "orang yang sama" tidak tergantung format tulisan.
    -- Dipakai CREATE maupun UPDATE (di luar keduanya tidak dibaca).
    DECLARE @Digits VARCHAR(30) = ISNULL(@PhoneNo, '');
    WHILE PATINDEX('%[^0-9]%', @Digits) > 0
        SET @Digits = STUFF(@Digits, PATINDEX('%[^0-9]%', @Digits), 1, '');

    IF LEFT(@Digits, 2) = '62'
        SET @Digits = '0' + SUBSTRING(@Digits, 3, LEN(@Digits));

    IF @Action IN ('CREATE', 'UPDATE')
    BEGIN
        SET @EmployeeName = NULLIF(LTRIM(RTRIM(@EmployeeName)), '');

        IF @EmployeeName IS NULL
        BEGIN
            RAISERROR('Nama pegawai wajib diisi.', 16, 1);
            RETURN;
        END

        IF NOT EXISTS (SELECT 1 FROM positions WHERE position_id = @PositionId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Jabatan wajib dipilih.', 16, 1);
            RETURN;
        END

        -- No. telp OPSIONAL dari stasiun (banyak pegawai lama belum punya nomor tercatat),
        -- tapi kalau diisi harus benar: minimal 9 digit. Kosong disimpan NULL supaya tidak
        -- ikut filtered index no. telp dan tidak pernah dianggap "nomor yang sama".
        IF LEN(@Digits) > 0 AND LEN(@Digits) < 9
        BEGIN
            RAISERROR('No. telp tidak valid. Minimal 9 digit.', 16, 1);
            RETURN;
        END

        SET @Digits = NULLIF(@Digits, '');

        -- Tanggal masuk boleh mundur (pegawai lama yang baru didaftar), tapi tidak boleh
        -- di masa depan. Kosong = hari ini.
        SET @JoinDate = ISNULL(@JoinDate, @Today);

        IF @JoinDate > @Today
        BEGIN
            RAISERROR('Tanggal masuk tidak boleh di masa depan.', 16, 1);
            RETURN;
        END
    END

    IF @Action = 'CREATE'
    BEGIN
        -- Nomor yang sama sudah dipakai? Pegawai AKTIF -> tolak. Pegawai NONAKTIF -> tawarkan
        -- "Aktifkan lagi?" (prefix PHONE_INACTIVE| dikenali UI). Itu sebabnya index no. telp
        -- sengaja BUKAN unique.
        DECLARE @ExistId INT, @ExistName VARCHAR(150), @ExistActive BIT, @ExistWhere VARCHAR(150);

        SELECT TOP 1 @ExistId = e.employee_id, @ExistName = e.employee_name, @ExistActive = e.is_active,
               @ExistWhere = ISNULL(r.resource_name, d.division_name)
        FROM employees e
        LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
        LEFT JOIN divisions d ON d.division_id = e.division_id AND d.deleted_at IS NULL
        -- @Digits NULL (no. telp dikosongkan) = tidak ada yang perlu dicek.
        WHERE @Digits IS NOT NULL AND e.phone_no = @Digits AND e.deleted_at IS NULL
        ORDER BY e.is_active DESC, e.employee_id ASC;

        IF @ExistId IS NOT NULL
        BEGIN
            SET @ExistWhere = ISNULL(@ExistWhere, '-');

            IF @ExistActive = 1
            BEGIN
                RAISERROR('PHONE_ACTIVE|%s|%s', 16, 1, @ExistName, @ExistWhere);
                RETURN;
            END

            RAISERROR('PHONE_INACTIVE|%d|%s|%s', 16, 1, @ExistId, @ExistName, @ExistWhere);
            RETURN;
        END

        -- Kode karyawan otomatis dari divisi stasiun, tanpa override dari stasiun
        -- (SIS_Employee_NextCode = sumber tunggal pola {division_code}-{4 digit}).
        DECLARE @CodeTable TABLE (SuggestedCode VARCHAR(40) NULL);
        INSERT INTO @CodeTable (SuggestedCode)
            EXEC SIS_Employee_NextCode @DivisionId = @DivisionId;

        DECLARE @NewCode VARCHAR(40) = (SELECT TOP 1 SuggestedCode FROM @CodeTable);

        IF @NewCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM employees WHERE employee_code = @NewCode AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Kode karyawan "%s" sudah digunakan. Coba simpan lagi.', 16, 1, @NewCode);
            RETURN;
        END

        INSERT INTO employees (division_id, resource_id, position_id, employee_code, employee_name,
                               phone_no, join_date, is_active, created_at, created_by)
        VALUES (@DivisionId, @ResourceId, @PositionId, @NewCode, @EmployeeName,
                @Digits, @JoinDate, 1, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    -- Ubah nama / no. telp / jabatan / tanggal masuk pegawai line ini. Divisi, line, kode
    -- karyawan, dan status aktif TIDAK bisa diubah dari stasiun -- itu wewenang Master
    -- Karyawan (pindah line/divisi lewat "Aktifkan lagi" atau admin).
    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM employees
            WHERE employee_id = @Id AND deleted_at IS NULL AND resource_id = @ResourceId
        )
        BEGIN
            RAISERROR('Pegawai ini bukan anggota line ini.', 16, 1);
            RETURN;
        END

        -- Nomor dipakai orang lain (aktif maupun nonaktif) -> tolak. Beda dengan CREATE, di
        -- sini TIDAK ada tawaran "Aktifkan lagi": yang sedang diedit orang yang berbeda.
        DECLARE @DupName VARCHAR(150), @DupWhere VARCHAR(150), @DupActive BIT;

        SELECT TOP 1 @DupName = e.employee_name, @DupActive = e.is_active,
               @DupWhere = ISNULL(r.resource_name, d.division_name)
        FROM employees e
        LEFT JOIN resources r ON r.resource_id = e.resource_id AND r.deleted_at IS NULL
        LEFT JOIN divisions d ON d.division_id = e.division_id AND d.deleted_at IS NULL
        WHERE @Digits IS NOT NULL AND e.phone_no = @Digits AND e.deleted_at IS NULL AND e.employee_id <> @Id
        ORDER BY e.is_active DESC, e.employee_id ASC;

        IF @DupName IS NOT NULL
        BEGIN
            SET @DupWhere = ISNULL(@DupWhere, '-') + CASE WHEN @DupActive = 1 THEN '' ELSE ', nonaktif' END;
            RAISERROR('No. telp sudah dipakai %s (%s).', 16, 1, @DupName, @DupWhere);
            RETURN;
        END

        UPDATE employees
        SET employee_name = @EmployeeName,
            phone_no = @Digits,
            position_id = @PositionId,
            join_date = @JoinDate,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'SETINACTIVE'
    BEGIN
        -- Hanya pegawai AKTIF di line ini. Absen & log lama tidak disentuh.
        DECLARE @SetName VARCHAR(150);
        SELECT @SetName = employee_name
        FROM employees
        WHERE employee_id = @Id AND deleted_at IS NULL AND is_active = 1 AND resource_id = @ResourceId;

        IF @SetName IS NULL
        BEGIN
            RAISERROR('Pegawai ini bukan anggota aktif line ini.', 16, 1);
            RETURN;
        END

        IF @InactiveDate IS NULL OR @InactiveDate > @Today
        BEGIN
            RAISERROR('Tanggal terakhir kerja wajib diisi dan tidak boleh di masa depan.', 16, 1);
            RETURN;
        END

        IF @InactiveReason IS NULL
           OR @InactiveReason NOT IN ('RESIGN', 'HABIS_KONTRAK', 'DIBERHENTIKAN', 'PINDAH_DIVISI')
        BEGIN
            RAISERROR('Alasan nonaktif wajib dipilih.', 16, 1);
            RETURN;
        END

        UPDATE employees
        SET is_active = 0,
            inactive_date = @InactiveDate,
            inactive_reason = @InactiveReason,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END

    ELSE IF @Action = 'REACTIVATE'
    BEGIN
        -- Boleh tanpa approval, termasuk pegawai dari line/divisi lain: diaktifkan lagi
        -- SEKALIAN dipindah ke divisi stasiun & line operator sesi. employee_code TIDAK
        -- diubah walau divisinya pindah (kode = identitas, bukan alamat).
        IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = @Id AND deleted_at IS NULL AND is_active = 0)
        BEGIN
            RAISERROR('Pegawai nonaktif tidak ditemukan.', 16, 1);
            RETURN;
        END

        UPDATE employees
        SET is_active = 1,
            inactive_date = NULL,
            inactive_reason = NULL,
            division_id = @DivisionId,
            resource_id = @ResourceId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE employee_id = @Id AND deleted_at IS NULL;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END
END;
GO
