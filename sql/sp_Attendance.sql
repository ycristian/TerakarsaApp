-- Prompt 70 -- Rekap & koreksi attendance_sessions untuk halaman admin /attendance
-- (module HR_ATTENDANCE tab 2 "Rekap Absensi" dan tab 3 "Koreksi Absensi").
--
-- IZIN/SAKIT/CUTI TIDAK ditangani di sini. Tidak ada tap = tidak ada baris. Jangan menambah
-- tabel atau kolom untuk itu (lihat "Yang TIDAK boleh dilakukan" di prompt 70). Absensi
-- manual/izin per divisi yang diisi PIC line adalah fitur lain (employee_attendances,
-- Prompt 58) dan sengaja tidak disentuh file ini.
--
-- Prompt ini juga TIDAK menghitung terlambat/lembur bernilai upah -- hanya jam mentah.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- ============================================================================
-- SIS_Attendance_Report -- satu baris per sesi. Sesi ANOMALI ikut muncul dengan jam pulang
-- kosong (justru itu yang harus kelihatan di rekap).
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Attendance_Report
    @DateFrom    DATE,
    @DateTo      DATE,
    @DivisionId  INT = NULL,
    @ResourceId  INT = NULL,
    @EmployeeId  INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.attendance_session_id AS Id,
           s.work_date             AS WorkDate,
           s.employee_id           AS EmployeeId,
           e.employee_name         AS EmployeeName,
           e.employee_code         AS EmployeeCode,
           -- Divisi & resource dibaca dari SNAPSHOT di sesi, bukan dari employees saat ini --
           -- mutasi line tidak boleh mengubah riwayat absensi.
           s.division_id           AS DivisionId,
           d.division_name         AS DivisionName,
           s.resource_id           AS ResourceId,
           r.resource_name         AS ResourceName,
           r.color_hex             AS ColorHex,
           s.check_in_at           AS CheckInAt,
           s.check_out_at          AS CheckOutAt,
           CASE WHEN s.check_out_at IS NULL THEN NULL
                ELSE DATEDIFF(MINUTE, s.check_in_at, s.check_out_at) END AS DurationMinutes,
           s.session_status        AS SessionStatus,
           s.session_flag          AS SessionFlag,
           s.entry_source          AS EntrySource,
           s.remarks               AS Remarks
    FROM attendance_sessions s
    INNER JOIN employees e ON e.employee_id = s.employee_id
    INNER JOIN divisions d ON d.division_id = s.division_id
    LEFT JOIN resources r ON r.resource_id = s.resource_id AND r.deleted_at IS NULL
    WHERE s.deleted_at IS NULL
      AND s.work_date >= @DateFrom
      AND s.work_date <= @DateTo
      AND (@DivisionId IS NULL OR s.division_id = @DivisionId)
      AND (@ResourceId IS NULL OR s.resource_id = @ResourceId)
      AND (@EmployeeId IS NULL OR s.employee_id = @EmployeeId)
    ORDER BY s.work_date DESC, s.check_in_at DESC, s.attendance_session_id DESC;
END;
GO

-- ============================================================================
-- SIS_Attendance_Anomali -- antrian kerja halaman Koreksi.
--
-- PENAMBAHAN YANG DISENGAJA: sesi ANOMALI dengan session_flag = 'DIVERIFIKASI' tidak ikut
-- muncul. Prompt meminta aksi "tandai sudah benar" di tab Koreksi, tapi sesi yang jam
-- pulangnya memang tidak diketahui tidak bisa berubah jadi CLOSED (constraint
-- CK_as_checkout_shape: CLOSED wajib punya check_out_at). Jadi "tandai sudah benar" memberi
-- flag DIVERIFIKASI -- status tetap ANOMALI (jujur: jam pulang memang kosong), tapi barisnya
-- keluar dari antrian supaya antrian bisa habis.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Attendance_Anomali
    @DateFrom DATE,
    @DateTo   DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT s.attendance_session_id AS Id,
           s.work_date             AS WorkDate,
           s.employee_id           AS EmployeeId,
           e.employee_name         AS EmployeeName,
           e.employee_code         AS EmployeeCode,
           s.division_id           AS DivisionId,
           d.division_name         AS DivisionName,
           s.resource_id           AS ResourceId,
           r.resource_name         AS ResourceName,
           r.color_hex             AS ColorHex,
           s.check_in_at           AS CheckInAt,
           s.check_out_at          AS CheckOutAt,
           CAST(NULL AS INT)       AS DurationMinutes,
           s.session_status        AS SessionStatus,
           s.session_flag          AS SessionFlag,
           s.entry_source          AS EntrySource,
           s.remarks               AS Remarks
    FROM attendance_sessions s
    INNER JOIN employees e ON e.employee_id = s.employee_id
    INNER JOIN divisions d ON d.division_id = s.division_id
    LEFT JOIN resources r ON r.resource_id = s.resource_id AND r.deleted_at IS NULL
    WHERE s.deleted_at IS NULL
      AND s.session_status = 'ANOMALI'
      AND ISNULL(s.session_flag, '') <> 'DIVERIFIKASI'
      AND s.work_date >= @DateFrom
      AND s.work_date <= @DateTo
    ORDER BY s.work_date DESC, s.check_in_at ASC;
END;
GO

-- ============================================================================
-- SIS_Attendance_Manage -- UPDATE / CREATE_MANUAL / ACK / DELETE.
-- Semua aksi dari tab Koreksi WAJIB memberi catatan (remarks) -- jam absensi yang diubah
-- manusia harus punya alasan tertulis.
-- ============================================================================
CREATE OR ALTER PROCEDURE SIS_Attendance_Manage
    @Action      VARCHAR(20),
    @Id          INT = NULL,
    @EmployeeId  INT = NULL,
    @CheckInAt   DATETIME2 = NULL,
    @CheckOutAt  DATETIME2 = NULL,
    @Remarks     VARCHAR(255) = NULL,
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Remarks = NULLIF(LTRIM(RTRIM(ISNULL(@Remarks, ''))), '');

    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM attendance_sessions WHERE attendance_session_id = @Id AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Sesi absensi tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @CheckInAt IS NULL OR @CheckOutAt IS NULL
        BEGIN
            RAISERROR('Jam masuk dan jam pulang wajib diisi untuk koreksi.', 16, 1);
            RETURN;
        END

        IF @CheckOutAt < @CheckInAt
        BEGIN
            RAISERROR('Jam pulang tidak boleh lebih awal dari jam masuk.', 16, 1);
            RETURN;
        END

        IF @Remarks IS NULL
        BEGIN
            RAISERROR('Catatan koreksi wajib diisi.', 16, 1);
            RETURN;
        END

        -- work_date sengaja TIDAK diubah: pemilik sesi tetap tanggal check in aslinya supaya
        -- rekap per tanggal tidak bergeser gara-gara koreksi jam.
        UPDATE attendance_sessions
        SET check_in_at     = @CheckInAt,
            check_out_at    = @CheckOutAt,
            session_status  = 'CLOSED',
            session_flag    = 'DIKOREKSI',
            remarks         = @Remarks,
            updated_at      = SYSDATETIME(),
            updated_by      = @UserId
        WHERE attendance_session_id = @Id AND deleted_at IS NULL;
    END

    -- Sesi untuk karyawan yang kartunya hilang / lupa tap sama sekali.
    ELSE IF @Action = 'CREATE_MANUAL'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM employees WHERE employee_id = @EmployeeId AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Karyawan tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @CheckInAt IS NULL
        BEGIN
            RAISERROR('Jam masuk wajib diisi.', 16, 1);
            RETURN;
        END

        IF @CheckOutAt IS NOT NULL AND @CheckOutAt < @CheckInAt
        BEGIN
            RAISERROR('Jam pulang tidak boleh lebih awal dari jam masuk.', 16, 1);
            RETURN;
        END

        IF @Remarks IS NULL
        BEGIN
            RAISERROR('Catatan wajib diisi untuk absensi manual.', 16, 1);
            RETURN;
        END

        -- Sesi manual TIDAK pernah dibuat berstatus OPEN: kalau jam pulang belum diketahui,
        -- barisnya langsung masuk antrian Koreksi (ANOMALI). Kalau dibuat OPEN, sesinya akan
        -- bertabrakan dengan tap kartu orang itu lewat UX_as_open_per_employee.
        INSERT INTO attendance_sessions
            (employee_id, division_id, resource_id, work_date, check_in_at, check_out_at,
             session_status, session_flag, entry_source, remarks, created_at, created_by)
        SELECT e.employee_id, e.division_id, e.resource_id, CAST(@CheckInAt AS DATE),
               @CheckInAt, @CheckOutAt,
               CASE WHEN @CheckOutAt IS NULL THEN 'ANOMALI' ELSE 'CLOSED' END,
               CASE WHEN @CheckOutAt IS NULL THEN 'BELUM_CHECKOUT' ELSE NULL END,
               'MANUAL', @Remarks, SYSDATETIME(), @UserId
        FROM employees e
        WHERE e.employee_id = @EmployeeId AND e.deleted_at IS NULL;

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewId;
    END

    -- "Tandai sudah benar": sesi memang tidak punya jam pulang dan tidak akan pernah punya
    -- (kartu dibawa pulang / hilang). Statusnya tetap ANOMALI, tapi keluar dari antrian Koreksi.
    ELSE IF @Action = 'ACK'
    BEGIN
        IF @Remarks IS NULL
        BEGIN
            RAISERROR('Catatan wajib diisi.', 16, 1);
            RETURN;
        END

        UPDATE attendance_sessions
        SET session_flag = 'DIVERIFIKASI',
            remarks      = @Remarks,
            updated_at   = SYSDATETIME(),
            updated_by   = @UserId
        WHERE attendance_session_id = @Id AND deleted_at IS NULL AND session_status = 'ANOMALI';

        IF @@ROWCOUNT = 0
        BEGIN
            RAISERROR('Sesi absensi tidak ditemukan atau bukan sesi anomali.', 16, 1);
            RETURN;
        END
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF @Remarks IS NULL
        BEGIN
            RAISERROR('Catatan wajib diisi saat menghapus sesi absensi.', 16, 1);
            RETURN;
        END

        UPDATE attendance_sessions
        SET remarks    = @Remarks,
            deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE attendance_session_id = @Id AND deleted_at IS NULL;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak dikenal.', 16, 1);
        RETURN;
    END
END;
GO
