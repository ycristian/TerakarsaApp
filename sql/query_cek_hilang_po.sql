-- Ad hoc (read-only): total HILANG satu PO sepanjang produksi, per line.
-- Dua jalur sumber (lihat sql/v_84_reject_unified.sql):
--   LAMA  = article_workflow_logs.qty_lost, untuk log created_at < app_settings.bundle_split_migrated_at
--   BARU  = kejadian di bundle_splits (Prompt 82). Qty per kejadian TIDAK disimpan sebagai
--           angka (baris log 'Hilang'/'Ketemu' qty_delta = 0, jumlahnya hanya teks di reason),
--           jadi dihitung ulang: source_qty_before - qty induk setelah kejadian - qty anak yang lahir.
--           Hasil positif = hilang, negatif = ketemu/koreksi.
--
-- READ-ONLY (tidak membuat/mengubah apa pun). Ubah @NoPo / @ResourceName di bawah.
-- @ResourceName = nama resource, jadi satu orang yang punya line di dua divisi
-- (mis. 'Line A1 (Heru)' di Sew + QC dan 'Trim  A1 (Heru)' di Buang Benang) harus
-- dicek per baris -- bukan per orang.
--
-- Hasil 4 adalah pembanding: angka 'Hilang' di kartu stasiun = SALDO TERBUKA
-- (bundles.missing_qty) gaya baru saja, sedangkan hasil 2/3 = TOTAL sepanjang
-- produksi (gaya lama + baru, sebelum dikurangi 'Barang ketemu').
SET NOCOUNT ON;

DECLARE @NoPo         VARCHAR(50)  = '632.AGS.2610';
DECLARE @ResourceName VARCHAR(150) = 'Line A1 (Heru)';   -- NULL = semua line

DECLARE @MigratedAt DATETIME2 = ISNULL(
    (SELECT TOP 1 bundle_split_migrated_at FROM app_settings WHERE deleted_at IS NULL), '9999-12-31');

;WITH Events AS (
    -- ---------- A. GAYA LAMA: kolom qty_lost ----------
    SELECT CAST('LAMA' AS VARCHAR(6))            AS Sumber,
           awl.created_at                        AS Waktu,
           a.article_name                         AS Artikel,
           aw.step_name                           AS Step,
           d.division_name                        AS Divisi,
           r.resource_name                        AS Line,
           b.serial                               AS Bundle,
           awl.qty_lost                           AS Qty,
           CAST(ISNULL(awl.remark, '') AS VARCHAR(500)) AS Catatan
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a          ON a.article_id = aw.article_id
    INNER JOIN projects p          ON p.project_id = a.project_id
    INNER JOIN divisions d         ON d.division_id = awl.division_id
    INNER JOIN resources r         ON r.resource_id = awl.resource_id
    LEFT  JOIN bundles b           ON b.bundle_id = awl.bundle_id
    WHERE awl.deleted_at IS NULL
      AND awl.qty_lost <> 0
      AND awl.created_at < @MigratedAt
      AND p.no_po = @NoPo
      AND (@ResourceName IS NULL OR r.resource_name = @ResourceName)

    UNION ALL

    -- ---------- B. GAYA BARU: kejadian bundle_splits ----------
    SELECT CAST(CASE WHEN bs.kind = 'found' THEN 'KETEMU' ELSE 'BARU' END AS VARCHAR(6)),
           bs.created_at,
           a.article_name,
           ISNULL(aw.step_name, '(tanpa log)'),
           d.division_name,
           r.resource_name,
           sb.serial,
           bs.source_qty_before - ISNULL(lg.qty_after, bs.source_qty_before) - ISNULL(ch.qty, 0),
           CAST(ISNULL(lg.reason, '') AS VARCHAR(500))
    FROM bundle_splits bs
    INNER JOIN bundles sb  ON sb.bundle_id = bs.source_bundle_id
    INNER JOIN articles a  ON a.article_id = sb.article_id
    INNER JOIN projects p  ON p.project_id = a.project_id
    INNER JOIN divisions d ON d.division_id = bs.division_id
    INNER JOIN resources r ON r.resource_id = bs.resource_id
    -- baris log induk yang membawa split ini: qty_after = isi induk setelah kejadian
    OUTER APPLY (
        SELECT TOP 1 l.qty_after, l.article_workflow_id, l.reason
        FROM article_workflow_logs l
        WHERE l.split_id = bs.split_id AND l.bundle_id = bs.source_bundle_id
          AND l.deleted_at IS NULL AND l.log_kind <> 'Hilang'
        ORDER BY l.workflow_log_id
    ) lg
    LEFT JOIN article_workflows aw ON aw.article_workflow_id = lg.article_workflow_id
    OUTER APPLY (
        SELECT SUM(sr.qty) AS qty FROM bundle_split_results sr WHERE sr.split_id = bs.split_id
    ) ch
    WHERE p.no_po = @NoPo
      AND (@ResourceName IS NULL OR r.resource_name = @ResourceName)
)
SELECT * INTO #ev FROM Events WHERE Qty <> 0;

-- 1. Rincian kejadian
SELECT Sumber, CONVERT(VARCHAR(16), Waktu, 120) AS Waktu, Artikel, Step, Divisi, Line,
       Bundle, Qty, Catatan
FROM #ev
ORDER BY Waktu, Bundle;

-- 2. Ringkasan per artikel
SELECT Artikel,
       SUM(CASE WHEN Qty > 0 THEN Qty ELSE 0 END)  AS HilangKotor,
       SUM(CASE WHEN Qty < 0 THEN -Qty ELSE 0 END) AS KetemuAtauKoreksi,
       SUM(Qty)                                    AS SaldoHilang
FROM #ev
GROUP BY Artikel
ORDER BY Artikel;

-- 3. Ringkasan PO
SELECT SUM(CASE WHEN Qty > 0 THEN Qty ELSE 0 END)  AS HilangKotor,
       SUM(CASE WHEN Qty < 0 THEN -Qty ELSE 0 END) AS KetemuAtauKoreksi,
       SUM(Qty)                                    AS SaldoHilang,
       COUNT(*)                                    AS JumlahKejadian
FROM #ev;

-- 4. Pembanding: angka 'Hilang' yang tampil di kartu stasiun (saldo terbuka
--    bundles.missing_qty, atribusi line = baris log 'Hilang' terakhir).
SELECT a.article_name AS Artikel,
       SUM(CASE WHEN b.missing_qty > 0 THEN b.missing_qty ELSE 0 END) AS HilangDiKartu,
       SUM(CASE WHEN b.missing_qty < 0 THEN -b.missing_qty ELSE 0 END) AS LebihDiKartu
FROM bundles b
INNER JOIN articles a ON a.article_id = b.article_id
INNER JOIN projects p ON p.project_id = a.project_id
OUTER APPLY (
    SELECT TOP 1 l.resource_id
    FROM article_workflow_logs l
    WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
    ORDER BY l.created_at DESC, l.workflow_log_id DESC
) lm
LEFT JOIN resources r ON r.resource_id = ISNULL(lm.resource_id, b.resource_id)
WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.missing_qty <> 0
  AND p.no_po = @NoPo
  AND (@ResourceName IS NULL OR r.resource_name = @ResourceName)
GROUP BY a.article_name;

DROP TABLE #ev;
