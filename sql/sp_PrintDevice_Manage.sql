/* =============================================================
   Device cetak + routing job_type (halaman /admin/printer, PrinterPicker, app Android).

   Prompt 88: file ini menjadi versi KANONIK SP device/routing yang dulu ada di
   sql/inv/alter_77_print_devices_mobile.sql (RegisterMobile, ListMobile, ListAll,
   PrintJobRoute_List, PrintJobRoute_Manage). JANGAN jalankan ulang alter_77 setelah file
   ini -- versi lamanya akan menimpa. SIS_PrintDevice_ByToken tetap di alter_77 (tidak berubah).

   Jalankan SETELAH sql/alter_88_print_multi_route.sql (kolom host/port/device_group).

   Jenis device (kolom transport):
     WINDOWS    -> PrintService PC, kirim lewat nama printer Windows (winspool).
     TCP        -> PrintService PC, kirim langsung socket host:port (printer jaringan).
     ANDROID_BT -> app HP (Bluetooth), didaftarkan dari HP -- di sini hanya tampil.
   ============================================================= */

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================
-- Registrasi HP sebagai device cetak (dipanggil app Android).
-- device_code dipakai sebagai identitas tetap HP itu (mis. HP-GUDANG-1).
-- Registrasi ulang MENGGANTI token (token lama langsung tidak berlaku) --
-- itu juga cara "mencabut" HP yang hilang.
-- Prompt 88: satu-satunya perubahan -- device baru diisi device_group 'LABEL_BENANG'
-- (kolom wajib). Registrasi ulang tidak menyentuh grup.
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
             transport, device_token, device_group, created_at, created_by)
        VALUES (@DeviceCode, @DeviceName, ISNULL(@PrinterName, 'Bluetooth'), 'RAW_TSPL',
                48, 64, 1, 'ANDROID_BT', @Token, 'LABEL_BENANG', SYSDATETIME(), @UserId);

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

-- Daftar device HP + job_type yang di-route ke sana.
-- Prompt 88: + Host/Port/DeviceGroup (bentuk baris sama dengan SIS_PrintDevice_ListAll,
-- keduanya dibaca ke PrintDeviceDto).
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
           d.host            AS Host,
           d.port            AS Port,
           d.device_group    AS DeviceGroup,
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

-- Semua device (PC Windows, PC Jaringan, HP) -- halaman /admin/printer.
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
           d.host            AS Host,
           d.port            AS Port,
           d.device_group    AS DeviceGroup,
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
    ORDER BY CASE d.transport WHEN 'WINDOWS' THEN 1 WHEN 'TCP' THEN 2 ELSE 3 END, d.device_name;
END;
GO

-- =============================================================
-- Prompt 88: tambah/ubah device PC + test print.
--   CREATE     -> device PC baru (WINDOWS atau TCP). HP tidak bisa dibuat di sini.
--   UPDATE     -> PC: semua field (kecuali kode). HP: hanya nama, grup, aktif.
--   TEST_PRINT -> job TEST_PRINT langsung ke device ini (print_device_id diisi, tanpa
--                 route). Hanya device PC aktif -- HP dites dari app-nya sendiri.
-- printer_name kolom NOT NULL lama: untuk TCP diisi otomatis 'TCP host:port'.
-- =============================================================
CREATE OR ALTER PROCEDURE SIS_PrintDevice_Manage
    @Action      VARCHAR(20),
    @Id          INT = NULL,
    @DeviceCode  VARCHAR(30) = NULL,
    @DeviceName  VARCHAR(150) = NULL,
    @Transport   VARCHAR(20) = NULL,
    @PrinterName VARCHAR(255) = NULL,
    @Host        VARCHAR(100) = NULL,
    @Port        INT = NULL,
    @RenderMode  VARCHAR(20) = NULL,
    @DeviceGroup VARCHAR(30) = NULL,
    @IsActive    BIT = 1,
    @UserId      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @DeviceCode  = UPPER(LTRIM(RTRIM(ISNULL(@DeviceCode, ''))));
    SET @DeviceName  = LTRIM(RTRIM(ISNULL(@DeviceName, '')));
    SET @Transport   = UPPER(LTRIM(RTRIM(ISNULL(@Transport, ''))));
    SET @PrinterName = NULLIF(LTRIM(RTRIM(ISNULL(@PrinterName, ''))), '');
    SET @Host        = NULLIF(LTRIM(RTRIM(ISNULL(@Host, ''))), '');
    SET @RenderMode  = UPPER(LTRIM(RTRIM(ISNULL(@RenderMode, ''))));
    SET @DeviceGroup = UPPER(LTRIM(RTRIM(ISNULL(@DeviceGroup, ''))));
    SET @IsActive    = ISNULL(@IsActive, 1);

    IF @Action = 'TEST_PRINT'
    BEGIN
        DECLARE @TName VARCHAR(150), @TCode VARCHAR(30), @TTransport VARCHAR(20), @TActive BIT,
                @TRender VARCHAR(20);
        SELECT @TName = device_name, @TCode = device_code, @TTransport = transport,
               @TActive = is_active, @TRender = render_mode
        FROM print_devices WHERE print_device_id = @Id AND deleted_at IS NULL;

        IF @TName IS NULL
        BEGIN
            RAISERROR('Device cetak tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @TTransport = 'ANDROID_BT'
        BEGIN
            RAISERROR('Test print HP dilakukan dari app di HP itu.', 16, 1);
            RETURN;
        END

        IF @TActive = 0
        BEGIN
            RAISERROR('Device nonaktif -- aktifkan dulu sebelum test print.', 16, 1);
            RETURN;
        END

        DECLARE @Now DATETIME2 = SYSDATETIME();
        DECLARE @TestPayload NVARCHAR(MAX) = (
            SELECT @TCode AS device_code,
                   @TName AS device_name,
                   @TRender AS render_mode,
                   @Now AS requested_at,
                   CONCAT('TEST ', @TName, ' ', FORMAT(@Now, 'dd-MM-yyyy HH:mm:ss')) AS [text]
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        INSERT INTO print_jobs (job_type, ref_id, payload, [status], print_device_id, created_at, created_by)
        VALUES ('TEST_PRINT', @Id, @TestPayload, 'PENDING', @Id, @Now, @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS NewPrintJobId;
        RETURN;
    END

    IF @Action NOT IN ('CREATE', 'UPDATE')
    BEGIN
        RAISERROR('Action "%s" tidak dikenal.', 16, 1, @Action);
        RETURN;
    END

    -- ---------- UPDATE device HP: hanya nama / grup / aktif ----------
    IF @Action = 'UPDATE'
       AND EXISTS (SELECT 1 FROM print_devices
                    WHERE print_device_id = @Id AND deleted_at IS NULL AND transport = 'ANDROID_BT')
    BEGIN
        IF @DeviceName = ''
        BEGIN
            RAISERROR('Nama device wajib diisi.', 16, 1);
            RETURN;
        END

        UPDATE print_devices
        SET device_name = @DeviceName,
            device_group = CASE WHEN @DeviceGroup = '' THEN device_group ELSE @DeviceGroup END,
            is_active = @IsActive,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE print_device_id = @Id;

        SELECT @Id AS PrintDeviceId;
        RETURN;
    END

    -- ---------- validasi device PC ----------
    IF @DeviceName = ''
    BEGIN
        RAISERROR('Nama device wajib diisi.', 16, 1);
        RETURN;
    END

    IF @Transport NOT IN ('WINDOWS', 'TCP')
    BEGIN
        RAISERROR('Tipe koneksi harus PC Windows atau PC Jaringan (TCP). HP didaftarkan dari app.', 16, 1);
        RETURN;
    END

    IF @RenderMode NOT IN ('RAW_TSPL', 'TOKEN')
    BEGIN
        RAISERROR('Render mode harus RAW_TSPL atau TOKEN.', 16, 1);
        RETURN;
    END

    IF @DeviceGroup = ''
    BEGIN
        RAISERROR('Grup device wajib diisi.', 16, 1);
        RETURN;
    END

    IF @Transport = 'WINDOWS'
    BEGIN
        IF @PrinterName IS NULL
        BEGIN
            RAISERROR('Nama printer Windows wajib diisi.', 16, 1);
            RETURN;
        END
        SET @Host = NULL;
        SET @Port = NULL;
    END
    ELSE
    BEGIN
        IF @Host IS NULL
        BEGIN
            RAISERROR('Host / IP printer jaringan wajib diisi.', 16, 1);
            RETURN;
        END
        IF @Port IS NULL OR @Port < 1 OR @Port > 65535
        BEGIN
            RAISERROR('Port printer jaringan harus 1-65535 (umumnya 9100).', 16, 1);
            RETURN;
        END
        SET @PrinterName = CONCAT('TCP ', @Host, ':', @Port);
    END

    IF @Action = 'CREATE'
    BEGIN
        IF @DeviceCode = ''
        BEGIN
            RAISERROR('Kode device wajib diisi.', 16, 1);
            RETURN;
        END

        IF EXISTS (SELECT 1 FROM print_devices WHERE device_code = @DeviceCode AND deleted_at IS NULL)
        BEGIN
            RAISERROR('Kode device "%s" sudah dipakai.', 16, 1, @DeviceCode);
            RETURN;
        END

        INSERT INTO print_devices
            (device_code, device_name, printer_name, render_mode, chars_per_line, chars_per_line_small,
             is_active, transport, host, port, device_group, created_at, created_by)
        VALUES
            (@DeviceCode, @DeviceName, @PrinterName, @RenderMode, 48, 64,
             @IsActive, @Transport, @Host, @Port, @DeviceGroup, SYSDATETIME(), @UserId);

        SELECT CAST(SCOPE_IDENTITY() AS INT) AS PrintDeviceId;
        RETURN;
    END

    -- UPDATE device PC
    IF NOT EXISTS (SELECT 1 FROM print_devices WHERE print_device_id = @Id AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Device cetak tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- Render mode menentukan format isi job (TSPL vs struk token) -- device yang masih jadi
    -- tujuan route tidak boleh berganti render mode diam-diam.
    IF EXISTS (SELECT 1 FROM print_devices WHERE print_device_id = @Id AND render_mode <> @RenderMode)
       AND EXISTS (SELECT 1 FROM print_job_routes WHERE print_device_id = @Id AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Render mode tidak bisa diganti selama device masih jadi tujuan routing. Lepas dulu dari routing.', 16, 1);
        RETURN;
    END

    UPDATE print_devices
    SET device_name = @DeviceName,
        transport = @Transport,
        printer_name = @PrinterName,
        host = @Host,
        port = @Port,
        render_mode = @RenderMode,
        device_group = @DeviceGroup,
        is_active = @IsActive,
        updated_at = SYSDATETIME(),
        updated_by = @UserId
    WHERE print_device_id = @Id;

    SELECT @Id AS PrintDeviceId;
END;
GO

-- Prompt 88: device aktif yang menjadi tujuan route job type tsb -- isi dropdown
-- PrinterPicker (0 = belum ada printer, 1 = otomatis, >1 = user memilih).
CREATE OR ALTER PROCEDURE SIS_PrintDevice_ListForJobType
    @JobType VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT d.print_device_id AS PrintDeviceId,
           d.device_name     AS DeviceName,
           d.device_group    AS DeviceGroup,
           d.transport       AS Transport
    FROM print_job_routes r
    INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
        AND d.deleted_at IS NULL AND d.is_active = 1
    WHERE r.job_type = @JobType AND r.deleted_at IS NULL
    ORDER BY d.device_name;
END;
GO

-- Daftar route (satu baris per job_type x device) + hitungan antrian per job_type
-- (diulang di tiap baris job_type yang sama; halaman admin mengelompokkan per job_type).
-- Prompt 88: + DeviceGroup dan hitungan job PENDING yang TIDAK BISA diklaim (lihat
-- SIS_PrintJob_Claim):
--   TertahanNonaktif    -- device pilihan job nonaktif / dihapus.
--   TertahanBukanRoute  -- device pilihan job aktif tapi sudah dilepas dari routing.
--   TertahanTanpaPilihan-- job tanpa device sementara job type punya >1 route aktif.
CREATE OR ALTER PROCEDURE SIS_PrintJobRoute_List
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH active_routes AS (
        SELECT r.job_type, COUNT(*) AS jumlah
        FROM print_job_routes r
        INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
            AND d.deleted_at IS NULL AND d.is_active = 1
        WHERE r.deleted_at IS NULL
        GROUP BY r.job_type
    ),
    antrian AS (
        SELECT j.job_type,
               COUNT(*) AS JobMenunggu,
               SUM(CASE WHEN j.print_device_id IS NOT NULL
                         AND (d.print_device_id IS NULL OR d.deleted_at IS NOT NULL OR d.is_active = 0)
                        THEN 1 ELSE 0 END) AS TertahanNonaktif,
               -- Subquery tidak boleh di dalam SUM() -- route device job dicek lewat LEFT JOIN
               -- (unique job_type + device, jadi maksimal satu baris, tidak menggandakan job).
               SUM(CASE WHEN j.print_device_id IS NOT NULL
                         AND d.deleted_at IS NULL AND d.is_active = 1
                         AND jr.print_job_route_id IS NULL
                        THEN 1 ELSE 0 END) AS TertahanBukanRoute,
               SUM(CASE WHEN j.print_device_id IS NULL AND ISNULL(ar.jumlah, 0) > 1
                        THEN 1 ELSE 0 END) AS TertahanTanpaPilihan
        FROM print_jobs j
        LEFT JOIN print_devices d ON d.print_device_id = j.print_device_id
        LEFT JOIN active_routes ar ON ar.job_type = j.job_type
        LEFT JOIN print_job_routes jr ON jr.job_type = j.job_type
            AND jr.print_device_id = j.print_device_id
            AND jr.deleted_at IS NULL
        WHERE j.[status] = 'PENDING' AND j.deleted_at IS NULL
        GROUP BY j.job_type
    )
    SELECT r.print_job_route_id AS RouteId,
           r.job_type           AS JobType,
           r.print_device_id    AS PrintDeviceId,
           d.device_code        AS DeviceCode,
           d.device_name        AS DeviceName,
           d.transport          AS Transport,
           d.render_mode        AS RenderMode,
           d.device_group       AS DeviceGroup,
           d.is_active          AS DeviceAktif,
           ISNULL(a.JobMenunggu, 0)          AS JobMenunggu,
           ISNULL(a.TertahanNonaktif, 0)     AS TertahanNonaktif,
           ISNULL(a.TertahanBukanRoute, 0)   AS TertahanBukanRoute,
           ISNULL(a.TertahanTanpaPilihan, 0) AS TertahanTanpaPilihan
    FROM print_job_routes r
    INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
    LEFT JOIN antrian a ON a.job_type = r.job_type
    WHERE r.deleted_at IS NULL
    ORDER BY r.job_type, d.device_name;
END;
GO

-- Prompt 88: SET = jadikan daftar device tujuan job_type PERSIS @PrintDeviceIdsCsv
-- ("1,4"): route yang tidak ada di daftar di-soft-delete, yang baru di-insert. Minimal
-- satu device (job_type tanpa route akan hilang dari halaman admin).
-- Aturan:
--   * Device HP hanya untuk label TSPL (app hanya merakit TSPL).
--   * Semua device tujuan satu job_type harus render mode yang sama (format isi job
--     tidak berubah per printer) -- dan sama dengan route yang sudah ada.
--   * Device yang BARU ditambahkan harus aktif (yang sudah terpasang boleh nonaktif).
--   * Lintas grup (mis. HP Gudang untuk BUNDLE_LABEL) TIDAK diblokir -- admin memutuskan.
CREATE OR ALTER PROCEDURE SIS_PrintJobRoute_Manage
    @Action           VARCHAR(20),          -- SET
    @JobType          VARCHAR(30),
    @PrintDeviceIdsCsv VARCHAR(500) = NULL,
    @UserId           INT = NULL,
    @PrintDeviceId    INT = NULL            -- kompatibilitas API lama (satu device); diabaikan bila CSV diisi
AS
BEGIN
    SET NOCOUNT ON;

    IF NULLIF(LTRIM(RTRIM(ISNULL(@PrintDeviceIdsCsv, ''))), '') IS NULL AND @PrintDeviceId IS NOT NULL
        SET @PrintDeviceIdsCsv = CAST(@PrintDeviceId AS VARCHAR(20));

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

    DECLARE @Ids TABLE (print_device_id INT PRIMARY KEY);
    INSERT INTO @Ids (print_device_id)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT)
    FROM STRING_SPLIT(ISNULL(@PrintDeviceIdsCsv, ''), ',')
    WHERE TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM @Ids)
    BEGIN
        RAISERROR('Pilih minimal satu device tujuan.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Ids i
                LEFT JOIN print_devices d ON d.print_device_id = i.print_device_id AND d.deleted_at IS NULL
                WHERE d.print_device_id IS NULL)
    BEGIN
        RAISERROR('Device cetak tidak dikenal.', 16, 1);
        RETURN;
    END

    -- Jalur TOKEN (struk ESC/POS) tidak bisa dicetak HP Bluetooth: app hanya merakit TSPL.
    IF EXISTS (SELECT 1 FROM @Ids i
                INNER JOIN print_devices d ON d.print_device_id = i.print_device_id
                WHERE d.transport = 'ANDROID_BT' AND d.render_mode <> 'RAW_TSPL')
    BEGIN
        RAISERROR('Device HP hanya mendukung label TSPL.', 16, 1);
        RETURN;
    END

    IF (SELECT COUNT(DISTINCT d.render_mode) FROM @Ids i
         INNER JOIN print_devices d ON d.print_device_id = i.print_device_id) > 1
    BEGIN
        RAISERROR('Semua device tujuan satu job type harus render mode yang sama.', 16, 1);
        RETURN;
    END

    DECLARE @ModeLama VARCHAR(20) = (
        SELECT TOP 1 d.render_mode
        FROM print_job_routes r
        INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
        WHERE r.job_type = @JobType AND r.deleted_at IS NULL);

    DECLARE @ModeBaru VARCHAR(20) = (
        SELECT TOP 1 d.render_mode FROM @Ids i
        INNER JOIN print_devices d ON d.print_device_id = i.print_device_id);

    IF @ModeLama IS NOT NULL AND @ModeLama <> @ModeBaru
    BEGIN
        RAISERROR('Job type %s memakai render mode %s -- pilih device %s.', 16, 1, @JobType, @ModeLama, @ModeLama);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Ids i
                INNER JOIN print_devices d ON d.print_device_id = i.print_device_id
                WHERE d.is_active = 0
                  AND NOT EXISTS (SELECT 1 FROM print_job_routes r
                                   WHERE r.job_type = @JobType
                                     AND r.print_device_id = i.print_device_id
                                     AND r.deleted_at IS NULL))
    BEGIN
        RAISERROR('Device nonaktif tidak bisa ditambahkan ke routing.', 16, 1);
        RETURN;
    END

    BEGIN TRAN;
    BEGIN TRY
        UPDATE print_job_routes
        SET deleted_at = SYSDATETIME(), deleted_by = @UserId
        WHERE job_type = @JobType AND deleted_at IS NULL
          AND print_device_id NOT IN (SELECT print_device_id FROM @Ids);

        INSERT INTO print_job_routes (job_type, print_device_id, created_at, created_by)
        SELECT @JobType, i.print_device_id, SYSDATETIME(), @UserId
        FROM @Ids i
        WHERE NOT EXISTS (SELECT 1 FROM print_job_routes r
                           WHERE r.job_type = @JobType
                             AND r.print_device_id = i.print_device_id
                             AND r.deleted_at IS NULL);

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH

    SELECT @JobType AS JobType, (SELECT COUNT(*) FROM @Ids) AS JumlahDevice;
END;
GO
