-- Prompt 57: SP read untuk halaman admin "Request Unlock" (module UNLOCK_REQUEST).
-- MURNI READ -- aksi tulis (APPROVE/REJECT/CANCEL) tetap di SIS_UnlockRequest_Manage
-- (sql/sp_UnlockRequest_Manage.sql, Prompt 55) dan TIDAK diubah oleh prompt ini.
--
-- Keadaan pengajuan diturunkan dari timestamp, tidak ada kolom status:
--   PENDING  = approved_at IS NULL AND rejected_at IS NULL
--   APPROVED = approved_at IS NOT NULL
--   REJECTED = rejected_at IS NOT NULL
-- Pengajuan yang DIBATALKAN pengaju (deleted_at terisi, action CANCEL dari stasiun) TIDAK
-- pernah ditampilkan di kedua SP ini -- itu urusan stasiun, bukan meja admin.
--
-- PeriodeFinal: ada minimal satu lock item di periode gajian yang sudah final. Request begitu
-- PASTI ditolak SIS_UnlockRequest_Manage saat APPROVE (lihat guard di sana) -- dibawa ke UI
-- supaya admin tahu sebelum menekan tombol, bukan setelah kena error.
--
-- Catatan TotalQty: jumlah SEMUA kategori qty dari SNAPSHOT lock (ok + 4 reject + hilang),
-- yaitu total pcs yang dibekukan lock itu -- bukan cuma qty_ok. Sengaja dari snapshot, bukan
-- dari baris log sekarang, supaya angka di daftar tidak berubah kalau baris sudah dibuka &
-- diedit.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_UnlockRequest_List
    @State      VARCHAR(10) = 'PENDING',   -- PENDING (default) / APPROVED / REJECTED / ALL
    @DivisionId INT = NULL,
    @DateFrom   DATE = NULL,               -- filter atas ur.created_at (waktu ajukan), inklusif
    @DateTo     DATE = NULL                -- inklusif (seluruh hari)
AS
BEGIN
    SET NOCOUNT ON;

    IF @State IS NULL SET @State = 'PENDING';
    SET @State = UPPER(LTRIM(RTRIM(@State)));

    IF @State NOT IN ('PENDING', 'APPROVED', 'REJECTED', 'ALL')
    BEGIN
        RAISERROR('Status pengajuan tidak valid.', 16, 1);
        RETURN;
    END

    IF @DateFrom IS NOT NULL AND @DateTo IS NOT NULL AND @DateTo < @DateFrom
    BEGIN
        RAISERROR('Rentang tanggal tidak valid.', 16, 1);
        RETURN;
    END

    SELECT ur.request_id AS RequestId,
           ur.created_at AS CreatedAt,
           ur.division_id AS DivisionId,
           d.division_name AS DivisionName,
           s.station_name AS StationName,
           rr.resource_name AS RequestedByResourceName,
           ur.reason AS Reason,
           ISNULL(agg.JumlahBaris, 0) AS JumlahBaris,
           ISNULL(agg.TotalQty, 0) AS TotalQty,
           CASE WHEN ur.approved_at IS NOT NULL THEN 'APPROVED'
                WHEN ur.rejected_at IS NOT NULL THEN 'REJECTED'
                ELSE 'PENDING' END AS State,
           COALESCE(ur.approved_at, ur.rejected_at) AS DecidedAt,
           du.FullName AS DecidedByName,
           ur.admin_note AS AdminNote,
           CAST(ISNULL(agg.PeriodeFinalFlag, 0) AS BIT) AS PeriodeFinal
    FROM unlock_requests ur
    INNER JOIN divisions d ON d.division_id = ur.division_id
    LEFT JOIN stations s ON s.station_id = ur.station_id
    LEFT JOIN resources rr ON rr.resource_id = ur.requested_by_resource_id
    LEFT JOIN Users du ON du.Id = COALESCE(ur.approved_by, ur.rejected_by)
    OUTER APPLY (
        SELECT COUNT(*) AS JumlahBaris,
               SUM(wli.snap_qty_ok + wli.snap_qty_reject_print + wli.snap_qty_reject_fabric
                   + wli.snap_qty_reject_sewing + wli.snap_qty_reject_rework + wli.snap_qty_lost) AS TotalQty,
               MAX(CASE WHEN pp.finalized_at IS NOT NULL THEN 1 ELSE 0 END) AS PeriodeFinalFlag
        FROM unlock_request_items uri
        INNER JOIN workflow_lock_items wli ON wli.lock_item_id = uri.lock_item_id
        INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id
        INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
        WHERE uri.request_id = ur.request_id
    ) agg
    WHERE ur.deleted_at IS NULL
      AND (@DivisionId IS NULL OR ur.division_id = @DivisionId)
      AND (@DateFrom IS NULL OR CAST(ur.created_at AS DATE) >= @DateFrom)
      AND (@DateTo IS NULL OR CAST(ur.created_at AS DATE) <= @DateTo)
      AND (
            @State = 'ALL'
            OR (@State = 'PENDING' AND ur.approved_at IS NULL AND ur.rejected_at IS NULL)
            OR (@State = 'APPROVED' AND ur.approved_at IS NOT NULL)
            OR (@State = 'REJECTED' AND ur.rejected_at IS NOT NULL)
          )
    -- Menunggu selalu di atas dan TERLAMA dulu (paling lama bikin stasiun menganggur);
    -- sisanya terbaru dulu. Ekspresi tengah NULL untuk baris yang sudah diputus, jadi
    -- urutan mereka jatuh ke created_at DESC.
    ORDER BY CASE WHEN ur.approved_at IS NULL AND ur.rejected_at IS NULL THEN 0 ELSE 1 END,
             CASE WHEN ur.approved_at IS NULL AND ur.rejected_at IS NULL THEN ur.created_at END ASC,
             ur.created_at DESC;
END;
GO

-- ---------------------------------------------------------------------------
-- SIS_UnlockRequest_Detail -- 2 result set:
--   1) header (bentuk sama dengan SIS_UnlockRequest_List, satu baris)
--   2) baris/item: identitas baris log + Sebelum (snapshot lock) vs Sekarang (nilai terkini)
--      + LockUlang (lock aktif BARU, kalau baris sudah di-lock lagi setelah dibuka).
--
-- Perbandingan Sebelum vs Sekarang memakai awl.article_size_id MENTAH (bukan COALESCE ke
-- bundles.article_size_id) -- karena itulah yang disnapshot SIS_WorkflowLock_Manage. SizeName
-- di kolom identitas tetap pakai COALESCE supaya badge ukuran baris Bundling tidak kosong.
-- ---------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE SIS_UnlockRequest_Detail
    @RequestId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM unlock_requests WHERE request_id = @RequestId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Pengajuan tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- Result 1: header.
    SELECT ur.request_id AS RequestId,
           ur.created_at AS CreatedAt,
           ur.division_id AS DivisionId,
           d.division_name AS DivisionName,
           s.station_name AS StationName,
           rr.resource_name AS RequestedByResourceName,
           ur.reason AS Reason,
           ISNULL(agg.JumlahBaris, 0) AS JumlahBaris,
           ISNULL(agg.TotalQty, 0) AS TotalQty,
           CASE WHEN ur.approved_at IS NOT NULL THEN 'APPROVED'
                WHEN ur.rejected_at IS NOT NULL THEN 'REJECTED'
                ELSE 'PENDING' END AS State,
           COALESCE(ur.approved_at, ur.rejected_at) AS DecidedAt,
           du.FullName AS DecidedByName,
           ur.admin_note AS AdminNote,
           CAST(ISNULL(agg.PeriodeFinalFlag, 0) AS BIT) AS PeriodeFinal
    FROM unlock_requests ur
    INNER JOIN divisions d ON d.division_id = ur.division_id
    LEFT JOIN stations s ON s.station_id = ur.station_id
    LEFT JOIN resources rr ON rr.resource_id = ur.requested_by_resource_id
    LEFT JOIN Users du ON du.Id = COALESCE(ur.approved_by, ur.rejected_by)
    OUTER APPLY (
        SELECT COUNT(*) AS JumlahBaris,
               SUM(wli.snap_qty_ok + wli.snap_qty_reject_print + wli.snap_qty_reject_fabric
                   + wli.snap_qty_reject_sewing + wli.snap_qty_reject_rework + wli.snap_qty_lost) AS TotalQty,
               MAX(CASE WHEN pp.finalized_at IS NOT NULL THEN 1 ELSE 0 END) AS PeriodeFinalFlag
        FROM unlock_request_items uri
        INNER JOIN workflow_lock_items wli ON wli.lock_item_id = uri.lock_item_id
        INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id
        INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
        WHERE uri.request_id = ur.request_id
    ) agg
    WHERE ur.request_id = @RequestId AND ur.deleted_at IS NULL;

    -- Result 2: baris yang diminta dibuka.
    SELECT uri.request_item_id AS RequestItemId,
           uri.workflow_log_id AS WorkflowLogId,
           p.project_name AS ProjectName, p.no_po AS NoPo,
           a.article_name AS ArticleName, a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           awl.bundle_id AS BundleId,
           b.bundle_no AS BundleNo, p.bundle_letter AS BundleLetter, b.serial AS Serial,
           spd.size_name AS SizeName,
           COALESCE(bemp.employee_name, lemp.employee_name) AS PenjahitName,
           -- Periode lock yang diminta dilepas (bukan periode "sekarang").
           pp.period_code AS PeriodeLock,
           wl.locked_at AS LockedAt,
           CAST(CASE WHEN pp.finalized_at IS NULL THEN 0 ELSE 1 END AS BIT) AS PeriodeLockFinal,

           -- Sebelum = snapshot saat di-lock.
           wli.snap_qty_ok AS SebelumQtyOk,
           wli.snap_qty_reject_print AS SebelumQtyRejectPrint,
           wli.snap_qty_reject_fabric AS SebelumQtyRejectFabric,
           wli.snap_qty_reject_sewing AS SebelumQtyRejectSewing,
           wli.snap_qty_reject_rework AS SebelumQtyRejectRework,
           wli.snap_qty_lost AS SebelumQtyLost,
           sspd.size_name AS SebelumSizeName,
           sres.resource_name AS SebelumResourceName,

           -- Sekarang = nilai terkini baris log. Baris yang sudah di-soft-delete ditandai
           -- IsDeleted (client menulis "dihapus"), nilainya tetap dibawa apa adanya.
           awl.qty_ok AS SekarangQtyOk,
           awl.qty_reject_print AS SekarangQtyRejectPrint,
           awl.qty_reject_fabric AS SekarangQtyRejectFabric,
           awl.qty_reject_sewing AS SekarangQtyRejectSewing,
           awl.qty_reject_rework AS SekarangQtyRejectRework,
           awl.qty_lost AS SekarangQtyLost,
           nspd.size_name AS SekarangSizeName,
           nres.resource_name AS SekarangResourceName,
           CAST(CASE WHEN awl.deleted_at IS NULL THEN 0 ELSE 1 END AS BIT) AS IsDeleted,

           -- LockUlang: baris sudah di-lock LAGI setelah dibuka (lock aktif sekarang bukan
           -- lock yang diminta dilepas). NULL selama request masih menunggu -- di saat itu
           -- awl.lock_id masih menunjuk lock yang sama.
           CASE WHEN awl.lock_id IS NOT NULL AND awl.lock_id <> wli.lock_id
                THEN npp.period_code END AS LockUlangPeriode,
           CASE WHEN awl.lock_id IS NOT NULL AND awl.lock_id <> wli.lock_id
                THEN nwl.locked_at END AS LockUlangLockedAt,

           -- Berubah = ada selisih antara Sekarang dan Sebelum (termasuk baris yang dihapus).
           CAST(CASE WHEN awl.deleted_at IS NOT NULL
                       OR awl.qty_ok <> wli.snap_qty_ok
                       OR awl.qty_reject_print <> wli.snap_qty_reject_print
                       OR awl.qty_reject_fabric <> wli.snap_qty_reject_fabric
                       OR awl.qty_reject_sewing <> wli.snap_qty_reject_sewing
                       OR awl.qty_reject_rework <> wli.snap_qty_reject_rework
                       OR awl.qty_lost <> wli.snap_qty_lost
                       OR ISNULL(awl.article_size_id, -1) <> ISNULL(wli.snap_article_size_id, -1)
                       OR ISNULL(awl.resource_id, -1) <> ISNULL(wli.snap_resource_id, -1)
                  THEN 1 ELSE 0 END AS BIT) AS Berubah
    FROM unlock_request_items uri
    INNER JOIN workflow_lock_items wli ON wli.lock_item_id = uri.lock_item_id
    INNER JOIN workflow_locks wl ON wl.lock_id = wli.lock_id
    INNER JOIN payroll_periods pp ON pp.payroll_period_id = wl.payroll_period_id
    INNER JOIN article_workflow_logs awl ON awl.workflow_log_id = uri.workflow_log_id
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN employees bemp ON bemp.employee_id = b.employee_id
    LEFT JOIN employees lemp ON lemp.employee_id = awl.employee_id
    -- Ukuran untuk kolom identitas (baris Bundling ambil dari bundle).
    LEFT JOIN article_sizes asz ON asz.article_size_id = COALESCE(b.article_size_id, awl.article_size_id)
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    -- Ukuran Sebelum / Sekarang -- MENTAH, sesuai yang disnapshot.
    LEFT JOIN article_sizes sasz ON sasz.article_size_id = wli.snap_article_size_id
    LEFT JOIN size_pack_details sspd ON sspd.size_pack_detail_id = sasz.size_pack_detail_id
    LEFT JOIN article_sizes nasz ON nasz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details nspd ON nspd.size_pack_detail_id = nasz.size_pack_detail_id
    LEFT JOIN resources sres ON sres.resource_id = wli.snap_resource_id
    LEFT JOIN resources nres ON nres.resource_id = awl.resource_id
    -- Lock aktif sekarang (untuk LockUlang).
    LEFT JOIN workflow_locks nwl ON nwl.lock_id = awl.lock_id
    LEFT JOIN payroll_periods npp ON npp.payroll_period_id = nwl.payroll_period_id
    WHERE uri.request_id = @RequestId
    ORDER BY p.project_name, a.article_name, aw.sort_order, b.bundle_no, spd.sort_order, uri.request_item_id;
END;
GO
