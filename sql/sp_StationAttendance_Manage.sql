-- Prompt 58: simpan absen harian dari perangkat stasiun (satu kali Simpan = banyak baris).
-- Pengambilan data ada di procedure terpisah: sp_StationAttendance_Select.sql.
--
-- Konteks SELALU dari token perangkat + operator sesi (@ResourceId / @StationId) -- client
-- tidak pernah mengirim division_id. @UserId = user sistem station_system.
--
-- Tidak ada lock di absensi (beda dengan log workflow, Prompt 55): selama tanggalnya masih
-- dalam jendela 4 hari, data bebas diubah berulang kali.
--
-- ANSI_NULLS/QUOTED_IDENTIFIER wajib ON: employee_attendances punya filtered unique index
-- (UX_ea_employee_date), dan setting ini "dibekukan" saat CREATE PROCEDURE.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_StationAttendance_Manage
    @Action         VARCHAR(20),
    @ResourceId     INT = NULL,            -- operator sesi (line) -- pencatat & pemilik baris baru
    @StationId      INT = NULL,
    @AttendanceDate DATE = NULL,
    -- JSON array: [{"employeeId":1,"status":"H","checkIn":"07:02","checkOut":null,"note":null}, ...]
    @ItemsJson      NVARCHAR(MAX) = NULL,
    @UserId         INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action <> 'SAVE'
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END

    IF @ResourceId IS NULL
    BEGIN
        RAISERROR('Operator wajib dipilih.', 16, 1);
        RETURN;
    END

    DECLARE @Today DATE = CAST(SYSDATETIME() AS date);

    -- Jendela input: hari ini sampai 4 hari ke belakang. Tanggal masa depan juga ditolak.
    IF @AttendanceDate IS NULL OR @AttendanceDate > @Today OR @AttendanceDate < DATEADD(day, -4, @Today)
    BEGIN
        RAISERROR('Absen hanya bisa diisi untuk hari ini sampai 4 hari ke belakang.', 16, 1);
        RETURN;
    END

    DECLARE @Items TABLE (
        employee_id INT NOT NULL,
        status      CHAR(1) NULL,
        check_in    TIME(0) NULL,
        check_out   TIME(0) NULL,
        note        VARCHAR(200) NULL
    );

    -- Jam dibaca sebagai teks lalu TRY_CONVERT: string kosong dari form ("" bukan null)
    -- tidak boleh menggagalkan seluruh batch.
    INSERT INTO @Items (employee_id, status, check_in, check_out, note)
    SELECT j.employeeId,
           UPPER(NULLIF(LTRIM(RTRIM(j.status)), '')),
           TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM(j.checkIn)), '')),
           TRY_CONVERT(TIME(0), NULLIF(LTRIM(RTRIM(j.checkOut)), '')),
           NULLIF(LTRIM(RTRIM(j.note)), '')
    FROM OPENJSON(@ItemsJson)
        WITH (
            employeeId INT          '$.employeeId',
            status     VARCHAR(5)   '$.status',
            checkIn    VARCHAR(16)  '$.checkIn',
            checkOut   VARCHAR(16)  '$.checkOut',
            note       VARCHAR(200) '$.note'
        ) j
    WHERE j.employeeId IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM @Items)
    BEGIN
        RAISERROR('Tidak ada baris absen yang dikirim.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT employee_id FROM @Items GROUP BY employee_id HAVING COUNT(*) > 1)
    BEGIN
        RAISERROR('Satu pegawai dikirim lebih dari sekali dalam satu Simpan.', 16, 1);
        RETURN;
    END

    DECLARE @BadName VARCHAR(150);

    -- Status wajib salah satu dari H/I/S/A/C (CHECK constraint tabel sebagai jaring terakhir,
    -- tapi pesannya harus menyebut nama pegawai supaya PIC tahu baris mana).
    SELECT TOP 1 @BadName = ISNULL(e.employee_name, CONCAT('ID ', i.employee_id))
    FROM @Items i
    LEFT JOIN employees e ON e.employee_id = i.employee_id AND e.deleted_at IS NULL
    WHERE i.status IS NULL OR i.status NOT IN ('H', 'I', 'S', 'A', 'C');

    IF @BadName IS NOT NULL
    BEGIN
        RAISERROR('Status absen "%s" tidak valid.', 16, 1, @BadName);
        RETURN;
    END

    -- Cakupan: pegawai line ini (resource sesi) ATAU pegawai yang sudah punya baris absen di
    -- line ini pada tanggal tsb (riwayat orang yang sudah pindah/nonaktif tetap bisa dikoreksi).
    SELECT TOP 1 @BadName = ISNULL(e.employee_name, CONCAT('ID ', i.employee_id))
    FROM @Items i
    LEFT JOIN employees e ON e.employee_id = i.employee_id AND e.deleted_at IS NULL
    WHERE e.employee_id IS NULL
       OR (
            (e.resource_id IS NULL OR e.resource_id <> @ResourceId)
            AND NOT EXISTS (
                SELECT 1 FROM employee_attendances ea
                WHERE ea.employee_id = i.employee_id
                  AND ea.attendance_date = @AttendanceDate
                  AND ea.resource_id = @ResourceId
                  AND ea.deleted_at IS NULL
            )
          );

    IF @BadName IS NOT NULL
    BEGIN
        RAISERROR('Pegawai "%s" bukan anggota line ini.', 16, 1, @BadName);
        RETURN;
    END

    -- Status selain Hadir tidak boleh menyimpan jam (CK_ea_time_only_hadir) -- jam yang
    -- terkirim dibuang, BUKAN ditolak.
    UPDATE @Items SET check_in = NULL, check_out = NULL WHERE status <> 'H';

    BEGIN TRAN;
    BEGIN TRY
        -- Baris dicocokkan per (employee_id, attendance_date) -- sama dengan UX_ea_employee_date,
        -- jadi tidak mungkin lahir baris kedua untuk pegawai yang sama di tanggal yang sama.
        -- resource_id baris lama SENGAJA tidak diubah: itu jejak line yang pertama mencatat;
        -- koreksi dari line lain terekam di updated_by_resource_id.
        -- source juga tidak diubah (jejak asal data, mis. 'RFID' yang dikoreksi PIC).
        UPDATE ea
        SET ea.status    = i.status,
            ea.check_in  = i.check_in,
            ea.check_out = i.check_out,
            ea.note      = i.note,
            ea.station_id = @StationId,
            ea.updated_by_resource_id = @ResourceId,
            ea.updated_at = SYSDATETIME(),
            ea.updated_by = @UserId
        FROM employee_attendances ea
        INNER JOIN @Items i ON i.employee_id = ea.employee_id
        WHERE ea.attendance_date = @AttendanceDate AND ea.deleted_at IS NULL;

        INSERT INTO employee_attendances
            (employee_id, attendance_date, resource_id, status, check_in, check_out, note,
             source, station_id, recorded_by_resource_id, created_at, created_by)
        SELECT i.employee_id, @AttendanceDate, @ResourceId, i.status, i.check_in, i.check_out, i.note,
               'MANUAL', @StationId, @ResourceId, SYSDATETIME(), @UserId
        FROM @Items i
        WHERE NOT EXISTS (
            SELECT 1 FROM employee_attendances ea
            WHERE ea.employee_id = i.employee_id
              AND ea.attendance_date = @AttendanceDate
              AND ea.deleted_at IS NULL
        );

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @ErrMsg NVARCHAR(2048) = ERROR_MESSAGE();
        RAISERROR(@ErrMsg, 16, 1);
        RETURN;
    END CATCH
END;
GO
