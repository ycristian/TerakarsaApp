-- Ad hoc 2026-10-30 -- lock SEMUA baris OUT (article_workflow_logs) yang belum terkunci
-- sampai dengan periode gajian 2026 w43 (minggu lalu; batas 2026-10-24 10:00). Dijalankan
-- MANUAL oleh developer. Lock sebelumnya berhenti di w41, jadi yang tersapu di sini adalah
-- periode w42 + w43 (periode berjalan w44 tetap bisa diedit).
--
-- Salinan sql/lock_periode_sd_26w41.sql dengan @CutoffPeriodNo = 43 -- file baru per periode
-- supaya jejak "sampai periode mana data dibekukan" ikut tercatat di repo.
--
-- Pola sama dengan sql/golive_55_lock_existing.sql (satu header workflow_locks per
-- kelompok divisi x periode, snapshot qty ke workflow_lock_items, lalu isi
-- article_workflow_logs.lock_id), dua perbedaan:
--   1. Batas waktu TIDAK diisi tangan -- diambil dari payroll_periods.period_end periode
--      @CutoffYear/@CutoffPeriodNo, jadi tidak mungkin memotong di tengah periode.
--   2. locked_by_name = 'SYSTEM - LOCK PERIODE' supaya bisa dibedakan dari lock go-live
--      dan dari lock yang ditekan PIC di stasiun (station_id + locked_by_resource_id terisi).
--
-- Lock hanya menyangkut sisi PENGIRIM. Kolom received_* tidak tersentuh -- divisi tujuan
-- tetap bisa menerima/membatalkan penerimaan baris yang sudah di-lock.
--
-- Idempotent: hanya menyentuh baris dengan lock_id IS NULL. Dijalankan ulang tidak membuat
-- lock ganda. Untuk periode berikutnya cukup ubah @CutoffPeriodNo lalu jalankan lagi.
--
-- Prasyarat: sql/alter_55_workflow_lock.sql, sql/sp_PayrollPeriod_Manage.sql,
-- sql/seed_55_payroll_periods.sql (periode tahun ybs sudah di-generate).

-- QUOTED_IDENTIFIER/ANSI_NULLS wajib ON, di batch terpisah (SET berlaku untuk sesi):
-- tabel log punya filtered index, dan INSERT/UPDATE ke tabel dengan filtered index gagal
-- (Msg 1934) kalau QUOTED_IDENTIFIER OFF -- itu default sqlcmd/ODBC.
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ============================================================================
DECLARE @CutoffYear     SMALLINT = 2026;   -- tahun periode gajian
DECLARE @CutoffPeriodNo TINYINT  = 43;     -- periode TERAKHIR yang ikut di-lock (inklusif)
-- ============================================================================

DECLARE @CutoffAt DATETIME2, @CutoffCode VARCHAR(10);

SELECT @CutoffAt = period_end, @CutoffCode = period_code
FROM payroll_periods
WHERE period_year = @CutoffYear AND period_no = @CutoffPeriodNo AND deleted_at IS NULL;

IF @CutoffAt IS NULL
BEGIN
    RAISERROR('Periode gajian %i w%i belum di-generate. Jalankan SIS_PayrollPeriod_Manage @Action = ''GENERATE_YEAR'' dulu.', 16, 1, @CutoffYear, @CutoffPeriodNo);
    RETURN;
END

PRINT 'Batas lock: semua baris dengan created_at < ' + CONVERT(VARCHAR(19), @CutoffAt, 120)
    + ' (akhir periode ' + @CutoffCode + ').';

-- created_by lock sistem = user sistem stasiun. Dicari berdasar Username (JANGAN hardcode Id --
-- id berbeda antar environment; lihat sql/seed_station_system_user.sql).
DECLARE @StationSystemUserId INT = (SELECT TOP 1 Id FROM Users WHERE Username = 'station_system' ORDER BY Id);

IF @StationSystemUserId IS NULL
BEGIN
    RAISERROR('User sistem stasiun (Username = ''station_system'') tidak ditemukan. Jalankan sql/seed_station_system_user.sql terlebih dahulu.', 16, 1);
    RETURN;
END

-- Kandidat: baris hidup, dibuat sebelum batas periode, belum punya lock.
IF OBJECT_ID('tempdb..#lock_rows') IS NOT NULL DROP TABLE #lock_rows;

SELECT awl.workflow_log_id,
       awl.division_id,
       awl.created_at,
       dbo.SIS_fn_PayrollPeriodIdAt(awl.created_at) AS payroll_period_id
INTO #lock_rows
FROM article_workflow_logs awl
WHERE awl.deleted_at IS NULL
  AND awl.lock_id IS NULL
  AND awl.created_at < @CutoffAt;

IF NOT EXISTS (SELECT 1 FROM #lock_rows)
BEGIN
    PRINT 'Tidak ada baris yang perlu di-lock (semua baris sampai periode ' + @CutoffCode + ' sudah terkunci).';
    RETURN;
END

-- Berhenti kalau ada baris yang periodenya belum di-generate -- mengunci sebagian berarti
-- sebagian data masuk periode gajian yang salah.
IF EXISTS (SELECT 1 FROM #lock_rows WHERE payroll_period_id IS NULL)
BEGIN
    PRINT 'GAGAL -- periode gajian belum di-generate untuk tanggal berikut (tidak ada baris yang di-lock):';

    SELECT CAST(created_at AS DATE) AS Tanggal, COUNT(*) AS JumlahBaris,
           MIN(created_at) AS PalingAwal, MAX(created_at) AS PalingAkhir
    FROM #lock_rows
    WHERE payroll_period_id IS NULL
    GROUP BY CAST(created_at AS DATE)
    ORDER BY Tanggal;

    RAISERROR('Jalankan SIS_PayrollPeriod_Manage @Action = ''GENERATE_YEAR'' untuk tahun-tahun di atas, lalu ulangi script ini.', 16, 1);
    RETURN;
END

-- Periode yang sudah final tidak boleh ditambah isinya lagi.
IF EXISTS (
    SELECT 1 FROM #lock_rows r
    INNER JOIN payroll_periods p ON p.payroll_period_id = r.payroll_period_id
    WHERE p.finalized_at IS NOT NULL)
BEGIN
    PRINT 'GAGAL -- ada baris yang jatuh di periode gajian yang sudah final (tidak ada baris yang di-lock):';

    SELECT p.period_code AS Periode, COUNT(*) AS JumlahBaris
    FROM #lock_rows r
    INNER JOIN payroll_periods p ON p.payroll_period_id = r.payroll_period_id
    WHERE p.finalized_at IS NOT NULL
    GROUP BY p.period_code
    ORDER BY p.period_code;

    RAISERROR('Periode di atas sudah final -- selesaikan dulu lewat jalur unlock request.', 16, 1);
    RETURN;
END

IF OBJECT_ID('tempdb..#new_locks') IS NOT NULL DROP TABLE #new_locks;
CREATE TABLE #new_locks (lock_id INT, division_id INT, payroll_period_id INT);

BEGIN TRAN;

-- Satu header workflow_locks per kelompok (division_id, periode dari created_at).
INSERT INTO workflow_locks (
    division_id, station_id, payroll_period_id, locked_by_resource_id, locked_by_name,
    locked_at, created_at, created_by
)
OUTPUT inserted.lock_id, inserted.division_id, inserted.payroll_period_id INTO #new_locks
SELECT g.division_id, NULL, g.payroll_period_id, NULL, 'SYSTEM - LOCK PERIODE',
       SYSDATETIME(), SYSDATETIME(), @StationSystemUserId
FROM (SELECT DISTINCT division_id, payroll_period_id FROM #lock_rows) g;

INSERT INTO workflow_lock_items (
    lock_id, workflow_log_id,
    snap_qty_ok, snap_qty_reject_print, snap_qty_reject_fabric, snap_qty_reject_sewing,
    snap_qty_reject_rework, snap_qty_lost,
    snap_article_size_id, snap_resource_id, snap_target_division_id,
    created_at, created_by
)
SELECT nl.lock_id, awl.workflow_log_id,
       awl.qty_ok, awl.qty_reject_print, awl.qty_reject_fabric, awl.qty_reject_sewing,
       awl.qty_reject_rework, awl.qty_lost,
       awl.article_size_id, awl.resource_id, awl.target_division_id,
       SYSDATETIME(), @StationSystemUserId
FROM #lock_rows g
INNER JOIN #new_locks nl ON nl.division_id = g.division_id AND nl.payroll_period_id = g.payroll_period_id
INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = g.workflow_log_id;

UPDATE awl
SET awl.lock_id = nl.lock_id
FROM article_workflow_logs awl
INNER JOIN #lock_rows g ON g.workflow_log_id = awl.workflow_log_id
INNER JOIN #new_locks nl ON nl.division_id = g.division_id AND nl.payroll_period_id = g.payroll_period_id;

COMMIT TRAN;

-- Ringkasan: jumlah baris per divisi x periode.
SELECT d.division_name AS Divisi, p.period_code AS Periode, COUNT(*) AS JumlahBaris
FROM #lock_rows g
INNER JOIN divisions d ON d.division_id = g.division_id
INNER JOIN payroll_periods p ON p.payroll_period_id = g.payroll_period_id
GROUP BY d.division_name, p.period_code
ORDER BY p.period_code, d.division_name;

SELECT (SELECT COUNT(*) FROM #new_locks) AS TotalHeaderLock,
       (SELECT COUNT(*) FROM #lock_rows) AS TotalBaris;

DROP TABLE #lock_rows;
DROP TABLE #new_locks;
