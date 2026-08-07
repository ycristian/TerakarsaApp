-- Mutasi/antrian print_jobs untuk TerakarsaApp.PrintService (Windows Worker Service).
-- Autentikasi service pakai header X-Print-Api-Key (lihat RequirePrintApiKeyAttribute),
-- terpisah dari JWT (user) dan X-Station-Token (perangkat stasiun).
--
-- Alur: Claim (ambil job PENDING, kunci jadi PRINTING) -> service cetak -> Report (DONE/retry/ERROR).
-- RequeueStale menangani service yang mati di tengah cetak (job nyangkut di PRINTING) --
-- dipanggil otomatis di awal Claim, jadi job seperti itu otomatis kembali antre.

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

-- Klaim atomik: ambil sampai @BatchSize job PENDING hidup, tertua dulu, kunci jadi PRINTING.
-- UPDLOCK+READPAST lewat CTE (TOP + ORDER BY di dalam CTE, UPDATE di luar) mencegah dua
-- pemanggilan bersamaan mengklaim job yang sama.
-- @JobTypesCsv: daftar job_type yang printer-nya sedang ON (dipisah koma, lihat
-- PrinterLabelOn/PrinterThermalOn di TerakarsaApp.PrintService). Job_type yang tidak ada di
-- daftar ini TIDAK PERNAH diklaim/disentuh (tetap PENDING murni) -- worker yang mengirim NULL
-- atau string kosong berarti tidak ada printer yang aktif sama sekali, jadi tidak ada yang diklaim.
--
-- Prompt 48: resolusi printer pindah ke tabel (print_job_routes -> print_devices) --
-- INNER JOIN ke keduanya di dalam CTE artinya job_type TANPA route hidup, atau route yang
-- device-nya is_active = 0, otomatis TIDAK IKUT TERPILIH sama sekali (baris tetap PENDING,
-- bukan gagal) -- job tanpa tujuan lebih baik menunggu daripada dipaksa klaim lalu error retry
-- 3x. print_devices.print_device_id dicatat ke print_jobs.print_device_id di UPDATE yang sama
-- (bukti printer mana yang benar-benar dipakai; mengubah routing langsung berlaku untuk job
-- yang masih antre). Kolom device (DeviceCode/PrinterName/RenderMode/CharsPerLine/
-- CharsPerLineSmall) diambil lewat SELECT kedua dari hasil OUTPUT (OUTPUT tidak bisa langsung
-- mengembalikan kolom tabel lain di luar print_jobs).
CREATE OR ALTER PROCEDURE SIS_PrintJob_Claim
    @BatchSize INT = 5,
    @JobTypesCsv NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @JobTypesCsv IS NULL OR LTRIM(RTRIM(@JobTypesCsv)) = ''
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

-- Lapor hasil cetak satu job. Sukses -> DONE. Gagal -> retry_count naik; masih < 3 kali
-- percobaan -> kembali PENDING (akan diklaim ulang siklus berikutnya); sudah 3 kali -> ERROR.
CREATE OR ALTER PROCEDURE SIS_PrintJob_Report
    @PrintJobId   INT,
    @Success      BIT,
    @ErrorMessage VARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
END;
GO
