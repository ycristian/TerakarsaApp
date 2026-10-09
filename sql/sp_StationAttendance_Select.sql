-- Prompt 58: pengambilan data absensi untuk perangkat stasiun (SELECT saja, tidak menyentuh
-- data). Mutasi ada di procedure terpisah: sp_StationAttendance_Manage.sql.
--
-- Empat SP di file ini:
--   SIS_StationAttendance_List         -- isi sub-tab Input (per pegawai) + jadwal & ringkasan
--   SIS_StationAttendance_Recap        -- grid satu periode gajian (Minggu s/d Sabtu) + ringkasan
--   SIS_StationAttendance_Periods      -- isi dropdown periode di sub-tab Rekap & Input
--   SIS_StationAttendance_PendingDates -- chip kuning "masih ada yang belum diisi" + badge tab
--
-- CAKUPAN PEGAWAI (sama di SP List/Recap/PendingDates): pegawai is_active = 1 dengan resource_id = @ResourceId,
-- DITAMBAH pegawai yang sudah punya baris absen di resource itu pada tanggal/rentang tsb --
-- supaya riwayat orang yang sudah nonaktif/pindah line tetap tampil.
--
-- day_of_week dihitung dari basis Senin (1900-01-01 = Senin) lewat DATEDIFF, BUKAN DATEPART
-- weekday -- hasilnya tidak bergantung setting DATEFIRST sesi pemanggil.
--
-- TELAT tidak pernah disimpan: status 'H' dengan check_in > start_time jadwal hari itu.
-- Hari is_working_day = 0 (atau tanpa baris jadwal) dianggap LIBUR -- start_time-nya
-- diabaikan, jadi absen di hari libur tidak pernah dihitung telat.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_StationAttendance_List
    @DivisionId     INT,
    @ResourceId     INT,
    @AttendanceDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Dow TINYINT = (DATEDIFF(day, '19000101', @AttendanceDate) % 7) + 1;
    DECLARE @IsWorkingDay BIT = 0;
    DECLARE @StartTime TIME(0) = NULL;
    DECLARE @EndTime TIME(0) = NULL;

    SELECT @IsWorkingDay = w.is_working_day, @StartTime = w.start_time, @EndTime = w.end_time
    FROM work_schedule_defaults w
    WHERE w.division_id = @DivisionId AND w.day_of_week = @Dow AND w.deleted_at IS NULL;

    SET @IsWorkingDay = ISNULL(@IsWorkingDay, 0);
    -- Libur: jam jadwal tidak dipakai menghitung telat.
    IF @IsWorkingDay = 0 SET @StartTime = NULL;

    SELECT e.employee_id        AS EmployeeId,
           e.employee_code      AS EmployeeCode,
           e.employee_name      AS EmployeeName,
           p.position_name      AS PositionName,
           e.is_active          AS IsActive,
           ea.attendance_id     AS AttendanceId,
           ea.status            AS Status,
           ea.check_in          AS CheckIn,
           ea.check_out         AS CheckOut,
           ea.note              AS Note,
           ea.source            AS Source,
           CAST(CASE WHEN ea.status = 'H' AND @StartTime IS NOT NULL AND ea.check_in > @StartTime
                     THEN 1 ELSE 0 END AS BIT) AS IsLate,
           CASE WHEN ea.status = 'H' AND @StartTime IS NOT NULL AND ea.check_in > @StartTime
                THEN DATEDIFF(minute, @StartTime, ea.check_in) ELSE 0 END AS LateMinutes
    INTO #Scope
    FROM employees e
    INNER JOIN positions p ON p.position_id = e.position_id
    LEFT JOIN employee_attendances ea
           ON ea.employee_id = e.employee_id
          AND ea.attendance_date = @AttendanceDate
          AND ea.deleted_at IS NULL
    WHERE e.deleted_at IS NULL
      AND (
            (e.is_active = 1 AND e.resource_id = @ResourceId)
            OR EXISTS (
                SELECT 1 FROM employee_attendances ea2
                WHERE ea2.employee_id = e.employee_id
                  AND ea2.attendance_date = @AttendanceDate
                  AND ea2.resource_id = @ResourceId
                  AND ea2.deleted_at IS NULL
            )
          );

    -- Result 1: baris pegawai. Yang BELUM diisi turun ke bawah (lihat mockup sub-tab Input).
    SELECT EmployeeId, EmployeeCode, EmployeeName, PositionName, IsActive,
           AttendanceId, Status, CheckIn, CheckOut, Note, Source, IsLate, LateMinutes
    FROM #Scope
    ORDER BY CASE WHEN AttendanceId IS NULL THEN 1 ELSE 0 END, EmployeeName ASC;

    -- Result 2: jadwal hari itu + ringkasan 5 kotak.
    SELECT CAST(@IsWorkingDay AS BIT) AS IsWorkingDay,
           @StartTime AS StartTime,
           @EndTime   AS EndTime,
           SUM(CASE WHEN Status = 'H' THEN 1 ELSE 0 END) AS HadirCount,
           SUM(CASE WHEN Status = 'I' THEN 1 ELSE 0 END) AS IzinCount,
           SUM(CASE WHEN Status = 'S' THEN 1 ELSE 0 END) AS SakitCount,
           SUM(CASE WHEN Status = 'A' THEN 1 ELSE 0 END) AS AlpaCount,
           SUM(CASE WHEN Status = 'C' THEN 1 ELSE 0 END) AS CutiCount,
           SUM(CASE WHEN AttendanceId IS NULL THEN 1 ELSE 0 END) AS BelumCount,
           SUM(CASE WHEN IsLate = 1 THEN 1 ELSE 0 END) AS TelatCount,
           COUNT(*) AS TotalCount
    FROM #Scope;

    DROP TABLE #Scope;
END;
GO

-- Rekap SATU PERIODE GAJIAN (payroll_periods), bukan 5 hari terakhir.
--
-- PEMETAAN PERIODE -> TANGGAL ABSEN: periode gajian berjalan Sabtu 10:00 -> Sabtu 10:00,
-- jadi satu hari Sabtu bisa jatuh di DUA periode kalau dipotong per jam. Untuk absensi itu
-- tidak masuk akal (absen dicatat per TANGGAL, bukan per jam), jadi hari Sabtu dihitung UTUH
-- milik periode SEBELUMNYA -- yaitu periode yang BERAKHIR di Sabtu itu. Hasilnya tiap periode
-- = Minggu s/d Sabtu (7 hari):
--     StartDate = CAST(period_start AS date) + 1   (Minggu)
--     EndDate   = CAST(period_end   AS date)       (Sabtu penutup)
-- Aturan ini HANYA untuk absensi; log workflow/lock tetap memakai batas jam 10:00.
CREATE OR ALTER PROCEDURE SIS_StationAttendance_Recap
    @DivisionId      INT,
    @ResourceId      INT,
    -- NULL = periode absen berjalan (periode yang Sabtu penutupnya >= hari ini).
    @PayrollPeriodId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS date);

    IF @PayrollPeriodId IS NULL
        SELECT TOP 1 @PayrollPeriodId = payroll_period_id
        FROM payroll_periods
        WHERE deleted_at IS NULL AND CAST(period_end AS date) >= @Today
        ORDER BY period_end ASC;

    DECLARE @StartDate DATE, @EndDate DATE, @PeriodCode VARCHAR(10);

    SELECT @StartDate = DATEADD(day, 1, CAST(period_start AS date)),
           @EndDate = CAST(period_end AS date),
           @PeriodCode = period_code
    FROM payroll_periods
    WHERE payroll_period_id = @PayrollPeriodId AND deleted_at IS NULL;

    -- Periode belum di-generate (SIS_PayrollPeriod_Manage GENERATE_YEAR) -- jangan error,
    -- jatuh balik ke minggu absen berjalan memakai aturan yang sama (Minggu s/d Sabtu).
    IF @EndDate IS NULL
    BEGIN
        SET @PayrollPeriodId = NULL;
        -- Sabtu pertama >= hari ini. @Dow: 1=Senin..7=Minggu, independen @@DATEFIRST.
        DECLARE @Dow TINYINT = (DATEDIFF(day, '19000101', @Today) % 7) + 1;
        SET @EndDate = DATEADD(day, (6 - @Dow + 7) % 7, @Today);
        SET @StartDate = DATEADD(day, -6, @EndDate);
    END

    DECLARE @Dates TABLE (
        attendance_date DATE PRIMARY KEY,
        is_working_day  BIT NOT NULL,
        start_time      TIME(0) NULL,
        end_time        TIME(0) NULL
    );

    ;WITH DayOffsets AS (
        SELECT 0 AS n
        UNION ALL
        SELECT n + 1 FROM DayOffsets WHERE n + 1 <= DATEDIFF(day, @StartDate, @EndDate)
    )
    INSERT INTO @Dates (attendance_date, is_working_day, start_time, end_time)
    SELECT d.dt,
           CAST(ISNULL(w.is_working_day, 0) AS BIT),
           -- Libur: jam jadwal tidak dipakai menghitung telat.
           CASE WHEN ISNULL(w.is_working_day, 0) = 1 THEN w.start_time END,
           w.end_time
    FROM (SELECT DATEADD(day, n, @StartDate) AS dt FROM DayOffsets) d
    LEFT JOIN work_schedule_defaults w
           ON w.division_id = @DivisionId
          AND w.day_of_week = (DATEDIFF(day, '19000101', d.dt) % 7) + 1
          AND w.deleted_at IS NULL;

    SELECT e.employee_id   AS EmployeeId,
           e.employee_name AS EmployeeName,
           p.position_name AS PositionName,
           e.is_active     AS IsActive
    INTO #RecapEmp
    FROM employees e
    INNER JOIN positions p ON p.position_id = e.position_id
    WHERE e.deleted_at IS NULL
      AND (
            (e.is_active = 1 AND e.resource_id = @ResourceId)
            OR EXISTS (
                SELECT 1 FROM employee_attendances ea2
                WHERE ea2.employee_id = e.employee_id
                  AND ea2.resource_id = @ResourceId
                  AND ea2.attendance_date BETWEEN @StartDate AND @EndDate
                  AND ea2.deleted_at IS NULL
            )
          );

    -- Kode sel: H hadir, T hadir telat, I/S/A/C sesuai status, '?' belum diisi (hari kerja
    -- yang SUDAH lewat), '.' hari kerja yang BELUM tiba, '-' libur tanpa data.
    -- '.' sengaja dibedakan dari '?': dalam periode berjalan sisa harinya bukan tunggakan,
    -- jadi tidak ikut dihitung "Belum diisi" maupun diberi tanda peringatan di grid.
    -- En dash/titik tengah digambar client -- kolom ini CHAR(1) non-unicode.
    SELECT s.EmployeeId,
           d.attendance_date AS AttendanceDate,
           CAST(
             CASE WHEN ea.attendance_id IS NULL
                       THEN CASE WHEN d.is_working_day = 0 THEN '-'
                                 WHEN d.attendance_date > @Today THEN '.'
                                 ELSE '?' END
                  WHEN ea.status = 'H' AND d.start_time IS NOT NULL AND ea.check_in > d.start_time
                       THEN 'T'
                  ELSE ea.status END AS CHAR(1)) AS Code
    INTO #Cells
    FROM #RecapEmp s
    CROSS JOIN @Dates d
    LEFT JOIN employee_attendances ea
           ON ea.employee_id = s.EmployeeId
          AND ea.attendance_date = d.attendance_date
          AND ea.deleted_at IS NULL;

    DECLARE @WorkingDays INT = (SELECT COUNT(*) FROM @Dates WHERE is_working_day = 1);
    -- % kehadiran hanya menghitung hari kerja yang SUDAH LEWAT (termasuk hari ini).
    DECLARE @ElapsedWorkingDays INT = (SELECT COUNT(*) FROM @Dates WHERE is_working_day = 1 AND attendance_date <= @Today);
    DECLARE @ActiveEmp INT = (SELECT COUNT(*) FROM #RecapEmp WHERE IsActive = 1);

    -- Result 1: tanggal kolom grid (satu periode = 7 hari).
    SELECT attendance_date AS AttendanceDate,
           is_working_day  AS IsWorkingDay,
           start_time      AS StartTime,
           end_time        AS EndTime,
           CAST(CASE WHEN attendance_date = @Today THEN 1 ELSE 0 END AS BIT) AS IsToday
    FROM @Dates
    ORDER BY attendance_date ASC;

    -- Result 2: baris pegawai + "Hadir x/y" (y = hari kerja dalam rentang, sama untuk semua).
    SELECT s.EmployeeId, s.EmployeeName, s.PositionName, s.IsActive,
           (SELECT COUNT(*) FROM #Cells c WHERE c.EmployeeId = s.EmployeeId AND c.Code IN ('H', 'T')) AS HadirCount,
           @WorkingDays AS WorkingDayCount
    FROM #RecapEmp s
    ORDER BY s.EmployeeName ASC;

    -- Result 3: sel grid.
    SELECT EmployeeId, AttendanceDate, Code
    FROM #Cells
    ORDER BY EmployeeId, AttendanceDate;

    -- Result 4: ringkasan. Penyebut % = pegawai AKTIF x hari kerja yang sudah lewat.
    SELECT CASE WHEN @ElapsedWorkingDays = 0 OR @ActiveEmp = 0 THEN 0
                ELSE CAST(ROUND(
                     100.0 * (SELECT COUNT(*) FROM #Cells c
                              INNER JOIN #RecapEmp e2 ON e2.EmployeeId = c.EmployeeId AND e2.IsActive = 1
                              WHERE c.Code IN ('H', 'T') AND c.AttendanceDate <= @Today)
                     / (@ActiveEmp * @ElapsedWorkingDays), 0) AS INT)
           END AS AttendancePercent,
           (SELECT COUNT(*) FROM #Cells WHERE Code = 'T') AS TelatCount,
           (SELECT COUNT(*) FROM #Cells WHERE Code = 'A') AS AlpaCount,
           (SELECT COUNT(*) FROM #Cells WHERE Code = '?') AS BelumCount,
           @WorkingDays AS WorkingDayCount,
           @StartDate  AS StartDate,
           @EndDate    AS EndDate,
           @PayrollPeriodId AS PayrollPeriodId,
           @PeriodCode AS PeriodCode;

    DROP TABLE #Cells;
    DROP TABLE #RecapEmp;
END;
GO

-- Isi dropdown periode di sub-tab Rekap. Periode yang SUDAH final tetap ikut -- finalisasi
-- itu urusan gajian (SIS_WorkflowLock_Manage), bukan absensi, dan rekap ini read-only.
-- Batasnya periode absen berjalan (Sabtu penutup >= hari ini) ke belakang, 12 terakhir --
-- cukup untuk menengok ke belakang tanpa membuat dropdown sepanjang tahun.
CREATE OR ALTER PROCEDURE SIS_StationAttendance_Periods
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS date);
    DECLARE @CurrentEndDate DATE;

    SELECT TOP 1 @CurrentEndDate = CAST(period_end AS date)
    FROM payroll_periods
    WHERE deleted_at IS NULL AND CAST(period_end AS date) >= @Today
    ORDER BY period_end ASC;

    -- Semua periode sudah lewat (tahun berjalan belum di-generate) -- tampilkan yang terakhir
    -- ada supaya dropdown tidak kosong.
    IF @CurrentEndDate IS NULL
        SELECT @CurrentEndDate = MAX(CAST(period_end AS date)) FROM payroll_periods WHERE deleted_at IS NULL;

    SELECT TOP 12
           pp.payroll_period_id AS PayrollPeriodId,
           pp.period_code       AS PeriodCode,
           -- Sabtu awal milik periode sebelumnya, jadi tanggal absen mulai Minggu.
           DATEADD(day, 1, CAST(pp.period_start AS date)) AS StartDate,
           CAST(pp.period_end AS date)                    AS EndDate,
           CAST(CASE WHEN CAST(pp.period_end AS date) = @CurrentEndDate THEN 1 ELSE 0 END AS BIT) AS IsCurrent
    FROM payroll_periods pp
    WHERE pp.deleted_at IS NULL
      AND CAST(pp.period_end AS date) <= @CurrentEndDate
    ORDER BY pp.period_end DESC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_StationAttendance_PendingDates
    @DivisionId INT,
    @ResourceId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today DATE = CAST(SYSDATETIME() AS date);

    -- Hanya hari kerja dalam jendela input (hari ini s/d 4 hari ke belakang) yang masih punya
    -- pegawai AKTIF line ini tanpa baris absen. Hari libur tidak pernah jadi tunggakan, jadi
    -- tab Absen tidak pernah berbadge di hari libur.
    SELECT q.AttendanceDate, q.PendingCount
    FROM (
        SELECT d.dt AS AttendanceDate,
               (SELECT COUNT(*)
                FROM employees e
                WHERE e.deleted_at IS NULL AND e.is_active = 1 AND e.resource_id = @ResourceId
                  AND NOT EXISTS (
                      SELECT 1 FROM employee_attendances ea
                      WHERE ea.employee_id = e.employee_id
                        AND ea.attendance_date = d.dt
                        AND ea.deleted_at IS NULL
                  )) AS PendingCount
        FROM (VALUES (DATEADD(day, -4, @Today)), (DATEADD(day, -3, @Today)),
                     (DATEADD(day, -2, @Today)), (DATEADD(day, -1, @Today)), (@Today)) AS d(dt)
        INNER JOIN work_schedule_defaults w
                ON w.division_id = @DivisionId
               AND w.day_of_week = (DATEDIFF(day, '19000101', d.dt) % 7) + 1
               AND w.is_working_day = 1
               AND w.deleted_at IS NULL
    ) q
    WHERE q.PendingCount > 0
    ORDER BY q.AttendanceDate ASC;
END;
GO
