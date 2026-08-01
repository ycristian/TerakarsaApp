-- Pengambilan data work_schedule_defaults & work_break_defaults (Prompt 36).
-- Mutasi ada di sp_WorkScheduleDefault_Manage.sql (SIS_WorkScheduleDefault_Manage).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Dua result set: (1) divisi hidup (termasuk yang show_in_dashboard = 0), (2) baris jam
-- kerja per divisi per hari. Divisi yang belum punya baris tetap muncul di result set (1)
-- supaya bisa dilengkapi dari UI -- baris jam kerjanya sendiri baru ada setelah SAVE_DIVISION
-- pertama kali (atau lewat seed_36_work_schedule_defaults.sql).
CREATE OR ALTER PROCEDURE SIS_WorkScheduleDefault_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT division_id AS DivisionId, division_code AS DivisionCode, division_name AS DivisionName,
           show_in_dashboard AS ShowInDashboard, dashboard_mode AS DashboardMode,
           dashboard_sort_order AS DashboardSortOrder, default_target_per_person AS DefaultTargetPerPerson
    FROM divisions
    WHERE deleted_at IS NULL
    ORDER BY dashboard_sort_order ASC, division_name ASC;

    SELECT wsd.work_schedule_default_id AS Id, wsd.division_id AS DivisionId,
           wsd.day_of_week AS DayOfWeek, wsd.is_working_day AS IsWorkingDay,
           wsd.start_time AS StartTime, wsd.end_time AS EndTime
    FROM work_schedule_defaults wsd
    INNER JOIN divisions d ON d.division_id = wsd.division_id
    WHERE wsd.deleted_at IS NULL AND d.deleted_at IS NULL
    ORDER BY wsd.division_id ASC, wsd.day_of_week ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_WorkBreakDefault_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT work_break_default_id AS Id, break_name AS BreakName, day_of_week AS DayOfWeek,
           start_time AS StartTime, end_time AS EndTime, sort_order AS SortOrder
    FROM work_break_defaults
    WHERE deleted_at IS NULL
    ORDER BY sort_order ASC, start_time ASC;
END;
GO
