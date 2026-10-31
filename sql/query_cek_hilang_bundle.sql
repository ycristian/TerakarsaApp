-- Ad hoc (read-only): MEMBEDAH angka Hilang sampai ke tiap pernyataan Kirim Hasil.
-- Pelengkap sql/query_cek_hilang_po.sql (itu ringkasan per PO/line; ini penjelasnya).
--
-- Definisi yang dibuktikan query ini:
--   Hilang BUKAN kolom tersendiri dan BUKAN jumlah baris log -- baris log 'Hilang'
--   qty_delta-nya 0 dan jumlah pcs-nya cuma teks di reason. Hilang adalah SISA dari
--   invarian satu pernyataan pemecahan (SIS_BundleSplit_Manage @Action = 'SPLIT'):
--
--       Masuk  =  QtyOK induk  +  Sigma qty bundle ANAK  +  Hilang
--       -----------------------------------------------------------
--       Masuk        = bundle_splits.source_qty_before (isi induk sebelum pernyataan)
--       QtyOK induk  = qty_after baris log 'Kirim'/'Split'/'Dikembalikan' split itu
--       Sigma anak   = SUM(bundle_split_results.qty) split itu (barang NYATA ADA,
--                      masing-masing lahir jadi bundle anak ber-barcode)
--       Hilang       = sisanya -- barang yang TIDAK ketemu fisiknya, jadi TIDAK pernah
--                      lahir barcode. Inilah yang ditambahkan ke bundles.missing_qty.
--
--   Satu bundle bisa punya BEBERAPA pernyataan (satu per step yang dilewatinya, plus
--   satu lagi tiap kali hasilnya diedit) -- karena itu unit barisnya split, bukan bundle.
--   Pernyataan yang bersih (semua ketemu) menghasilkan Hilang = 0; itu normal.
--
--   Pengurangnya: "Barang ketemu" (kind = 'found') -- missing_qty induk berkurang,
--   boleh sampai negatif (= Lebih).
--
--   Baris dengan Step '(?)' = pernyataan yang baris lognya sudah DIHAPUS (Batal Serah
--   men-soft-delete baris log, tapi bundle_splits-nya tetap tinggal). Hilangnya 0 --
--   memang tidak ada selisih yang pernah diakui di situ.
--
-- READ-ONLY. Ubah @NoPo / @ResourceName di bawah.
SET NOCOUNT ON;

DECLARE @NoPo         VARCHAR(50)  = '632.AGS.2610';
DECLARE @ResourceName VARCHAR(150) = 'Line A4 (Aji)';   -- NULL = semua line

-- ---------------------------------------------------------------------------
-- 1. Tiap pernyataan Kirim Hasil + pembuktian invariannya.
--    Kolom Hilang di sini dihitung ULANG dari rumus, bukan dibaca dari mana pun.
-- ---------------------------------------------------------------------------
SELECT CONVERT(VARCHAR(16), s.created_at, 120) AS Waktu,
       p.bundle_letter + '-' + CAST(sb.bundle_no AS VARCHAR(10)) AS Kode,
       sb.serial            AS Serial,
       d.division_name      AS Divisi,
       ISNULL(aw.step_name, '(?)') AS Step,
       s.source_qty_before  AS Masuk,
       ISNULL(lg.qty_after, s.source_qty_before) AS QtyOk,
       ISNULL(ch.qty, 0)    AS Anak,
       s.source_qty_before - ISNULL(lg.qty_after, s.source_qty_before) - ISNULL(ch.qty, 0) AS Hilang,
       ch.daftar            AS RincianAnak,
       ISNULL(hl.reason, '') AS CatatanLog
FROM bundle_splits s
INNER JOIN bundles sb  ON sb.bundle_id = s.source_bundle_id
INNER JOIN articles a  ON a.article_id = sb.article_id
INNER JOIN projects p  ON p.project_id = a.project_id
INNER JOIN divisions d ON d.division_id = s.division_id
LEFT  JOIN resources r ON r.resource_id = s.resource_id
-- baris log INDUK pernyataan ini: qty_after = isi induk sesudahnya (= QtyOK)
OUTER APPLY (
    SELECT TOP 1 l.qty_after, l.article_workflow_id
    FROM article_workflow_logs l
    WHERE l.split_id = s.split_id AND l.bundle_id = s.source_bundle_id
      AND l.deleted_at IS NULL AND l.log_kind <> 'Hilang'
    ORDER BY l.workflow_log_id
) lg
LEFT JOIN article_workflows aw ON aw.article_workflow_id = lg.article_workflow_id
-- baris log 'Hilang' pernyataan ini -- hanya untuk teksnya; angkanya TIDAK di sini
OUTER APPLY (
    SELECT TOP 1 l.reason
    FROM article_workflow_logs l
    WHERE l.split_id = s.split_id AND l.bundle_id = s.source_bundle_id
      AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
    ORDER BY l.workflow_log_id
) hl
OUTER APPLY (
    SELECT SUM(sr.qty) AS qty,
           STRING_AGG(CAST(cb.serial + ' ' + ISNULL(cb.reject_category, cb.[status])
                           + ' ' + CAST(cb.qty AS VARCHAR(10)) + 'pcs' AS VARCHAR(200)), ' | ') AS daftar
    FROM bundle_split_results sr
    INNER JOIN bundles cb ON cb.bundle_id = sr.bundle_id AND cb.deleted_at IS NULL
    WHERE sr.split_id = s.split_id
) ch
WHERE s.kind = 'split'
  AND p.no_po = @NoPo
  AND (@ResourceName IS NULL OR r.resource_name = @ResourceName)
ORDER BY s.created_at, sb.serial;

-- ---------------------------------------------------------------------------
-- 2. Saldo per induk: hasil penjumlahan rumus di atas HARUS sama dengan
--    bundles.missing_qty (itulah satu-satunya tempat angkanya disimpan).
--    Beda = ada "Barang ketemu" (kind = 'found') yang menguranginya.
-- ---------------------------------------------------------------------------
SELECT p.bundle_letter + '-' + CAST(b.bundle_no AS VARCHAR(10)) AS Kode,
       b.serial                AS Serial,
       b.qty                   AS QtyIndukSekarang,
       b.missing_qty           AS SaldoTersimpan,
       ISNULL(ev.HilangDihitung, 0) AS HilangDariRumus,
       ISNULL(ft.Ketemu, 0)    AS SudahKetemu,
       ISNULL(ev.HilangDihitung, 0) - ISNULL(ft.Ketemu, 0) AS Cocok
FROM bundles b
INNER JOIN articles a ON a.article_id = b.article_id
INNER JOIN projects p ON p.project_id = a.project_id
OUTER APPLY (
    SELECT SUM(s.source_qty_before - ISNULL(lg.qty_after, s.source_qty_before) - ISNULL(ch.qty, 0)) AS HilangDihitung
    FROM bundle_splits s
    OUTER APPLY (
        SELECT TOP 1 l.qty_after FROM article_workflow_logs l
        WHERE l.split_id = s.split_id AND l.bundle_id = s.source_bundle_id
          AND l.deleted_at IS NULL AND l.log_kind <> 'Hilang'
        ORDER BY l.workflow_log_id
    ) lg
    OUTER APPLY (
        SELECT SUM(sr.qty) AS qty FROM bundle_split_results sr WHERE sr.split_id = s.split_id
    ) ch
    WHERE s.source_bundle_id = b.bundle_id AND s.kind = 'split'
) ev
OUTER APPLY (
    SELECT SUM(sr2.qty) AS Ketemu
    FROM bundle_splits s2
    INNER JOIN bundle_split_results sr2 ON sr2.split_id = s2.split_id
    WHERE s2.source_bundle_id = b.bundle_id AND s2.kind = 'found'
) ft
OUTER APPLY (
    SELECT TOP 1 l.resource_id FROM article_workflow_logs l
    WHERE l.bundle_id = b.bundle_id AND l.deleted_at IS NULL AND l.log_kind = 'Hilang'
    ORDER BY l.created_at DESC, l.workflow_log_id DESC
) lm
LEFT JOIN resources r ON r.resource_id = ISNULL(lm.resource_id, b.resource_id)
WHERE b.deleted_at IS NULL AND b.sequence_no = 0 AND b.missing_qty <> 0
  AND p.no_po = @NoPo
  AND (@ResourceName IS NULL OR r.resource_name = @ResourceName)
ORDER BY b.bundle_no;
