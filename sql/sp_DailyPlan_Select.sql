-- Pengambilan data Planning Harian PPIC (Prompt 37). Mutasi ada di sp_DailyPlan_Manage.sql
-- (SIS_DailyPlan_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Tiga result set: (1) divisi + rencana tersimpan/prefill, (2) resource untuk divisi
-- bermode RESOURCE, (3) istirahat yang berlaku pada hari itu. Sumber data form PPIC.
CREATE OR ALTER PROCEDURE SIS_DailyPlan_GetByDate
    @PlanDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Konversi DATEPART(WEEKDAY) (tergantung DATEFIRST sesi) menjadi 1 = Senin ... 7 = Minggu,
    -- tahan berapa pun nilai DATEFIRST yang aktif.
    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @PlanDate) + @@DATEFIRST - 2) % 7) + 1;

    -- (1) Divisi: prefill dari work_schedule_defaults/divisions.default_target_per_person
    -- HANYA dipakai bila belum ada baris tersimpan (ddp.daily_division_plan_id IS NULL).
    -- Headcount TIDAK pernah diprefill -- PPIC wajib mengisi setiap hari.
    SELECT
        d.division_id AS DivisionId,
        d.division_name AS DivisionName,
        d.dashboard_mode AS DashboardMode,
        d.default_target_per_person AS DefaultTargetPerPerson,
        CAST(CASE WHEN ddp.daily_division_plan_id IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSaved,
        ddp.daily_division_plan_id AS DailyDivisionPlanId,
        ISNULL(ddp.is_holiday, CAST(CASE WHEN wsd.is_working_day = 0 THEN 1 ELSE 0 END AS BIT)) AS IsHoliday,
        COALESCE(ddp.start_time, wsd.start_time) AS StartTime,
        COALESCE(ddp.end_time, wsd.end_time) AS EndTime,
        ddp.headcount AS Headcount,
        COALESCE(ddp.target_per_person, d.default_target_per_person) AS TargetPerPerson,
        ddp.remark AS Remark,
        ddp.updated_at AS UpdatedAt,
        u.FullName AS SavedByName
    FROM divisions d
    LEFT JOIN daily_division_plans ddp
        ON ddp.division_id = d.division_id AND ddp.plan_date = @PlanDate AND ddp.deleted_at IS NULL
    LEFT JOIN work_schedule_defaults wsd
        ON wsd.division_id = d.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
    LEFT JOIN Users u ON u.Id = COALESCE(ddp.updated_by, ddp.created_by)
    WHERE d.deleted_at IS NULL AND d.show_in_dashboard = 1
    ORDER BY d.dashboard_sort_order ASC, d.division_name ASC;

    -- (2) Resource untuk divisi bermode RESOURCE: seluruh resource hidup + aktif + ikut
    -- dashboard milik divisi tersebut, bukan hanya yang sudah tersimpan. Filter deleted_at
    -- untuk daily_resource_plans ada di klausa ON, bukan WHERE, supaya resource tanpa
    -- rencana tetap muncul (LEFT JOIN).
    SELECT
        r.division_id AS DivisionId,
        r.resource_id AS ResourceId,
        r.resource_name AS ResourceName,
        drp.headcount AS Headcount,
        COALESCE(drp.target_per_person, d.default_target_per_person) AS TargetPerPerson,
        drp.start_time AS StartTime,
        drp.end_time AS EndTime,
        drp.remark AS Remark,
        CAST(CASE WHEN drp.daily_resource_plan_id IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSaved
    FROM resources r
    INNER JOIN divisions d
        ON d.division_id = r.division_id AND d.deleted_at IS NULL
       AND d.dashboard_mode = 'RESOURCE' AND d.show_in_dashboard = 1
    LEFT JOIN daily_division_plans ddp
        ON ddp.division_id = r.division_id AND ddp.plan_date = @PlanDate AND ddp.deleted_at IS NULL
    LEFT JOIN daily_resource_plans drp
        ON drp.daily_division_plan_id = ddp.daily_division_plan_id AND drp.resource_id = r.resource_id AND drp.deleted_at IS NULL
    WHERE r.deleted_at IS NULL AND r.is_active = 1 AND r.include_in_dashboard = 1
    ORDER BY r.division_id ASC, r.resource_name ASC;

    -- (3) Istirahat yang berlaku pada hari itu.
    SELECT
        work_break_default_id AS Id, break_name AS BreakName, day_of_week AS DayOfWeek,
        start_time AS StartTime, end_time AS EndTime, sort_order AS SortOrder
    FROM work_break_defaults
    WHERE deleted_at IS NULL AND (day_of_week IS NULL OR day_of_week = @Dow)
    ORDER BY sort_order ASC, start_time ASC;
END;
GO

-- Ringkasan status per tanggal untuk navigasi pemilih tanggal.
CREATE OR ALTER PROCEDURE SIS_DailyPlan_ListDates
    @FromDate DATE,
    @ToDate   DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH DateRange AS (
        SELECT @FromDate AS PlanDate
        UNION ALL
        SELECT DATEADD(DAY, 1, PlanDate) FROM DateRange WHERE PlanDate < @ToDate
    )
    SELECT
        dr.PlanDate,
        (SELECT COUNT(*) FROM divisions d WHERE d.deleted_at IS NULL AND d.show_in_dashboard = 1) AS TotalDivision,
        (SELECT COUNT(*) FROM daily_division_plans ddp
            INNER JOIN divisions d ON d.division_id = ddp.division_id AND d.deleted_at IS NULL AND d.show_in_dashboard = 1
            WHERE ddp.plan_date = dr.PlanDate AND ddp.deleted_at IS NULL) AS SavedDivision,
        (SELECT COUNT(*) FROM daily_division_plans ddp
            INNER JOIN divisions d ON d.division_id = ddp.division_id AND d.deleted_at IS NULL AND d.show_in_dashboard = 1
            WHERE ddp.plan_date = dr.PlanDate AND ddp.deleted_at IS NULL AND ddp.is_holiday = 1) AS HolidayDivision
    FROM DateRange dr
    OPTION (MAXRECURSION 366);
END;
GO
