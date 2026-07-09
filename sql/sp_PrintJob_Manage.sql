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
CREATE OR ALTER PROCEDURE SIS_PrintJob_Claim
    @BatchSize INT = 5
AS
BEGIN
    SET NOCOUNT ON;

    EXEC SIS_PrintJob_RequeueStale;

    ;WITH cte AS (
        SELECT TOP (@BatchSize) *
        FROM print_jobs WITH (UPDLOCK, READPAST, ROWLOCK)
        WHERE [status] = 'PENDING' AND deleted_at IS NULL
        ORDER BY created_at ASC
    )
    UPDATE cte
    SET [status] = 'PRINTING',
        updated_at = SYSDATETIME()
    OUTPUT
        inserted.print_job_id AS PrintJobId,
        inserted.job_type AS JobType,
        inserted.ref_id AS RefId,
        inserted.payload AS Payload,
        inserted.retry_count AS RetryCount;
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
