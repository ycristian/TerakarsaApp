-- Mutasi/antrian print_jobs untuk TerakarsaApp.PrintService (Windows Worker Service).
-- Autentikasi service pakai header X-Print-Api-Key (lihat RequirePrintApiKeyAttribute),
-- terpisah dari JWT (user) dan X-Station-Token (perangkat stasiun).
--
-- Alur: Claim (ambil job PENDING, kunci jadi PRINTING) -> service cetak -> Report (DONE/retry/ERROR).
-- RequeueStale menangani service yang mati di tengah cetak (job nyangkut di PRINTING) --
-- dipanggil otomatis di awal Claim, jadi job seperti itu otomatis kembali antre.
--
-- Prompt 88: file ini kembali jadi versi KANONIK Claim/Report (sebelumnya versi terbaru ada
-- di sql/inv/alter_77_print_devices_mobile.sql -- JANGAN jalankan ulang file alter_77 itu
-- setelah file ini, versi lamanya akan menimpa). Tambahan Prompt 88:
--   * SIS_PrintJob_ResolveDevice -- satu tempat aturan "printer tujuan saat job dibuat".
--   * Claim: print_jobs.print_device_id yang sudah diisi saat insert DIHORMATI; pemisahan
--     siapa yang boleh mengklaim (PrintService PC = WINDOWS/TCP, HP = device miliknya).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Job PRINTING yang tidak di-report lebih dari 10 menit (service mati di tengah jalan)
-- dikembalikan ke PENDING supaya diklaim ulang.
CREATE OR ALTER PROCEDURE SIS_PrintJob_RequeueStale
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE print_jobs
    SET [status] = 'PENDING',
        updated_at = SYSDATETIME()
    WHERE [status] = 'PRINTING'
      AND updated_at < DATEADD(MINUTE, -10, SYSDATETIME())
      AND deleted_at IS NULL;
END;
GO

-- Prompt 88: printer tujuan job saat DIBUAT. Dipanggil SEMUA SP yang membuat print_jobs
-- untuk jalur yang punya pilihan printer (label bundle & stiker cutting), SEBELUM transaksi
-- utama bila memungkinkan.
--
-- "Route hidup" = baris print_job_routes hidup yang device-nya hidup & aktif.
--   @RequestedDeviceId diisi -> harus salah satu route hidup job type ini -> dipakai.
--   @RequestedDeviceId NULL  -> >1 route hidup: DITOLAK 'Pilih printer tujuan.'
--                               (job tidak dibuat; tidak ada job "ngambang").
--                               1 route / 0 route: @DeviceId NULL -- perilaku lama, device
--                               diisi saat klaim (0 route = job menunggu PENDING).
--
-- Pakai THROW (bukan RAISERROR + RETURN): THROW di luar TRY menghentikan batch pemanggil,
-- jadi SP pemanggil tidak perlu memeriksa kode kembali -- di dalam TRY pemanggil, langsung
-- jatuh ke CATCH (rollback).
CREATE OR ALTER PROCEDURE SIS_PrintJob_ResolveDevice
    @JobType           VARCHAR(30),
    @RequestedDeviceId INT = NULL,
    @DeviceId          INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SET @DeviceId = NULL;

    DECLARE @Routes TABLE (print_device_id INT PRIMARY KEY);

    INSERT INTO @Routes (print_device_id)
    SELECT DISTINCT r.print_device_id
    FROM print_job_routes r
    INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
        AND d.deleted_at IS NULL AND d.is_active = 1
    WHERE r.job_type = @JobType AND r.deleted_at IS NULL;

    IF @RequestedDeviceId IS NOT NULL
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Routes WHERE print_device_id = @RequestedDeviceId)
        BEGIN
            DECLARE @Pesan NVARCHAR(400) = CONCAT(
                N'Printer yang dipilih tidak aktif atau tidak terdaftar untuk ', @JobType,
                N'. Muat ulang halaman lalu pilih printer lagi.');
            THROW 50088, @Pesan, 1;
        END

        SET @DeviceId = @RequestedDeviceId;
        RETURN;
    END

    IF (SELECT COUNT(*) FROM @Routes) > 1
        THROW 50088, N'Pilih printer tujuan.', 1;
END;
GO

-- Klaim atomik: ambil sampai @BatchSize job PENDING hidup, tertua dulu, kunci jadi PRINTING.
-- UPDLOCK+READPAST lewat CTE (TOP + ORDER BY di dalam CTE, UPDATE di luar) mencegah dua
-- pemanggilan bersamaan mengklaim job yang sama.
-- @JobTypesCsv: daftar job_type yang printer-nya sedang ON (dipisah koma, lihat
-- PrinterLabelOn/PrinterThermalOn di TerakarsaApp.PrintService). Job_type yang tidak ada di
-- daftar ini TIDAK PERNAH diklaim/disentuh (tetap PENDING murni) -- worker yang mengirim NULL
-- atau string kosong berarti tidak ada printer yang aktif sama sekali, jadi tidak ada yang diklaim.
--
-- Prompt 48: resolusi printer lewat tabel (print_job_routes -> print_devices). Kolom device
-- (DeviceCode/PrinterName/RenderMode/...) diambil lewat SELECT kedua dari hasil OUTPUT.
--
-- Prompt 77: @DeviceId OPSIONAL. NULL = PrintService PC (API key); diisi = HP Android
-- (X-Print-Device-Token) -- hanya job yang device finalnya HP itu sendiri. Dengan @DeviceId,
-- @JobTypesCsv boleh NULL (device-nya sendiri sudah membatasi).
--
-- Prompt 88: device FINAL per job:
--   * print_device_id sudah terisi (dipilih user saat cetak / test print) -> device itu.
--     Syarat: device hidup & aktif DAN masih ada di route job type tsb (TEST_PRINT
--     dikecualikan: test print sengaja tanpa route). Tidak memenuhi -> tetap PENDING
--     (bukan error) -- tampil di hitungan "tertahan" halaman admin.
--   * NULL -> satu-satunya route hidup job type tsb. >1 route hidup = data lama/anomali
--     (menunggu pilihan printer) -> tetap PENDING.
--   * PrintService PC (@DeviceId NULL) hanya mengklaim device transport WINDOWS/TCP; HP
--     hanya device miliknya. Wajib, karena satu job type kini bisa punya tujuan PC dan HP.
--   * @DeviceCodesCsv (setting DeviceCodes di appsettings PrintService): kalau diisi,
--     worker itu HANYA mengklaim job yang device finalnya ada di daftar (mis. 'LABEL_ATAS').
--     NULL/kosong = semua device PC (perilaku default).
CREATE OR ALTER PROCEDURE SIS_PrintJob_Claim
    @BatchSize      INT = 5,
    @JobTypesCsv    NVARCHAR(500) = NULL,
    @DeviceId       INT = NULL,
    @DeviceCodesCsv NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

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

    ;WITH single_route AS (
        SELECT r.job_type, MIN(r.print_device_id) AS print_device_id
        FROM print_job_routes r
        INNER JOIN print_devices d ON d.print_device_id = r.print_device_id
            AND d.deleted_at IS NULL AND d.is_active = 1
        WHERE r.deleted_at IS NULL
        GROUP BY r.job_type
        HAVING COUNT(*) = 1
    ),
    cte AS (
        SELECT TOP (@BatchSize) pj.*, pd.print_device_id AS FinalDeviceId
        FROM print_jobs pj WITH (UPDLOCK, READPAST, ROWLOCK)
        LEFT JOIN single_route sr ON sr.job_type = pj.job_type
        INNER JOIN print_devices pd ON pd.print_device_id = ISNULL(pj.print_device_id, sr.print_device_id)
            AND pd.deleted_at IS NULL AND pd.is_active = 1
        WHERE pj.[status] = 'PENDING' AND pj.deleted_at IS NULL
          AND (
                (pj.job_type = 'TEST_PRINT' AND pj.print_device_id IS NOT NULL)
             OR EXISTS (SELECT 1 FROM print_job_routes r2
                         WHERE r2.job_type = pj.job_type
                           AND r2.print_device_id = pd.print_device_id
                           AND r2.deleted_at IS NULL)
          )
          AND (
                (@DeviceId IS NULL AND pd.transport IN ('WINDOWS','TCP'))
             OR (@DeviceId IS NOT NULL AND pd.print_device_id = @DeviceId)
          )
          AND (@JobTypesCsv IS NULL OR LTRIM(RTRIM(@JobTypesCsv)) = ''
               OR pj.job_type IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@JobTypesCsv, ',')))
          AND (@DeviceCodesCsv IS NULL OR LTRIM(RTRIM(@DeviceCodesCsv)) = ''
               OR pd.device_code IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@DeviceCodesCsv, ',')))
        -- print_job_id sebagai tie-breaker: job dari satu INSERT punya created_at sama
        -- (mis. cetak kartu TNI urut size), urutan insert harus tetap terjaga.
        ORDER BY pj.created_at ASC, pj.print_job_id ASC
    )
    UPDATE cte
    SET [status] = 'PRINTING',
        print_device_id = FinalDeviceId,
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
        pd.chars_per_line_small AS CharsPerLineSmall,
        -- Prompt 88: cara kirim ke printer (WINDOWS = winspool, TCP = socket host:port).
        pd.transport AS Transport,
        pd.host AS Host,
        pd.port AS Port
    FROM @Claimed c
    INNER JOIN print_devices pd ON pd.print_device_id = c.PrintDeviceId
    ORDER BY c.PrintJobId;
END;
GO

-- Lapor hasil cetak satu job. Sukses -> DONE. Gagal -> retry_count naik; masih < 3 kali
-- percobaan -> kembali PENDING (akan diklaim ulang siklus berikutnya); sudah 3 kali -> ERROR.
-- Prompt 77: @DeviceId (HP) -- device hanya boleh melapor job yang memang miliknya.
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
