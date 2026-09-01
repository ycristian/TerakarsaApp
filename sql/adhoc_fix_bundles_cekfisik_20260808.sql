-- Ad-hoc: koreksi data setelah cek fisik bundle WIP di Sewing (2026-08-08).
-- Bukan stored procedure -- baca, cek preview, baru jalankan manual per bagian.
--
-- Konteks: 36 bundle WIP di Sewing (Sejak = received_at baris log Bundling,
-- Umur dihitung dari situ) dicek fisik di lapangan:
--   - Status "Gak ada"      -> bundle tidak ketemu -> Bagian A: soft delete
--     bundle + SEMUA baris article_workflow_logs milik bundle itu (bukan cuma
--     baris Bundling), alasan seragam 'Tidak ketemu di lapangan (cek fisik 2026-08-08)'.
--   - Status "Ada, ..."     -> bundle ketemu, sudah selesai dikerjakan Sewing
--     tapi belum pernah diinput -> Bagian B: INSERT baris article_workflow_logs
--     baru untuk step Sew + QC (division_id 2), qty_ok/reject sesuai catatan
--     fisik, remark = teks status apa adanya, created_at = received_at
--     (baris Bundling, "Sejak") + 1 hari. received_at pada baris baru ini
--     TETAP NULL (belum benar-benar diterima Trim) dan target_division_id
--     diisi 9 (Trim) meniru pola baris Sew+QC nyata (row 10357/10356 dicek
--     manual sebelum nulis script ini).
--
-- Semua resource_id/employee_id/article_workflow_id sudah dicek langsung ke DB
-- (bukan tebak dari nama), lihat JOIN bundles/article_workflows di bawah.

SET NOCOUNT ON;

DECLARE @ActorUserId int = 1;              -- user_id aktor koreksi manual ini
DECLARE @DeleteReason varchar(255) = N'Tidak ketemu di lapangan (cek fisik 2026-08-08)';
DECLARE @DeleteReasonLog varchar(255) = N'Bundle tidak ketemu di lapangan (cek fisik 2026-08-08)';
DECLARE @TrimDivisionId int = 9;

-- ============================================================
-- BAGIAN A -- "Gak ada": soft delete bundle + semua log-nya
-- ============================================================

DECLARE @NotFoundSerials TABLE (serial varchar(20) primary key);
INSERT INTO @NotFoundSerials (serial) VALUES
 ('B26-000289'),('B26-000728'),('B26-000013'),('B26-000017'),('B26-000045'),
 ('B26-000023'),('B26-000204'),('B26-000010'),('B26-000428'),('B26-000024'),
 ('B26-000223'),('B26-000238'),('B26-000242'),('B26-000269'),('B26-000271'),
 ('B26-000300'),('B26-000183'),('B26-000313'),('B26-000776'),('B26-001021'),
 ('B26-001022'),('B26-001028'),('B26-001097'),('B26-001180'),('B26-000256'),
 ('B26-000317'),('B26-000551'),('B26-000424'),('B26-001023');
-- 29 serial, status "Gak ada" / "Gak Ada" di hasil cek fisik.

-- --- Preview dulu sebelum jalankan UPDATE di bawah ---
-- SELECT ns.serial AS serial_dicari, b.bundle_id, b.deleted_at AS sudah_deleted
-- FROM @NotFoundSerials ns
-- LEFT JOIN bundles b ON b.serial = ns.serial
-- ORDER BY ns.serial;
-- Pastikan semua ketemu (bundle_id tidak NULL) dan belum ada yang deleted_at terisi.

UPDATE b
SET b.deleted_at = SYSDATETIME(),
    b.deleted_by = @ActorUserId,
    b.delete_reason = @DeleteReason
FROM bundles b
JOIN @NotFoundSerials ns ON ns.serial = b.serial
WHERE b.deleted_at IS NULL;

UPDATE l
SET l.deleted_at = SYSDATETIME(),
    l.deleted_by = @ActorUserId,
    l.delete_reason = @DeleteReasonLog
FROM article_workflow_logs l
JOIN bundles b ON b.bundle_id = l.bundle_id
JOIN @NotFoundSerials ns ON ns.serial = b.serial
WHERE l.deleted_at IS NULL;


-- ============================================================
-- BAGIAN B -- "Ada": input baris log Sew + QC yang belum pernah dicatat
-- ============================================================

DECLARE @FoundBundles TABLE (
    serial varchar(20) primary key,
    qty_ok int, qty_reject_print int, qty_reject_fabric int,
    qty_reject_sewing int, qty_reject_rework int, qty_lost int,
    status_note nvarchar(500)
);
INSERT INTO @FoundBundles (serial, qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost, status_note)
VALUES
 ('B26-000176', 46, 0, 13, 0, 0, 0, N'Ada, Reject Bahan 13 sisanya OK'),
 ('B26-000418', 40, 0,  0, 0, 0, 0, N'Ada, Semua OK'),
 ('B26-000426', 50, 0,  0, 0, 0, 0, N'Ada, Semua OK'),
 ('B26-000387', 60, 0,  0, 0, 0, 0, N'Ada, Semua OK'),
 ('B26-000225', 55, 0,  0, 0, 0, 0, N'Ada, Semua OK'),
 ('B26-000707', 60, 0,  0, 0, 0, 0, N'Ada, Semua OK'),
 ('B26-000332', 118, 0, 2, 1, 6, 5, N'Ada, OK 118, reject jahit 1, rework belang 6, bahan 2, hilang 5');
-- B26-000332 (B-321, qty bundle 132): angka awal di cek fisik ("OK 127,
-- reject jahit 1, rework belang 6, bahan 2") jumlahnya 136, tidak cocok qty
-- 132 -- dikoreksi user jadi OK 118 + jahit 1 + bahan 2 + rework 6 + hilang 5
-- = 132, cocok.

-- --- Preview dulu sebelum jalankan INSERT di bawah ---
-- SELECT fb.serial, b.bundle_id, b.qty AS qty_bundle,
--        fb.qty_ok + fb.qty_reject_print + fb.qty_reject_fabric + fb.qty_reject_sewing + fb.qty_reject_rework + fb.qty_lost AS qty_breakdown_total,
--        aw_sew.article_workflow_id AS sew_awf_id, b.resource_id, b.employee_id,
--        bundling_log.received_at AS sejak, DATEADD(DAY, 1, bundling_log.received_at) AS created_at_baru,
--        EXISTS (
--            SELECT 1 FROM article_workflow_logs x
--            WHERE x.bundle_id = b.bundle_id AND x.division_id = 2 AND x.deleted_at IS NULL
--        ) AS sudah_ada_log_sewing
-- FROM @FoundBundles fb
-- JOIN bundles b ON b.serial = fb.serial
-- JOIN article_workflows aw_sew ON aw_sew.article_id = b.article_id AND aw_sew.division_id = 2 AND aw_sew.deleted_at IS NULL
-- JOIN article_workflow_logs bundling_log ON bundling_log.bundle_id = b.bundle_id AND bundling_log.division_id = 7 AND bundling_log.deleted_at IS NULL
-- ORDER BY fb.serial;
-- Pastikan qty_breakdown_total = qty_bundle dan sudah_ada_log_sewing = 0 untuk semua baris.

INSERT INTO article_workflow_logs (
    article_workflow_id, bundle_id, article_size_id, division_id,
    resource_id, employee_id,
    qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing, qty_reject_rework, qty_lost,
    log_type, remark,
    received_at, received_by_resource_id, received_remark,
    target_division_id, target_division_id_original,
    created_at, created_by
)
SELECT
    aw_sew.article_workflow_id, b.bundle_id, NULL, 2,
    b.resource_id, b.employee_id,
    fb.qty_ok, fb.qty_reject_print, fb.qty_reject_fabric, fb.qty_reject_sewing, fb.qty_reject_rework, fb.qty_lost,
    'NORMAL', fb.status_note,
    NULL, NULL, NULL,
    @TrimDivisionId, NULL,
    DATEADD(DAY, 1, bundling_log.received_at), @ActorUserId
FROM @FoundBundles fb
JOIN bundles b ON b.serial = fb.serial
JOIN article_workflows aw_sew ON aw_sew.article_id = b.article_id AND aw_sew.division_id = 2 AND aw_sew.deleted_at IS NULL
JOIN article_workflow_logs bundling_log ON bundling_log.bundle_id = b.bundle_id AND bundling_log.division_id = 7 AND bundling_log.deleted_at IS NULL
WHERE NOT EXISTS (
    SELECT 1 FROM article_workflow_logs x
    WHERE x.bundle_id = b.bundle_id AND x.division_id = 2 AND x.deleted_at IS NULL
);
