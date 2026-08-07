-- Ad hoc (lanjutan Prompt 48 thermal token render): antrian cetak KHUSUS TESTING, mirror
-- print_jobs persis. Saat TerakarsaApp.PrintService jalan dengan DryRun=true, worker
-- memanggil varian *_DryRun dari Claim/Report, dan SIS_Print_Dispatch dengan @DryRun=1 --
-- semuanya baca/tulis ke print_jobs_dryrun, BUKAN print_jobs -- supaya testing tidak pernah
-- menyentuh/mengklaim antrian cetak live. Diisi lewat SIS_PrintJobDryRun_Seed (copy satu
-- baris dari print_jobs asli; baris sumbernya di print_jobs TIDAK diubah/disentuh sama
-- sekali). Idempotent -- aman dijalankan berkali-kali.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'print_jobs_dryrun')
BEGIN
    CREATE TABLE print_jobs_dryrun(
        print_job_id int primary key identity(1,1),
        job_type varchar(30) not null,
        ref_id int not null,
        payload nvarchar(max) not null,
        [status] varchar(20) not null default 'PENDING',
        error_message varchar(500) null,
        retry_count int not null default 0,
        printed_at datetime2 null,
        print_device_id int null
            constraint FK_print_jobs_dryrun_print_devices foreign key references print_devices(print_device_id),
        created_at datetime2 not null default sysdatetime(),
        created_by int not null,
        updated_at datetime2 null,
        updated_by int null,
        deleted_at datetime2 null,
        deleted_by int null
    );
END
GO

-- Salin SATU baris dari print_jobs (job_type/ref_id/payload apa adanya, sumber TIDAK
-- diubah) ke print_jobs_dryrun sebagai baris PENDING baru -- cara utama mengisi antrian
-- testing dengan data nyata (mis. kupon borongan yang benar-benar pernah tercetak).
CREATE OR ALTER PROCEDURE SIS_PrintJobDryRun_Seed
    @PrintJobId INT,
    @UserId     INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @JobType VARCHAR(30), @RefId INT, @Payload NVARCHAR(MAX);
    SELECT @JobType = job_type, @RefId = ref_id, @Payload = payload
    FROM print_jobs WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;

    IF @JobType IS NULL
    BEGIN
        RAISERROR('Print job %d tidak ditemukan di print_jobs.', 16, 1, @PrintJobId);
        RETURN;
    END

    INSERT INTO print_jobs_dryrun (job_type, ref_id, payload, [status], created_at, created_by)
    VALUES (@JobType, @RefId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

    SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewDryRunPrintJobId;
END;
GO

-- Mirror SIS_PrintJob_RequeueStale, target print_jobs_dryrun.
CREATE OR ALTER PROCEDURE SIS_PrintJobDryRun_RequeueStale
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE print_jobs_dryrun
    SET [status] = 'PENDING',
        updated_at = SYSDATETIME()
    WHERE [status] = 'PRINTING'
      AND updated_at < DATEADD(MINUTE, -10, SYSDATETIME())
      AND deleted_at IS NULL;
END;
GO

-- Mirror SIS_PrintJob_Claim persis (termasuk resolusi print_devices lewat print_job_routes),
-- target print_jobs_dryrun. Routing config (print_job_routes/print_devices) TETAP dibagi
-- dengan jalur live -- yang dipisah cuma antrian jobnya, bukan konfigurasi printernya.
CREATE OR ALTER PROCEDURE SIS_PrintJobDryRun_Claim
    @BatchSize INT = 5,
    @JobTypesCsv NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @JobTypesCsv IS NULL OR LTRIM(RTRIM(@JobTypesCsv)) = ''
    BEGIN
        RETURN;
    END

    EXEC SIS_PrintJobDryRun_RequeueStale;

    DECLARE @Claimed TABLE (
        PrintJobId    INT,
        JobType       VARCHAR(30),
        RefId         INT,
        Payload       NVARCHAR(MAX),
        RetryCount    INT,
        PrintDeviceId INT
    );

    ;WITH cte AS (
        SELECT TOP (@BatchSize) pj.*, pjr.print_device_id AS RouteDeviceId
        FROM print_jobs_dryrun pj WITH (UPDLOCK, READPAST, ROWLOCK)
        INNER JOIN print_job_routes pjr ON pjr.job_type = pj.job_type AND pjr.deleted_at IS NULL
        INNER JOIN print_devices pd ON pd.print_device_id = pjr.print_device_id
            AND pd.deleted_at IS NULL AND pd.is_active = 1
        WHERE pj.[status] = 'PENDING' AND pj.deleted_at IS NULL
          AND pj.job_type IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@JobTypesCsv, ','))
        ORDER BY pj.created_at ASC
    )
    UPDATE cte
    SET [status] = 'PRINTING',
        print_device_id = RouteDeviceId,
        updated_at = SYSDATETIME()
    OUTPUT
        inserted.print_job_id,
        inserted.job_type,
        inserted.ref_id,
        inserted.payload,
        inserted.retry_count,
        inserted.print_device_id
    INTO @Claimed;

    SELECT
        c.PrintJobId,
        c.JobType,
        c.RefId,
        c.Payload,
        c.RetryCount,
        pd.device_code AS DeviceCode,
        pd.printer_name AS PrinterName,
        pd.render_mode AS RenderMode,
        pd.chars_per_line AS CharsPerLine,
        pd.chars_per_line_small AS CharsPerLineSmall
    FROM @Claimed c
    INNER JOIN print_devices pd ON pd.print_device_id = c.PrintDeviceId;
END;
GO

-- Mirror SIS_PrintJob_Report persis, target print_jobs_dryrun.
CREATE OR ALTER PROCEDURE SIS_PrintJobDryRun_Report
    @PrintJobId   INT,
    @Success      BIT,
    @ErrorMessage VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Success = 1
    BEGIN
        UPDATE print_jobs_dryrun
        SET [status] = 'DONE',
            printed_at = SYSDATETIME(),
            error_message = NULL,
            updated_at = SYSDATETIME()
        WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;
    END
    ELSE
    BEGIN
        DECLARE @NewRetryCount INT;

        UPDATE print_jobs_dryrun
        SET retry_count = retry_count + 1,
            @NewRetryCount = retry_count + 1,
            error_message = @ErrorMessage,
            updated_at = SYSDATETIME()
        WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;

        UPDATE print_jobs_dryrun
        SET [status] = CASE WHEN @NewRetryCount < 3 THEN 'PENDING' ELSE 'ERROR' END
        WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;
    END
END;
GO
