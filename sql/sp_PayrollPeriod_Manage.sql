-- Prompt 55: periode gajian sebagai baris (payroll_periods), bukan lagi cuma rumus.
--
-- ATURAN PENOMORAN (satu-satunya definisi -- jangan bikin varian baru di SP lain):
--   Periode ke-N tahun Y BERAKHIR di Sabtu ke-N tahun Y jam 10:00.
--   period_code = 'YY-wNN' (2 digit tahun + '-w' + nomor periode 2 digit), mis. '26-w01'.
--   period_end   = Sabtu ke-N 10:00 (eksklusif)
--   period_start = period_end - 7 hari (inklusif)
--   Jumlah periode setahun = jumlah hari Sabtu di tahun itu (52 atau 53).
-- Konsekuensi yang disengaja: w01 selalu MULAI di tahun sebelumnya (26-w01 mulai
-- 27 Des 2025 10:00) dan sisa akhir Desember jatuh ke w01 tahun berikutnya (log
-- 26 Des 2026 jam 11:00 -> 27-w01). Dengan begitu periode antar tahun bersambung
-- tanpa celah maupun tumpang tindih.
--
-- Rentang ini IDENTIK dengan rumus Prompt 30 (BuildPeriods() di ReportProduksi.razor,
-- anchor Sabtu 10:00 di SIS_Report_LineTrendWeekly / DashboardService.ResolveLineDetailPeriode)
-- -- di sini hanya diberi nomor dan disimpan. Hari dalam minggu dihitung independen dari
-- @@DATEFIRST lewat pola @Dow yang sudah dipakai fn_EffectiveMinutes (1=Senin..7=Minggu,
-- Sabtu = 6).
--
-- FINALIZE/UNFINALIZE sengaja BELUM dibuat (UI finalisasi menyusul) -- kolom
-- finalized_at/finalized_by sudah ada dan sudah dibaca sebagai guard oleh
-- SIS_WorkflowLock_Manage & SIS_UnlockRequest_Manage.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Periode yang MEMUAT @At (period_start <= @At < period_end). NULL = periode untuk waktu
-- itu belum di-generate (bukan error -- pemanggil yang memutuskan bagaimana menyikapinya).
CREATE OR ALTER FUNCTION dbo.SIS_fn_PayrollPeriodIdAt(@At DATETIME2)
RETURNS INT
AS
BEGIN
    DECLARE @Id INT;

    SELECT TOP 1 @Id = payroll_period_id
    FROM payroll_periods
    WHERE deleted_at IS NULL
      AND period_start <= @At AND @At < period_end
    ORDER BY period_start ASC;

    RETURN @Id;
END;
GO

-- Prompt 56: dropdown "Periode Gajian" di modal LOCK stasiun. Rentang pilihan sengaja sempit:
-- dari satu periode SEBELUM periode yang memuat @DefaultAt sampai satu periode SETELAH periode
-- berjalan -- batas atas yang sama ditegakkan SIS_WorkflowLock_Manage (mencegah salah pilih
-- jauh ke masa depan), batas bawah cukup satu periode mundur karena @DefaultAt sendiri sudah
-- mengikuti tanggal baris yang dipilih.
-- IsDefault menandai periode yang MEMUAT @DefaultAt -- itu yang diperlihatkan terpilih di UI.
-- Periode yang sudah final tidak pernah ikut (lock ke periode final ditolak SP tulis).
CREATE OR ALTER PROCEDURE SIS_PayrollPeriod_Options
    @DefaultAt DATETIME2 = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @DefaultAt IS NULL SET @DefaultAt = SYSDATETIME();

    DECLARE @DefaultPeriodId INT = dbo.SIS_fn_PayrollPeriodIdAt(@DefaultAt);
    DECLARE @CurrentPeriodId INT = dbo.SIS_fn_PayrollPeriodIdAt(SYSDATETIME());

    DECLARE @DefaultStart DATETIME2 = (SELECT period_start FROM payroll_periods WHERE payroll_period_id = @DefaultPeriodId);
    DECLARE @CurrentEnd DATETIME2 = (SELECT period_end FROM payroll_periods WHERE payroll_period_id = @CurrentPeriodId);

    -- Periode belum di-generate untuk salah satu acuan -- jatuh balik ke periode berjalan saja
    -- (kalau itu pun tidak ada, hasilnya kosong dan UI menampilkan pesan "belum di-generate").
    IF @DefaultStart IS NULL SET @DefaultStart = @CurrentEnd;
    IF @CurrentEnd IS NULL SET @CurrentEnd = @DefaultStart;

    SELECT pp.payroll_period_id AS PayrollPeriodId,
           pp.period_code AS PeriodCode,
           pp.period_start AS PeriodStart,
           pp.period_end AS PeriodEnd,
           CAST(CASE WHEN pp.payroll_period_id = @DefaultPeriodId THEN 1 ELSE 0 END AS BIT) AS IsDefault
    FROM payroll_periods pp
    WHERE pp.deleted_at IS NULL
      AND pp.finalized_at IS NULL
      AND pp.period_end >= DATEADD(DAY, -7, @DefaultStart)
      AND pp.period_start <= @CurrentEnd
    ORDER BY pp.period_start ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_PayrollPeriod_Manage
    @Action VARCHAR(20),
    @Year   INT = NULL,
    @UserId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'GENERATE_YEAR'
    BEGIN
        IF @Year IS NULL OR @Year < 2000 OR @Year > 2200
        BEGIN
            RAISERROR('Tahun periode tidak valid.', 16, 1);
            RETURN;
        END

        IF @UserId IS NULL
        BEGIN
            RAISERROR('User pembuat tidak dikenal.', 16, 1);
            RETURN;
        END

        DECLARE @Jan1 DATE = DATEFROMPARTS(@Year, 1, 1);
        DECLARE @Dec31 DATE = DATEFROMPARTS(@Year, 12, 31);

        -- @Dow: 1=Senin .. 7=Minggu, independen @@DATEFIRST. Sabtu = 6.
        DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @Jan1) + @@DATEFIRST - 2) % 7) + 1;
        DECLARE @FirstSaturday DATE = DATEADD(DAY, (6 - @Dow + 7) % 7, @Jan1);
        DECLARE @PeriodCount INT = (DATEDIFF(DAY, @FirstSaturday, @Dec31) / 7) + 1;

        -- Aman dipanggil berulang: hanya nomor periode yang belum ada yang di-insert.
        ;WITH Nums AS (
            SELECT 1 AS N
            UNION ALL
            SELECT N + 1 FROM Nums WHERE N + 1 <= @PeriodCount
        ),
        Calc AS (
            SELECT N,
                   CAST(DATEADD(HOUR, 10, CAST(DATEADD(DAY, (N - 1) * 7, @FirstSaturday) AS DATETIME2)) AS DATETIME2) AS PeriodEnd
            FROM Nums
        )
        INSERT INTO payroll_periods (period_year, period_no, period_code, period_start, period_end, created_at, created_by)
        SELECT @Year,
               c.N,
               RIGHT(CAST(@Year AS VARCHAR(4)), 2) + '-w' + RIGHT('00' + CAST(c.N AS VARCHAR(2)), 2),
               DATEADD(DAY, -7, c.PeriodEnd),
               c.PeriodEnd,
               SYSDATETIME(),
               @UserId
        FROM Calc c
        WHERE NOT EXISTS (
            SELECT 1 FROM payroll_periods pp
            WHERE pp.period_year = @Year AND pp.period_no = c.N AND pp.deleted_at IS NULL
        )
        OPTION (MAXRECURSION 100);

        SELECT @@ROWCOUNT AS InsertedCount, @PeriodCount AS PeriodCount, @FirstSaturday AS FirstSaturday;
    END
    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO
