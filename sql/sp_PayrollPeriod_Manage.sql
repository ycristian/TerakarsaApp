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
-- Prompt 83: FINALIZE/UNFINALIZE SEKARANG ADA (sebelumnya finalized_at/finalized_by cuma
-- dibaca sebagai guard oleh SIS_WorkflowLock_Manage, SIS_UnlockRequest_Manage dan
-- SIS_NonPoOutput_Manage, tanpa satu pun SP yang mengisinya).
--
-- DUA LAPIS PEMBEKUAN yang berbeda -- jangan dicampur:
--   LOCK BARIS (Prompt 55/56) -- per BARIS, ditekan PIC di stasiun, mengisi
--     article_workflow_logs.lock_id / manual_outputs.lock_id. Membekukan QTY.
--   FINALISASI PERIODE (Prompt 83) -- per PERIODE, ditekan admin di Rekap Gajian,
--     mengisi payroll_periods.finalized_at. Membekukan HARGA (workflow_lock_items
--     .unit_price).
--
-- FINALIZE SENGAJA TIDAK ikut me-lock baris log yang belum di-lock PIC. Untuk menyapu
-- baris begitu, SP harus memilihnya berdasarkan created_at -- bertentangan dengan aturan
-- "periode gajian log = periode di workflow_locks, bukan dari created_at" dan masuk daftar
-- "di luar cakupan" Prompt 83. Konsekuensi yang dikehendaki: baris yang belum di-lock saat
-- finalisasi memang tidak ikut periode itu, dan nanti masuk periode yang dipilih PIC.

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
    -- GENERATE_YEAR (Prompt 55) / FINALIZE / UNFINALIZE (Prompt 83)
    @Action           VARCHAR(20),
    @Year             INT = NULL,   -- GENERATE_YEAR
    @PayrollPeriodId  INT = NULL,   -- FINALIZE / UNFINALIZE
    @UserId           INT = NULL
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

    -- =======================================================================
    -- FINALIZE -- "gajian periode ini sudah dibayar". Setelah ini harga lock item
    -- periode tersebut read-only (ditegakkan SIS_LockItem_UpdatePrice), lock baru ke
    -- periode itu ditolak (SIS_WorkflowLock_Manage) dan unlock request atas barisnya
    -- ditolak (SIS_UnlockRequest_Manage).
    --
    -- DITOLAK bila masih ada lock item aktif dengan unit_price IS NULL -- dan daftar
    -- baris bermasalahnya DIKEMBALIKAN sebagai result set supaya admin tahu harus
    -- memperbaiki apa (Bagian 3.5), bukan cuma pesan error.
    -- =======================================================================
    ELSE IF @Action = 'FINALIZE'
    BEGIN
        IF @UserId IS NULL
        BEGIN
            RAISERROR('User pencatat tidak dikenal.', 16, 1);
            RETURN;
        END

        DECLARE @PeriodId INT = @PayrollPeriodId;

        DECLARE @PeriodCode VARCHAR(10), @FinalizedAt DATETIME2;
        SELECT @PeriodCode = period_code, @FinalizedAt = finalized_at
        FROM payroll_periods
        WHERE payroll_period_id = @PeriodId AND deleted_at IS NULL;

        IF @PeriodCode IS NULL
        BEGIN
            RAISERROR('Periode gajian tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @FinalizedAt IS NOT NULL
        BEGIN
            RAISERROR('Periode gajian %s sudah final.', 16, 1, @PeriodCode);
            RETURN;
        END

        DECLARE @MissingCount INT = (
            SELECT COUNT(*)
            FROM workflow_lock_items wli
            INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id AND wl.deleted_at IS NULL
            WHERE wl.payroll_period_id = @PeriodId
              AND wli.released_at IS NULL AND wli.deleted_at IS NULL
              AND wli.unit_price IS NULL
        );

        IF @MissingCount > 0
        BEGIN
            -- Daftar baris bermasalah: id, source, resource, deskripsi/artikel, qty.
            SELECT wli.lock_item_id AS LockItemId,
                   wli.source       AS Source,
                   res.resource_name AS ResourceName,
                   CASE WHEN wli.source = 'MANUAL'
                        THEN mo.work_description
                        ELSE CAST(ISNULL(a.article_name, '?') + ' - ' + ISNULL(aw.step_name, '?') AS NVARCHAR(300))
                   END AS Description,
                   CASE WHEN wli.source = 'MANUAL'
                        THEN wli.snap_qty_ok
                        ELSE wli.snap_qty_ok + wli.snap_qty_reject_fabric END AS Qty
            FROM workflow_lock_items wli
            INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id AND wl.deleted_at IS NULL
            LEFT JOIN resources res ON res.resource_id = wli.snap_resource_id
            LEFT JOIN article_workflow_logs awl ON awl.workflow_log_id = wli.workflow_log_id
            LEFT JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            LEFT JOIN articles a ON a.article_id = aw.article_id
            LEFT JOIN manual_outputs mo ON mo.manual_output_id = wli.manual_output_id
            WHERE wl.payroll_period_id = @PeriodId
              AND wli.released_at IS NULL AND wli.deleted_at IS NULL
              AND wli.unit_price IS NULL
            ORDER BY wli.source DESC, res.resource_name, wli.lock_item_id;

            RAISERROR('HARGA_KOSONG|%d baris di periode %s belum punya harga. Isi dulu harganya sebelum finalisasi.', 16, 1, @MissingCount, @PeriodCode);
            RETURN;
        END

        UPDATE payroll_periods
        SET finalized_at = SYSDATETIME(),
            finalized_by = @UserId,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE payroll_period_id = @PeriodId AND deleted_at IS NULL;

        SELECT @PeriodId AS PayrollPeriodId, @PeriodCode AS PeriodCode;
    END

    -- =======================================================================
    -- UNFINALIZE -- membuka periode yang salah difinalisasi. TIDAK menyentuh harga
    -- maupun lock baris: hanya mengosongkan finalized_at/finalized_by sehingga kolom
    -- harga bisa diedit lagi. Disediakan karena tanpa ini satu salah klik membuat
    -- harga periode itu read-only permanen (hanya bisa dibuka lewat SQL manual).
    -- =======================================================================
    ELSE IF @Action = 'UNFINALIZE'
    BEGIN
        IF @UserId IS NULL
        BEGIN
            RAISERROR('User pencatat tidak dikenal.', 16, 1);
            RETURN;
        END

        DECLARE @UnfPeriodCode VARCHAR(10), @UnfFinalizedAt DATETIME2;
        SELECT @UnfPeriodCode = period_code, @UnfFinalizedAt = finalized_at
        FROM payroll_periods
        WHERE payroll_period_id = @PayrollPeriodId AND deleted_at IS NULL;

        IF @UnfPeriodCode IS NULL
        BEGIN
            RAISERROR('Periode gajian tidak ditemukan.', 16, 1);
            RETURN;
        END

        IF @UnfFinalizedAt IS NULL
        BEGIN
            RAISERROR('Periode gajian %s belum final.', 16, 1, @UnfPeriodCode);
            RETURN;
        END

        UPDATE payroll_periods
        SET finalized_at = NULL,
            finalized_by = NULL,
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE payroll_period_id = @PayrollPeriodId AND deleted_at IS NULL;

        SELECT @PayrollPeriodId AS PayrollPeriodId, @UnfPeriodCode AS PeriodCode;
    END

    ELSE
    BEGIN
        RAISERROR('Action tidak valid.', 16, 1);
        RETURN;
    END
END;
GO
