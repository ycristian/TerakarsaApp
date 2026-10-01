-- Prompt 55 -- SCRIPT GO-LIVE, dijalankan MANUAL SEKALI oleh developer saat fitur lock
-- dinyalakan. Mengunci SEMUA baris article_workflow_logs hidup yang dibuat SEBELUM @GoLiveAt,
-- supaya data historis tidak bisa lagi diubah diam-diam begitu periode gajian jadi acuan bayar.
--
-- >>> ISI @GoLiveAt DI BARIS PALING BAWAH BLOK DECLARE DI BAWAH SEBELUM MENJALANKAN. <<<
--
-- Idempotent: hanya menyentuh baris dengan lock_id IS NULL, jadi dijalankan ulang tidak
-- membuat lock ganda (paling banter membuat header baru untuk baris yang memang belum terkunci).
-- Berhenti TANPA mengunci apa pun kalau ada baris yang periodenya belum di-generate --
-- mengunci sebagian berarti sebagian data masuk periode gajian yang salah.
--
-- Prasyarat urutan: sql/alter_55_workflow_lock.sql, sql/sp_PayrollPeriod_Manage.sql,
-- sql/seed_55_payroll_periods.sql.

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ============================================================================
DECLARE @GoLiveAt DATETIME2 = NULL; -- isi, mis. '2026-10-03 10:00'
-- ============================================================================

IF @GoLiveAt IS NULL
BEGIN
    RAISERROR('@GoLiveAt masih NULL -- isi dulu variabel di baris paling atas script ini (mis. ''2026-10-03 10:00''), lalu jalankan ulang.', 16, 1);
    RETURN;
END

-- created_by lock sistem = user sistem stasiun. Dicari berdasar Username (JANGAN hardcode Id --
-- id berbeda antar environment; lihat sql/seed_station_system_user.sql).
DECLARE @StationSystemUserId INT = (SELECT TOP 1 Id FROM Users WHERE Username = 'station_system' ORDER BY Id);

IF @StationSystemUserId IS NULL
BEGIN
    RAISERROR('User sistem stasiun (Username = ''station_system'') tidak ditemukan. Jalankan sql/seed_station_system_user.sql terlebih dahulu.', 16, 1);
    RETURN;
END

-- Kandidat: baris hidup, dibuat sebelum go-live, belum punya lock.
IF OBJECT_ID('tempdb..#golive_rows') IS NOT NULL DROP TABLE #golive_rows;

SELECT awl.workflow_log_id,
       awl.division_id,
       awl.created_at,
       dbo.SIS_fn_PayrollPeriodIdAt(awl.created_at) AS payroll_period_id
INTO #golive_rows
FROM article_workflow_logs awl
WHERE awl.deleted_at IS NULL
  AND awl.lock_id IS NULL
  AND awl.created_at < @GoLiveAt;

IF NOT EXISTS (SELECT 1 FROM #golive_rows)
BEGIN
    PRINT 'Tidak ada baris yang perlu di-lock (semua baris sebelum @GoLiveAt sudah terkunci atau tidak ada data).';
    RETURN;
END

-- Berhenti kalau ada baris yang periodenya belum di-generate -- laporkan tanggalnya.
IF EXISTS (SELECT 1 FROM #golive_rows WHERE payroll_period_id IS NULL)
BEGIN
    PRINT 'GAGAL -- periode gajian belum di-generate untuk tanggal berikut (tidak ada baris yang di-lock):';

    SELECT CAST(created_at AS DATE) AS Tanggal, COUNT(*) AS JumlahBaris,
           MIN(created_at) AS PalingAwal, MAX(created_at) AS PalingAkhir
    FROM #golive_rows
    WHERE payroll_period_id IS NULL
    GROUP BY CAST(created_at AS DATE)
    ORDER BY Tanggal;

    RAISERROR('Jalankan SIS_PayrollPeriod_Manage @Action = ''GENERATE_YEAR'' untuk tahun-tahun di atas, lalu ulangi script ini.', 16, 1);
    RETURN;
END

IF OBJECT_ID('tempdb..#golive_locks') IS NOT NULL DROP TABLE #golive_locks;
CREATE TABLE #golive_locks (lock_id INT, division_id INT, payroll_period_id INT);

BEGIN TRAN;

-- Satu header workflow_locks per kelompok (division_id, periode dari created_at).
INSERT INTO workflow_locks (
    division_id, station_id, payroll_period_id, locked_by_resource_id, locked_by_name,
    locked_at, created_at, created_by
)
OUTPUT inserted.lock_id, inserted.division_id, inserted.payroll_period_id INTO #golive_locks
SELECT g.division_id, NULL, g.payroll_period_id, NULL, 'SYSTEM - GO LIVE',
       SYSDATETIME(), SYSDATETIME(), @StationSystemUserId
FROM (SELECT DISTINCT division_id, payroll_period_id FROM #golive_rows) g;

INSERT INTO workflow_lock_items (
    lock_id, workflow_log_id,
    snap_qty_ok, snap_qty_reject_print, snap_qty_reject_fabric, snap_qty_reject_sewing,
    snap_qty_reject_rework, snap_qty_lost,
    snap_article_size_id, snap_resource_id, snap_target_division_id,
    created_at, created_by
)
SELECT gl.lock_id, awl.workflow_log_id,
       awl.qty_ok, awl.qty_reject_print, awl.qty_reject_fabric, awl.qty_reject_sewing,
       awl.qty_reject_rework, awl.qty_lost,
       awl.article_size_id, awl.resource_id, awl.target_division_id,
       SYSDATETIME(), @StationSystemUserId
FROM #golive_rows g
INNER JOIN #golive_locks gl ON gl.division_id = g.division_id AND gl.payroll_period_id = g.payroll_period_id
INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = g.workflow_log_id;

UPDATE awl
SET awl.lock_id = gl.lock_id
FROM article_workflow_logs awl
INNER JOIN #golive_rows g ON g.workflow_log_id = awl.workflow_log_id
INNER JOIN #golive_locks gl ON gl.division_id = g.division_id AND gl.payroll_period_id = g.payroll_period_id;

COMMIT TRAN;

-- Ringkasan: jumlah header dan baris per divisi.
SELECT d.division_name AS Divisi,
       COUNT(DISTINCT gl.lock_id) AS JumlahHeaderLock,
       COUNT(*) AS JumlahBaris
FROM #golive_rows g
INNER JOIN #golive_locks gl ON gl.division_id = g.division_id AND gl.payroll_period_id = g.payroll_period_id
INNER JOIN divisions d ON d.division_id = g.division_id
GROUP BY d.division_name
ORDER BY d.division_name;

SELECT COUNT(DISTINCT lock_id) AS TotalHeaderLock, (SELECT COUNT(*) FROM #golive_rows) AS TotalBaris
FROM #golive_locks;

DROP TABLE #golive_rows;
DROP TABLE #golive_locks;
