/* =============================================================
   Prompt 77 -- device cetak lewat app Android (Bluetooth SPP).

   print_devices sekarang bisa berisi dua macam "printer":
     transport = 'WINDOWS'    -> TerakarsaApp.PrintService di PC (jalur lama,
                                 autentikasi X-Print-Api-Key). TIDAK BERUBAH.
     transport = 'ANDROID_BT' -> HP admin gudang (app Terakarsa), autentikasi
                                 X-Print-Device-Token per device.

   JALUR LAMA TIDAK DISENTUH: SIS_PrintJob_Claim/_Report hanya DITAMBAH parameter
   opsional @DeviceId. Tanpa @DeviceId perilakunya sama persis seperti sebelumnya.

   Idempotent; hanya ALTER TABLE ADD + CREATE OR ALTER (tanpa recreate table).
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'transport')
BEGIN
    ALTER TABLE print_devices ADD transport VARCHAR(20) NOT NULL
        CONSTRAINT DF_print_devices_transport DEFAULT 'WINDOWS';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_print_devices_transport')
    ALTER TABLE print_devices ADD CONSTRAINT CK_print_devices_transport
        CHECK (transport IN ('WINDOWS','ANDROID_BT'));
GO

-- Token per device HP. 48 karakter acak, hanya ditampilkan saat registrasi.
IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'device_token')
    ALTER TABLE print_devices ADD device_token VARCHAR(64) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'last_seen_at')
    ALTER TABLE print_devices ADD last_seen_at DATETIME2 NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
                WHERE object_id = OBJECT_ID('dbo.print_devices') AND name = 'last_seen_info')
    ALTER TABLE print_devices ADD last_seen_info VARCHAR(200) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_print_devices_token')
    CREATE UNIQUE INDEX UX_print_devices_token ON print_devices(device_token)
        WHERE deleted_at IS NULL AND device_token IS NOT NULL;
GO

-- =============================================================
-- Registrasi HP sebagai device cetak.
-- device_code dipakai sebagai identitas tetap HP itu (mis. HP-GUDANG-1).
-- Registrasi ulang MENGGANTI token (token lama langsung tidak berlaku) --
-- itu juga cara "mencabut" HP yang hilang.
-- =============================================================
CREATE OR ALTER PROCEDURE SIS_PrintDevice_RegisterMobile
    @DeviceCode  VARCHAR(30),
    @DeviceName  VARCHAR(150),
    @PrinterName VARCHAR(255) = NULL,     -- nama/MAC printer Bluetooth (informasi saja)
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @DeviceCode = UPPER(LTRIM(RTRIM(ISNULL(@DeviceCode, ''))));
    SET @DeviceName = LTRIM(RTRIM(ISNULL(@DeviceName, '')));
    SET @PrinterName = NULLIF(LTRIM(RTRIM(ISNULL(@PrinterName, ''))), '');

    IF @DeviceCode = ''
    BEGIN
        RAISERROR('Kode device wajib diisi.', 16, 1);
        RETURN;
    END

    IF @DeviceName = ''
    BEGIN
        RAISERROR('Nama device wajib diisi.', 16, 1);
        RETURN;
    END

    DECLARE @Ada INT = (SELECT print_device_id FROM print_devices
                         WHERE device_code = @DeviceCode AND deleted_at IS NULL);

    IF @Ada IS NOT NULL
       AND EXISTS (SELECT 1 FROM print_devices
                    WHERE print_device_id = @Ada AND transport <> 'ANDROID_BT')
    BEGIN
        RAISERROR('Kode device "%s" sudah dipakai printer PC -- pakai kode lain.', 16, 1, @DeviceCode);
        RETURN;
    END

    -- Token acak 48 karakter (A-Z, a-z, 0-9) dari CRYPT_GEN_RANDOM.
    DECLARE @Token VARCHAR(64) = LOWER(CONVERT(VARCHAR(64), CONVERT(BINARY(24), CRYPT_GEN_RANDOM(24)), 2));

    IF @Ada IS NULL
    BEGIN
        INSERT INTO print_devices
            (device_code, device_name, printer_name, render_mode,
             chars_per_line, chars_per_line_small, is_active,
             transport, device_token, created_at, created_by)
        VALUES (@DeviceCode, @DeviceName, ISNULL(@PrinterName, 'Bluetooth'), 'RAW_TSPL',
                48, 64, 1, 'ANDROID_BT', @Token, SYSDATETIME(), @UserId);

        SET @Ada = CAST(SCOPE_IDENTITY() AS INT);
    END
    ELSE
    BEGIN
        UPDATE print_devices
        SET device_name = @DeviceName,
            printer_name = ISNULL(@PrinterName, printer_name),
            render_mode = 'RAW_TSPL',
            transport = 'ANDROID_BT',
            device_token = @Token,
            is_active = 1,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE print_device_id = @Ada;
    END

    SELECT @Ada AS PrintDeviceId,
           @DeviceCode AS DeviceCode,
           @DeviceName AS DeviceName,
           @Token AS DeviceToken;
END;
GO

-- Daftar device HP + job_type yang di-route ke sana (halaman /admin/printer).
CREATE OR ALTER PROCEDURE SIS_PrintDevice_ListMobile
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.print_device_id AS PrintDeviceId,
           d.device_code     AS DeviceCode,
           d.device_name     AS DeviceName,
           d.printer_name    AS PrinterName,
           d.render_mode     AS RenderMode,
           d.transport       AS Transport,
           d.is_active       AS IsActive,
           d.last_seen_at    AS LastSeenAt,
           d.last_seen_info  AS LastSeenInfo,
           CASE WHEN d.device_token IS NULL THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS AdaToken,
           STUFF((SELECT ', ' + r.job_type
                  FROM print_job_routes r
                  WHERE r.print_device_id = d.print_device_id AND r.deleted_at IS NULL
                  ORDER BY r.job_type
                  FOR XML PATH('')), 1, 2, '') AS JobTypes
    FROM print_devices d
    WHERE d.deleted_at IS NULL
      AND d.transport = 'ANDROID_BT'
    ORDER BY d.device_code;
END;
GO

-- Semua device (PC + HP) untuk dropdown routing.
CREATE OR ALTER PROCEDURE SIS_PrintDevice_ListAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.print_device_id AS PrintDeviceId,
           d.device_code     AS DeviceCode,
           d.device_name     AS DeviceName,
           d.printer_name    AS PrinterName,
           d.render_mode     AS RenderMode,
           d.transport       AS Transport,
           d.is_active       AS IsActive,
           d.last_seen_at    AS LastSeenAt,
           d.last_seen_info  AS LastSeenInfo,
           CASE WHEN d.device_token IS NULL THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS AdaToken,
           STUFF((SELECT ', ' + r.job_type
                  FROM print_job_routes r
                  WHERE r.print_device_id = d.print_device_id AND r.deleted_at IS NULL
                  ORDER BY r.job_type
                  FOR XML PATH('')), 1, 2, '') AS JobTypes
    FROM print_devices d
    WHERE d.deleted_at IS NULL
    ORDER BY d.transport, d.device_code;
END;
GO

-- Daftar route + device tujuannya (tabel di halaman /admin/printer).
CREATE OR ALTER PROCEDURE SIS_PrintJobRoute_List
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.print_job_route_id AS RouteId,
           r.job_type           AS JobType,
           r.print_device_id    AS PrintDeviceId,
           d.device_code        AS DeviceCode,
           d.device_name        AS DeviceName,
           d.transport          AS Transport,
           d.render_mode        AS RenderMode,
           d.is_active          AS DeviceAktif,
           (SELECT COUNT(*) FROM print_jobs j
             WHERE j.job_type = r.job_type AND j.[status] = 'PENDING' AND j.deleted_at IS NULL)
               AS JobMenunggu
    FROM print_job_routes r
    INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
    WHERE r.deleted_at IS NULL
    ORDER BY d.transport, r.job_type;
END;
GO

-- Pindahkan satu job_type ke device lain (owner tidak perlu SQL lagi).
CREATE OR ALTER PROCEDURE SIS_PrintJobRoute_Manage
    @Action        VARCHAR(20),          -- SET
    @JobType       VARCHAR(30),
    @PrintDeviceId INT = NULL,
    @UserId        INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action <> 'SET'
    BEGIN
        RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
        RETURN;
    END

    SET @JobType = UPPER(LTRIM(RTRIM(ISNULL(@JobType, ''))));

    IF @JobType = ''
    BEGIN
        RAISERROR('Job type wajib diisi.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM print_devices
                    WHERE print_device_id = @PrintDeviceId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Device cetak tidak dikenal.', 16, 1);
        RETURN;
    END

    -- Jalur TOKEN (struk ESC/POS) tidak bisa dicetak HP Bluetooth: app hanya merakit TSPL.
    IF EXISTS (SELECT 1 FROM print_devices
                WHERE print_device_id = @PrintDeviceId
                  AND transport = 'ANDROID_BT' AND render_mode <> 'RAW_TSPL')
    BEGIN
        RAISERROR('Device HP hanya mendukung label TSPL.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM print_job_routes WHERE job_type = @JobType AND deleted_at IS NULL)
        UPDATE print_job_routes
        SET print_device_id = @PrintDeviceId,
            updated_at = SYSDATETIME(), updated_by = @UserId
        WHERE job_type = @JobType AND deleted_at IS NULL;
    ELSE
        INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
        VALUES (@JobType, @PrintDeviceId, SYSDATETIME(), @UserId);

    SELECT @JobType AS JobType, @PrintDeviceId AS PrintDeviceId;
END;
GO

-- Tukar token -> device (dipakai filter X-Print-Device-Token di API) + catat jejak.
CREATE OR ALTER PROCEDURE SIS_PrintDevice_ByToken
    @DeviceToken VARCHAR(64),
    @Info        VARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Id INT = (SELECT print_device_id FROM print_devices
                        WHERE device_token = @DeviceToken
                          AND transport = 'ANDROID_BT'
                          AND is_active = 1
                          AND deleted_at IS NULL);

    IF @Id IS NOT NULL
        UPDATE print_devices
        SET last_seen_at = SYSDATETIME(),
            last_seen_info = ISNULL(@Info, last_seen_info)
        WHERE print_device_id = @Id;

    SELECT @Id AS PrintDeviceId;
END;
GO

/* =============================================================
   Claim & Report: parameter @DeviceId OPSIONAL.

   @DeviceId NULL  -> perilaku LAMA, tidak berubah sama sekali (PrintService Windows).
   @DeviceId diisi -> hanya job yang route-nya mengarah ke device itu, dan device
                      harus is_active = 1. @JobTypesCsv boleh NULL: dengan @DeviceId,
                      route-nya sendiri sudah membatasi job mana yang boleh diambil.
   ============================================================= */
CREATE OR ALTER PROCEDURE SIS_PrintJob_Claim
    @BatchSize INT = 5,
    @JobTypesCsv NVARCHAR(500) = NULL,
    @DeviceId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Tanpa device: daftar job_type WAJIB (worker yang tidak punya printer aktif
    -- mengirim kosong -> tidak ada yang diklaim). Dengan device: route yang membatasi.
    IF @DeviceId IS NULL AND (@JobTypesCsv IS NULL OR LTRIM(RTRIM(@JobTypesCsv)) = '')
    BEGIN
        RETURN;
    END

    IF @DeviceId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM print_devices
                        WHERE print_device_id = @DeviceId AND is_active = 1 AND deleted_at IS NULL)
    BEGIN
        RETURN;
    END

    EXEC SIS_PrintJob_RequeueStale;

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
        FROM print_jobs pj WITH (UPDLOCK, READPAST, ROWLOCK)
        INNER JOIN print_job_routes pjr ON pjr.job_type = pj.job_type AND pjr.deleted_at IS NULL
        INNER JOIN print_devices pd ON pd.print_device_id = pjr.print_device_id
            AND pd.deleted_at IS NULL AND pd.is_active = 1
        WHERE pj.[status] = 'PENDING' AND pj.deleted_at IS NULL
          AND (@DeviceId IS NULL OR pjr.print_device_id = @DeviceId)
          AND (@JobTypesCsv IS NULL OR LTRIM(RTRIM(@JobTypesCsv)) = ''
               OR pj.job_type IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@JobTypesCsv, ',')))
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

    IF @DeviceId IS NOT NULL
        UPDATE print_devices SET last_seen_at = SYSDATETIME() WHERE print_device_id = @DeviceId;

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

CREATE OR ALTER PROCEDURE SIS_PrintJob_Report
    @PrintJobId   INT,
    @Success      BIT,
    @ErrorMessage VARCHAR(500) = NULL,
    @DeviceId     INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Device HP hanya boleh melapor job yang memang dirutekan ke dirinya.
    IF @DeviceId IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM print_jobs j
                        WHERE j.print_job_id = @PrintJobId
                          AND j.print_device_id = @DeviceId
                          AND j.deleted_at IS NULL)
    BEGIN
        RAISERROR('Job ini bukan milik device Anda.', 16, 1);
        RETURN;
    END

    IF @Success = 1
    BEGIN
        UPDATE print_jobs
        SET [status] = 'DONE',
            printed_at = SYSDATETIME(),
            error_message = NULL,
            updated_at = SYSDATETIME()
        WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;
    END
    ELSE
    BEGIN
        DECLARE @NewRetryCount INT;

        UPDATE print_jobs
        SET retry_count = retry_count + 1,
            @NewRetryCount = retry_count + 1,
            error_message = @ErrorMessage,
            updated_at = SYSDATETIME()
        WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;

        UPDATE print_jobs
        SET [status] = CASE WHEN @NewRetryCount < 3 THEN 'PENDING' ELSE 'ERROR' END
        WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;
    END

    IF @DeviceId IS NOT NULL
        UPDATE print_devices SET last_seen_at = SYSDATETIME() WHERE print_device_id = @DeviceId;
END;
GO
