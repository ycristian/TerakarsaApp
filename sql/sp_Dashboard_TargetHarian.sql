-- Prompt 38 -- Dashboard Target Harian: agregasi READ-ONLY (tidak ada INSERT/UPDATE/DELETE
-- ke tabel mana pun) untuk layar TV. Basis Qty Ok/Reject SELALU created_at (bukan
-- received_at) -- lihat CLAUDE.md soal model log 1 baris per divisi: baris dibuat saat
-- divisi itu SENDIRI selesai/serah, article_workflow_logs.division_id = divisi pelaksana.
-- WIP memakai ulang SIS_Report_DivisionWipTotals (sql/sp_Report_DivisionWip.sql) --
-- definisi WIP TIDAK diduplikasi di sini. Transit (belum diterima, per divisi tujuan,
-- Prompt 39) memakai ulang SIS_Report_DivisionTransitTotals dengan pola sama; hanya
-- tampil di kartu divisi (result set 2), TIDAK di result set 3 (resource/line).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Menit efektif antara @StartTime dan @EndTime pada @PlanDate, dikurangi total irisan
-- dengan seluruh rentang work_break_defaults yang berlaku hari itu (day_of_week NULL =
-- semua hari). NULL bila jam tidak valid (salah satu NULL, atau end <= start).
CREATE OR ALTER FUNCTION fn_EffectiveMinutes(@StartTime TIME(0), @EndTime TIME(0), @PlanDate DATE)
RETURNS INT
AS
BEGIN
    IF @StartTime IS NULL OR @EndTime IS NULL OR @EndTime <= @StartTime
        RETURN NULL;

    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @PlanDate) + @@DATEFIRST - 2) % 7) + 1;
    DECLARE @BreakMinutes INT;

    SELECT @BreakMinutes = SUM(
        CASE WHEN DATEDIFF(MINUTE,
                    IIF(start_time > @StartTime, start_time, @StartTime),
                    IIF(end_time < @EndTime, end_time, @EndTime)) > 0
             THEN DATEDIFF(MINUTE,
                    IIF(start_time > @StartTime, start_time, @StartTime),
                    IIF(end_time < @EndTime, end_time, @EndTime))
             ELSE 0
        END)
    FROM work_break_defaults
    WHERE deleted_at IS NULL AND (day_of_week IS NULL OR day_of_week = @Dow);

    RETURN DATEDIFF(MINUTE, @StartTime, @EndTime) - ISNULL(@BreakMinutes, 0);
END;
GO

CREATE OR ALTER PROCEDURE SIS_Dashboard_TargetHarian
    @PlanDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @NowTime TIME(0) = CAST(@Now AS TIME(0));
    DECLARE @IsToday BIT = CASE WHEN @PlanDate = CAST(@Now AS DATE) THEN 1 ELSE 0 END;
    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @PlanDate) + @@DATEFIRST - 2) % 7) + 1;

    -- Qty Ok/Reject per (divisi pelaksana, resource pelaksana) -- basis created_at,
    -- dihitung sekali lalu di-LEFT JOIN (bukan sub-query berulang per baris).
    SELECT division_id AS DivisionId, resource_id AS ResourceId,
           SUM(qty_ok) AS QtyOk,
           SUM(qty_reject_print + qty_reject_fabric + qty_reject_sewing) AS QtyReject
    INTO #QtyAgg
    FROM article_workflow_logs
    WHERE deleted_at IS NULL AND CAST(created_at AS date) = @PlanDate
    GROUP BY division_id, resource_id;

    -- WIP per (divisi, resource penerima) -- pakai ulang SIS_Report_DivisionWipTotals
    -- (Prompt 22, varian ditambahkan Prompt 38), BUKAN definisi baru. TotalBundles (Prompt 45
    -- revisi): dashboard menampilkan WIP sebagai "N bundle - M pcs".
    CREATE TABLE #WipAgg (DivisionId INT, ResourceId INT NULL, TotalPcs INT, TotalBundles INT);
    INSERT INTO #WipAgg (DivisionId, ResourceId, TotalPcs, TotalBundles)
    EXEC SIS_Report_DivisionWipTotals;

    -- Transit (belum diterima) per divisi tujuan -- pakai ulang SIS_Report_DivisionTransitTotals,
    -- tidak dipecah per resource karena belum ada penerima.
    CREATE TABLE #TransitAgg (DivisionId INT, TotalPcs INT);
    INSERT INTO #TransitAgg (DivisionId, TotalPcs)
    EXEC SIS_Report_DivisionTransitTotals;

    -- ===================== Result set 1: Header =====================
    SELECT
        @PlanDate AS PlanDate,
        @Now AS ServerTime,
        (SELECT COUNT(*) FROM divisions WHERE deleted_at IS NULL AND show_in_dashboard = 1) AS TotalDivision,
        (SELECT COUNT(*) FROM daily_division_plans ddp
            INNER JOIN divisions d ON d.division_id = ddp.division_id AND d.deleted_at IS NULL AND d.show_in_dashboard = 1
            WHERE ddp.plan_date = @PlanDate AND ddp.deleted_at IS NULL) AS PlannedDivision;

    -- ===================== Result set 2: Divisi =====================
    -- Untuk mode RESOURCE, Headcount/TargetTotal adalah SUM seluruh line (daily_resource_plans);
    -- TargetPerPerson header dibiarkan NULL (tidak ada satu angka per-orang yang representatif
    -- lintas line dengan target berbeda-beda) -- keputusan desain, lihat catatan di prompt.
    ;WITH Base AS (
        SELECT
            d.division_id AS DivisionId,
            d.division_name AS DivisionName,
            d.dashboard_mode AS DashboardMode,
            d.dashboard_sort_order AS DashboardSortOrder,
            CAST(CASE WHEN ddp.daily_division_plan_id IS NULL THEN 0 ELSE 1 END AS BIT) AS HasPlan,
            ISNULL(ddp.is_holiday, CAST(0 AS BIT)) AS IsHoliday,
            COALESCE(ddp.start_time, wsd.start_time) AS StartTime,
            COALESCE(ddp.end_time, wsd.end_time) AS EndTime,
            CASE WHEN d.dashboard_mode = 'DIVISION' THEN ddp.headcount ELSE rr.Headcount END AS Headcount,
            CASE WHEN d.dashboard_mode = 'DIVISION' THEN ddp.target_per_person ELSE NULL END AS TargetPerPerson,
            CASE WHEN d.dashboard_mode = 'DIVISION' THEN ddp.target_per_person * ddp.headcount ELSE rr.TargetTotal END AS TargetTotal,
            ISNULL(qq.QtyOk, 0) AS QtyOk,
            ISNULL(qq.QtyReject, 0) AS QtyReject,
            ISNULL(ww.Wip, 0) AS Wip,
            ISNULL(ww.WipBundles, 0) AS WipBundles,
            ISNULL(tt.Transit, 0) AS Transit
        FROM divisions d
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = d.division_id AND ddp.plan_date = @PlanDate AND ddp.deleted_at IS NULL
        LEFT JOIN work_schedule_defaults wsd
            ON wsd.division_id = d.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
        OUTER APPLY (
            SELECT SUM(drp.headcount) AS Headcount, SUM(drp.headcount * drp.target_per_person) AS TargetTotal
            FROM daily_resource_plans drp
            WHERE drp.daily_division_plan_id = ddp.daily_division_plan_id AND drp.deleted_at IS NULL
        ) rr
        OUTER APPLY (
            SELECT SUM(QtyOk) AS QtyOk, SUM(QtyReject) AS QtyReject FROM #QtyAgg WHERE DivisionId = d.division_id
        ) qq
        OUTER APPLY (
            SELECT SUM(TotalPcs) AS Wip, SUM(TotalBundles) AS WipBundles FROM #WipAgg WHERE DivisionId = d.division_id
        ) ww
        OUTER APPLY (
            SELECT TotalPcs AS Transit FROM #TransitAgg WHERE DivisionId = d.division_id
        ) tt
        WHERE d.deleted_at IS NULL AND d.show_in_dashboard = 1
    ),
    Calc AS (
        SELECT *,
            dbo.fn_EffectiveMinutes(StartTime, EndTime, @PlanDate) AS EffectiveMinutesTotal,
            CASE
                WHEN StartTime IS NULL OR EndTime IS NULL THEN NULL
                WHEN @IsToday = 0 THEN dbo.fn_EffectiveMinutes(StartTime, EndTime, @PlanDate)
                WHEN @NowTime < StartTime THEN 0
                ELSE dbo.fn_EffectiveMinutes(StartTime, IIF(@NowTime < EndTime, @NowTime, EndTime), @PlanDate)
            END AS EffectiveMinutesElapsed,
            CAST(CASE WHEN TargetTotal IS NOT NULL AND TargetTotal > 0 THEN 1 ELSE 0 END AS BIT) AS HasTarget
        FROM Base
    ),
    Calc2 AS (
        SELECT *,
            CASE WHEN EffectiveMinutesTotal IS NULL OR EffectiveMinutesTotal = 0 THEN NULL
                 ELSE CAST(EffectiveMinutesElapsed AS FLOAT) / EffectiveMinutesTotal END AS ExpectedRatio
        FROM Calc
    )
    SELECT
        DivisionId, DivisionName, DashboardMode, HasPlan, IsHoliday, HasTarget,
        StartTime, EndTime, Headcount, TargetPerPerson, TargetTotal,
        QtyOk, QtyReject, Wip, WipBundles, Transit,
        EffectiveMinutesTotal, EffectiveMinutesElapsed,
        CASE WHEN HasTarget = 0 OR ExpectedRatio IS NULL THEN NULL ELSE ROUND(100.0 * ExpectedRatio, 1) END AS ExpectedPercent,
        CASE WHEN HasTarget = 0 THEN NULL ELSE ROUND(100.0 * CAST(QtyOk AS FLOAT) / TargetTotal, 1) END AS ActualPercent,
        CASE WHEN HasTarget = 0 OR ExpectedRatio IS NULL THEN NULL
             ELSE CAST(ROUND(QtyOk - (TargetTotal * ExpectedRatio), 0) AS INT) END AS DiffQty,
        CASE WHEN HasTarget = 0 OR ExpectedRatio IS NULL THEN NULL
             ELSE ROUND((100.0 * CAST(QtyOk AS FLOAT) / TargetTotal) - (100.0 * ExpectedRatio), 1) END AS DiffPercent,
        CASE WHEN HasTarget = 0 THEN NULL
             ELSE IIF(TargetTotal - QtyOk > 0, TargetTotal - QtyOk, 0) END AS RemainingQty,
        CASE WHEN Headcount IS NULL OR Headcount = 0 OR EffectiveMinutesElapsed IS NULL OR EffectiveMinutesElapsed = 0 THEN NULL
             ELSE ROUND(CAST(QtyOk AS FLOAT) / Headcount / (CAST(EffectiveMinutesElapsed AS FLOAT) / 60.0), 1) END AS OutputPerPersonPerHour
    FROM Calc2
    ORDER BY DashboardSortOrder ASC, DivisionName ASC;

    -- ===================== Result set 3: Resource (hanya divisi mode RESOURCE) =====================
    ;WITH ResBase AS (
        SELECT
            r.division_id AS DivisionId,
            r.resource_id AS ResourceId,
            r.resource_name AS ResourceName,
            CAST(CASE WHEN ddp.daily_division_plan_id IS NULL THEN 0 ELSE 1 END AS BIT) AS HasPlan,
            ISNULL(ddp.is_holiday, CAST(0 AS BIT)) AS IsHoliday,
            CAST(CASE WHEN drp.start_time IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS HasTimeOverride,
            COALESCE(drp.start_time, ddp.start_time, wsd.start_time) AS StartTime,
            COALESCE(drp.end_time, ddp.end_time, wsd.end_time) AS EndTime,
            drp.headcount AS Headcount,
            drp.target_per_person AS TargetPerPerson,
            CASE WHEN drp.headcount IS NOT NULL AND drp.target_per_person IS NOT NULL
                 THEN drp.headcount * drp.target_per_person ELSE NULL END AS TargetTotal,
            ISNULL(qq.QtyOk, 0) AS QtyOk,
            ISNULL(qq.QtyReject, 0) AS QtyReject,
            ISNULL(ww.Wip, 0) AS Wip,
            ISNULL(ww.WipBundles, 0) AS WipBundles
        FROM resources r
        INNER JOIN divisions d ON d.division_id = r.division_id AND d.deleted_at IS NULL
            AND d.dashboard_mode = 'RESOURCE' AND d.show_in_dashboard = 1
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = r.division_id AND ddp.plan_date = @PlanDate AND ddp.deleted_at IS NULL
        LEFT JOIN work_schedule_defaults wsd
            ON wsd.division_id = r.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
        LEFT JOIN daily_resource_plans drp
            ON drp.daily_division_plan_id = ddp.daily_division_plan_id AND drp.resource_id = r.resource_id AND drp.deleted_at IS NULL
        OUTER APPLY (
            SELECT QtyOk, QtyReject FROM #QtyAgg WHERE DivisionId = r.division_id AND ResourceId = r.resource_id
        ) qq
        OUTER APPLY (
            SELECT TotalPcs AS Wip, TotalBundles AS WipBundles FROM #WipAgg WHERE DivisionId = r.division_id AND ResourceId = r.resource_id
        ) ww
        WHERE r.deleted_at IS NULL AND r.is_active = 1 AND r.include_in_dashboard = 1
    ),
    ResCalc AS (
        SELECT *,
            dbo.fn_EffectiveMinutes(StartTime, EndTime, @PlanDate) AS EffectiveMinutesTotal,
            CASE
                WHEN StartTime IS NULL OR EndTime IS NULL THEN NULL
                WHEN @IsToday = 0 THEN dbo.fn_EffectiveMinutes(StartTime, EndTime, @PlanDate)
                WHEN @NowTime < StartTime THEN 0
                ELSE dbo.fn_EffectiveMinutes(StartTime, IIF(@NowTime < EndTime, @NowTime, EndTime), @PlanDate)
            END AS EffectiveMinutesElapsed,
            CAST(CASE WHEN TargetTotal IS NOT NULL AND TargetTotal > 0 THEN 1 ELSE 0 END AS BIT) AS HasTarget
        FROM ResBase
    ),
    ResCalc2 AS (
        SELECT *,
            CASE WHEN EffectiveMinutesTotal IS NULL OR EffectiveMinutesTotal = 0 THEN NULL
                 ELSE CAST(EffectiveMinutesElapsed AS FLOAT) / EffectiveMinutesTotal END AS ExpectedRatio
        FROM ResCalc
    )
    SELECT
        DivisionId, ResourceId, ResourceName, HasPlan, IsHoliday, HasTarget, HasTimeOverride,
        StartTime, EndTime, Headcount, TargetPerPerson, TargetTotal,
        QtyOk, QtyReject, Wip, WipBundles,
        EffectiveMinutesTotal, EffectiveMinutesElapsed,
        CASE WHEN HasTarget = 0 OR ExpectedRatio IS NULL THEN NULL ELSE ROUND(100.0 * ExpectedRatio, 1) END AS ExpectedPercent,
        CASE WHEN HasTarget = 0 THEN NULL ELSE ROUND(100.0 * CAST(QtyOk AS FLOAT) / TargetTotal, 1) END AS ActualPercent,
        CASE WHEN HasTarget = 0 OR ExpectedRatio IS NULL THEN NULL
             ELSE CAST(ROUND(QtyOk - (TargetTotal * ExpectedRatio), 0) AS INT) END AS DiffQty,
        CASE WHEN HasTarget = 0 OR ExpectedRatio IS NULL THEN NULL
             ELSE ROUND((100.0 * CAST(QtyOk AS FLOAT) / TargetTotal) - (100.0 * ExpectedRatio), 1) END AS DiffPercent,
        CASE WHEN HasTarget = 0 THEN NULL
             ELSE IIF(TargetTotal - QtyOk > 0, TargetTotal - QtyOk, 0) END AS RemainingQty,
        CASE WHEN Headcount IS NULL OR Headcount = 0 OR EffectiveMinutesElapsed IS NULL OR EffectiveMinutesElapsed = 0 THEN NULL
             ELSE ROUND(CAST(QtyOk AS FLOAT) / Headcount / (CAST(EffectiveMinutesElapsed AS FLOAT) / 60.0), 1) END AS OutputPerPersonPerHour
    FROM ResCalc2
    ORDER BY DivisionId ASC, ResourceName ASC;

    DROP TABLE #QtyAgg;
    DROP TABLE #WipAgg;
    DROP TABLE #TransitAgg;
END;
GO
