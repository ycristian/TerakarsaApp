-- Mutasi work_schedule_defaults & work_break_defaults (Prompt 36 -- setting jam kerja
-- default per divisi, dipakai untuk prefill Planning Harian PPIC di Prompt 37).
-- Pengambilan data ada di procedure terpisah: sp_WorkScheduleDefault_Select.sql.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_WorkScheduleDefault_Manage
    @Action     VARCHAR(20),
    @DivisionId INT = NULL,
    @DaysJson   NVARCHAR(MAX) = NULL,  -- JSON array: [{"dayOfWeek":1,"isWorkingDay":true,"startTime":"08:00","endTime":"20:00"}, ...]
    @Id         INT = NULL,            -- work_break_default_id, untuk SAVE_BREAK (NULL = insert) / DELETE_BREAK
    @BreakName  VARCHAR(150) = NULL,
    @DayOfWeek  TINYINT = NULL,        -- NULL = berlaku semua hari
    @StartTime  VARCHAR(8) = NULL,
    @EndTime    VARCHAR(8) = NULL,
    @SortOrder  INT = 0,
    @UserId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'SAVE_DIVISION'
    BEGIN
        IF (SELECT COUNT(*) FROM OPENJSON(@DaysJson)) <> 7
        BEGIN
            RAISERROR('Jam kerja harus lengkap untuk 7 hari (Senin s.d. Minggu).', 16, 1);
            RETURN;
        END

        IF EXISTS (
            SELECT 1 FROM OPENJSON(@DaysJson)
                WITH (
                    isWorkingDay BIT           '$.isWorkingDay',
                    startTime    VARCHAR(8)    '$.startTime',
                    endTime      VARCHAR(8)    '$.endTime'
                ) j
            WHERE j.isWorkingDay = 1 AND CAST(j.endTime AS TIME) <= CAST(j.startTime AS TIME)
        )
        BEGIN
            RAISERROR('Jam pulang harus lebih besar dari jam masuk untuk hari kerja.', 16, 1);
            RETURN;
        END

        BEGIN TRAN;
        BEGIN TRY
            -- Baris yang sudah ada (division_id, day_of_week) -> update
            UPDATE wsd
            SET wsd.is_working_day = j.isWorkingDay,
                wsd.start_time = CAST(j.startTime AS TIME),
                wsd.end_time = CAST(j.endTime AS TIME),
                wsd.updated_at = SYSDATETIME(),
                wsd.updated_by = @UserId
            FROM work_schedule_defaults wsd
            INNER JOIN OPENJSON(@DaysJson)
                WITH (
                    dayOfWeek    TINYINT       '$.dayOfWeek',
                    isWorkingDay BIT           '$.isWorkingDay',
                    startTime    VARCHAR(8)    '$.startTime',
                    endTime      VARCHAR(8)    '$.endTime'
                ) j ON j.dayOfWeek = wsd.day_of_week
            WHERE wsd.division_id = @DivisionId AND wsd.deleted_at IS NULL;

            -- Hari yang belum punya baris -> insert
            INSERT INTO work_schedule_defaults (division_id, day_of_week, is_working_day, start_time, end_time, created_at, created_by)
            SELECT @DivisionId, j.dayOfWeek, j.isWorkingDay, CAST(j.startTime AS TIME), CAST(j.endTime AS TIME), SYSDATETIME(), @UserId
            FROM OPENJSON(@DaysJson)
                WITH (
                    dayOfWeek    TINYINT       '$.dayOfWeek',
                    isWorkingDay BIT           '$.isWorkingDay',
                    startTime    VARCHAR(8)    '$.startTime',
                    endTime      VARCHAR(8)    '$.endTime'
                ) j
            WHERE NOT EXISTS (
                SELECT 1 FROM work_schedule_defaults wsd
                WHERE wsd.division_id = @DivisionId AND wsd.day_of_week = j.dayOfWeek AND wsd.deleted_at IS NULL
            );

            COMMIT TRAN;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'SAVE_BREAK'
    BEGIN
        IF CAST(@EndTime AS TIME) <= CAST(@StartTime AS TIME)
        BEGIN
            RAISERROR('Jam selesai istirahat harus lebih besar dari jam mulai.', 16, 1);
            RETURN;
        END

        IF @Id IS NULL
        BEGIN
            INSERT INTO work_break_defaults (break_name, day_of_week, start_time, end_time, sort_order, created_at, created_by)
            VALUES (@BreakName, @DayOfWeek, CAST(@StartTime AS TIME), CAST(@EndTime AS TIME), @SortOrder, SYSDATETIME(), @UserId);

            SELECT SCOPE_IDENTITY() AS NewId;
        END
        ELSE
        BEGIN
            UPDATE work_break_defaults
            SET break_name = @BreakName,
                day_of_week = @DayOfWeek,
                start_time = CAST(@StartTime AS TIME),
                end_time = CAST(@EndTime AS TIME),
                sort_order = @SortOrder,
                updated_at = SYSDATETIME(),
                updated_by = @UserId
            WHERE work_break_default_id = @Id AND deleted_at IS NULL;
        END
    END

    ELSE IF @Action = 'DELETE_BREAK'
    BEGIN
        UPDATE work_break_defaults
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId
        WHERE work_break_default_id = @Id AND deleted_at IS NULL;
    END
END;
GO
