-- Mutasi Planning Harian PPIC (Prompt 37): daily_division_plans + daily_resource_plans,
-- header + detail dalam satu transaksi. Pengambilan data ada di procedure terpisah:
-- sp_DailyPlan_Select.sql (SIS_DailyPlan_GetByDate / SIS_DailyPlan_ListDates).
-- Setting default (work_schedule_defaults/divisions.default_target_per_person, Prompt 36)
-- HANYA dipakai untuk prefill di SIS_DailyPlan_GetByDate -- SP ini tidak pernah membacanya.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_DailyPlan_Manage
    @Action          VARCHAR(20),
    @PlanDate        DATE = NULL,
    @DivisionId      INT = NULL,
    @IsHoliday       BIT = 0,
    @StartTime       TIME(0) = NULL,
    @EndTime         TIME(0) = NULL,
    @Headcount       INT = NULL,
    @TargetPerPerson INT = NULL,
    @Remark          VARCHAR(500) = NULL,
    @ResourcesJson   NVARCHAR(MAX) = NULL,  -- JSON array: [{"resourceId":1,"headcount":8,"targetPerPerson":80,"startTime":null,"endTime":null,"remark":null}, ...]
    @SourceDate      DATE = NULL,
    @TargetDate      DATE = NULL,
    @UserId          INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'SAVE'
    BEGIN
        DECLARE @DashboardMode VARCHAR(20);
        SELECT @DashboardMode = dashboard_mode FROM divisions WHERE division_id = @DivisionId AND deleted_at IS NULL;

        IF @DashboardMode IS NULL
        BEGIN
            RAISERROR('Divisi tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @IsHoliday = 0
        BEGIN
            IF @StartTime IS NULL OR @EndTime IS NULL OR @EndTime <= @StartTime
            BEGIN
                RAISERROR('Jam pulang harus lebih besar dari jam masuk.', 16, 1);
                RETURN;
            END

            IF @DashboardMode = 'DIVISION'
            BEGIN
                IF @Headcount IS NULL OR @Headcount < 0 OR @TargetPerPerson IS NULL OR @TargetPerPerson < 0
                BEGIN
                    RAISERROR('Jumlah orang dan target per orang wajib diisi dan tidak boleh negatif.', 16, 1);
                    RETURN;
                END
            END
            ELSE IF @DashboardMode = 'RESOURCE'
            BEGIN
                IF @ResourcesJson IS NULL OR NOT EXISTS (SELECT 1 FROM OPENJSON(@ResourcesJson))
                BEGIN
                    RAISERROR('Rencana per line wajib diisi minimal satu.', 16, 1);
                    RETURN;
                END

                IF EXISTS (
                    SELECT 1 FROM OPENJSON(@ResourcesJson)
                        WITH (resourceId INT '$.resourceId') j
                    WHERE NOT EXISTS (
                        SELECT 1 FROM resources r
                        WHERE r.resource_id = j.resourceId
                          AND r.division_id = @DivisionId
                          AND r.include_in_dashboard = 1
                          AND r.deleted_at IS NULL
                    )
                )
                BEGIN
                    RAISERROR('Resource bukan milik divisi ini atau tidak ikut dashboard.', 16, 1);
                    RETURN;
                END

                IF EXISTS (
                    SELECT 1 FROM OPENJSON(@ResourcesJson)
                        WITH (
                            startTime TIME(0) '$.startTime',
                            endTime   TIME(0) '$.endTime'
                        ) j
                    WHERE (j.startTime IS NULL AND j.endTime IS NOT NULL)
                       OR (j.startTime IS NOT NULL AND j.endTime IS NULL)
                       OR (j.startTime IS NOT NULL AND j.endTime IS NOT NULL AND j.endTime <= j.startTime)
                )
                BEGIN
                    RAISERROR('Jam override resource tidak lengkap atau tidak valid.', 16, 1);
                    RETURN;
                END

                IF EXISTS (
                    SELECT 1 FROM OPENJSON(@ResourcesJson)
                        WITH (headcount INT '$.headcount', targetPerPerson INT '$.targetPerPerson') j
                    WHERE j.headcount IS NULL OR j.headcount < 0 OR j.targetPerPerson IS NULL OR j.targetPerPerson < 0
                )
                BEGIN
                    RAISERROR('Jumlah orang dan target per orang wajib diisi dan tidak boleh negatif untuk semua line.', 16, 1);
                    RETURN;
                END
            END
        END

        DECLARE @PlanId INT;
        DECLARE @EffStartTime TIME(0) = CASE WHEN @IsHoliday = 1 THEN NULL ELSE @StartTime END;
        DECLARE @EffEndTime TIME(0) = CASE WHEN @IsHoliday = 1 THEN NULL ELSE @EndTime END;
        DECLARE @EffHeadcount INT = CASE WHEN @IsHoliday = 1 THEN NULL ELSE @Headcount END;
        DECLARE @EffTargetPerPerson INT = CASE WHEN @IsHoliday = 1 THEN NULL ELSE @TargetPerPerson END;

        BEGIN TRAN;
        BEGIN TRY
            SELECT @PlanId = daily_division_plan_id FROM daily_division_plans
            WHERE plan_date = @PlanDate AND division_id = @DivisionId AND deleted_at IS NULL;

            IF @PlanId IS NOT NULL
            BEGIN
                UPDATE daily_division_plans
                SET is_holiday = @IsHoliday,
                    start_time = @EffStartTime,
                    end_time = @EffEndTime,
                    headcount = @EffHeadcount,
                    target_per_person = @EffTargetPerPerson,
                    remark = @Remark,
                    updated_at = SYSDATETIME(),
                    updated_by = @UserId
                WHERE daily_division_plan_id = @PlanId;
            END
            ELSE
            BEGIN
                INSERT INTO daily_division_plans (plan_date, division_id, is_holiday, start_time, end_time, headcount, target_per_person, remark, created_at, created_by)
                VALUES (@PlanDate, @DivisionId, @IsHoliday, @EffStartTime, @EffEndTime, @EffHeadcount, @EffTargetPerPerson, @Remark, SYSDATETIME(), @UserId);

                SET @PlanId = CAST(SCOPE_IDENTITY() AS INT);
            END

            IF @IsHoliday = 1 OR @DashboardMode = 'DIVISION'
            BEGIN
                -- Libur, atau mode DIVISION (baris resource tidak relevan lagi -- bisa
                -- tersisa dari saat divisi ini masih bermode RESOURCE).
                UPDATE daily_resource_plans
                SET deleted_at = SYSDATETIME(), deleted_by = @UserId
                WHERE daily_division_plan_id = @PlanId AND deleted_at IS NULL;
            END
            ELSE -- mode RESOURCE, tidak libur
            BEGIN
                -- Baris dengan resource_id yang cocok -> update
                UPDATE drp
                SET drp.headcount = j.headcount,
                    drp.target_per_person = j.targetPerPerson,
                    drp.start_time = j.startTime,
                    drp.end_time = j.endTime,
                    drp.remark = j.remark,
                    drp.updated_at = SYSDATETIME(),
                    drp.updated_by = @UserId
                FROM daily_resource_plans drp
                INNER JOIN OPENJSON(@ResourcesJson)
                    WITH (
                        resourceId      INT           '$.resourceId',
                        headcount       INT           '$.headcount',
                        targetPerPerson INT           '$.targetPerPerson',
                        startTime       TIME(0)       '$.startTime',
                        endTime         TIME(0)       '$.endTime',
                        remark          VARCHAR(500)  '$.remark'
                    ) j ON j.resourceId = drp.resource_id
                WHERE drp.daily_division_plan_id = @PlanId AND drp.deleted_at IS NULL;

                -- Resource yang sudah tidak ada di JSON -> soft delete
                UPDATE drp
                SET drp.deleted_at = SYSDATETIME(), drp.deleted_by = @UserId
                FROM daily_resource_plans drp
                WHERE drp.daily_division_plan_id = @PlanId AND drp.deleted_at IS NULL
                  AND NOT EXISTS (
                      SELECT 1 FROM OPENJSON(@ResourcesJson) WITH (resourceId INT '$.resourceId') j
                      WHERE j.resourceId = drp.resource_id
                  );

                -- Resource baru (belum punya baris hidup) -> insert
                INSERT INTO daily_resource_plans (daily_division_plan_id, resource_id, headcount, target_per_person, start_time, end_time, remark, created_at, created_by)
                SELECT @PlanId, j.resourceId, j.headcount, j.targetPerPerson, j.startTime, j.endTime, j.remark, SYSDATETIME(), @UserId
                FROM OPENJSON(@ResourcesJson)
                    WITH (
                        resourceId      INT           '$.resourceId',
                        headcount       INT           '$.headcount',
                        targetPerPerson INT           '$.targetPerPerson',
                        startTime       TIME(0)       '$.startTime',
                        endTime         TIME(0)       '$.endTime',
                        remark          VARCHAR(500)  '$.remark'
                    ) j
                WHERE NOT EXISTS (
                    SELECT 1 FROM daily_resource_plans drp2
                    WHERE drp2.daily_division_plan_id = @PlanId AND drp2.resource_id = j.resourceId AND drp2.deleted_at IS NULL
                );
            END

            COMMIT TRAN;
            SELECT @PlanId AS NewId;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @DelPlanId INT;
            SELECT @DelPlanId = daily_division_plan_id FROM daily_division_plans
            WHERE plan_date = @PlanDate AND division_id = @DivisionId AND deleted_at IS NULL;

            IF @DelPlanId IS NOT NULL
            BEGIN
                UPDATE daily_division_plans
                SET deleted_at = SYSDATETIME(), deleted_by = @UserId
                WHERE daily_division_plan_id = @DelPlanId;

                UPDATE daily_resource_plans
                SET deleted_at = SYSDATETIME(), deleted_by = @UserId
                WHERE daily_division_plan_id = @DelPlanId AND deleted_at IS NULL;
            END

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'COPY_FROM_DATE'
    BEGIN
        BEGIN TRAN;
        BEGIN TRY
            DECLARE @Mapping TABLE (DivisionId INT, NewDailyDivisionPlanId INT);

            -- Divisi yang sudah punya rencana hidup di @TargetDate dilewati, tidak ditimpa.
            INSERT INTO daily_division_plans (plan_date, division_id, is_holiday, start_time, end_time, headcount, target_per_person, remark, created_at, created_by)
            OUTPUT INSERTED.division_id, INSERTED.daily_division_plan_id INTO @Mapping (DivisionId, NewDailyDivisionPlanId)
            SELECT @TargetDate, src.division_id, src.is_holiday, src.start_time, src.end_time, src.headcount, src.target_per_person, src.remark, SYSDATETIME(), @UserId
            FROM daily_division_plans src
            WHERE src.plan_date = @SourceDate AND src.deleted_at IS NULL
              AND NOT EXISTS (
                  SELECT 1 FROM daily_division_plans t
                  WHERE t.plan_date = @TargetDate AND t.division_id = src.division_id AND t.deleted_at IS NULL
              );

            INSERT INTO daily_resource_plans (daily_division_plan_id, resource_id, headcount, target_per_person, start_time, end_time, remark, created_at, created_by)
            SELECT m.NewDailyDivisionPlanId, drp.resource_id, drp.headcount, drp.target_per_person, drp.start_time, drp.end_time, drp.remark, SYSDATETIME(), @UserId
            FROM @Mapping m
            INNER JOIN daily_division_plans src ON src.plan_date = @SourceDate AND src.division_id = m.DivisionId AND src.deleted_at IS NULL
            INNER JOIN daily_resource_plans drp ON drp.daily_division_plan_id = src.daily_division_plan_id AND drp.deleted_at IS NULL;

            COMMIT TRAN;
            SELECT COUNT(*) AS CopiedCount FROM @Mapping;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END
END;
GO
