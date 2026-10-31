-- Prompt 59: tab "Rekap Produksi" di perangkat stasiun -- matriks output satu RESOURCE
-- (line) untuk satu PERIODE GAJIAN. SELECT saja.
--
-- Dikelompokkan per resource sesi stasiun (BUKAN per karyawan), dengan baris per STEP
-- ARTIKEL (article_workflow_id). Saat ini satu artikel praktis hanya punya satu step per
-- divisi, tapi grouping tetap per step supaya tetap benar kalau nanti tidak begitu.
--
-- Qty yang dihitung = qty_ok + qty_reject_fabric (reject BAHAN). Kategori reject lain
-- (sablon/jahit/rework/hilang) sengaja TIDAK dihitung -- itu keputusan bisnis prompt,
-- berbeda dari Laporan Produksi admin yang menampilkan kelimanya terpisah.
--
-- Harga SELALU article_workflows.unit_price yang BERLAKU SEKARANG -- tidak ada snapshot
-- harga di log (lihat sql/prompt_59_harga_rekap_nonpo.sql).
-- Konsekuensi yang disengaja: mengubah harga step langsung mengubah kolom Nilai periode
-- lampau juga.
--
-- CATATAN Prompt 83: snapshot harga per periode SEKARANG ADA, di
-- workflow_lock_items.unit_price, dan dipakai halaman admin Rekap Gajian
-- (sql/sp_PayrollRekap_Select.sql). Rekap stasiun ini SENGAJA dibiarkan tetap membaca
-- harga yang berlaku sekarang -- mengubahnya di luar cakupan Prompt 83. Akibatnya kedua
-- rekap bisa berbeda untuk periode yang tarifnya diubah SETELAH di-lock, atau yang
-- harganya dikoreksi admin lewat SIS_LockItem_UpdatePrice. Rekap Gajian yang jadi acuan
-- pembayaran; rekap stasiun ini acuan PIC di lapangan.
--
-- Dua mode, dua definisi "tanggal" yang berbeda:
--   OUTPUT -- baris yang DIBUAT resource ini (awl.resource_id) dan sudah DI-LOCK ke periode
--     ini. Periode sebuah baris SELALU diturunkan dari lock_id -> workflow_locks
--     .payroll_period_id, TIDAK PERNAH dari created_at (Prompt 55) -- karena itu tanggal
--     baris bisa jatuh DI LUAR rentang periode (PIC bebas memilih periode saat menekan
--     Lock), dan client menampilkannya sebagai kolom tambahan "luar periode".
--   TERIMA -- baris yang DITERIMA resource ini (received_by_resource_id), received_at di
--     dalam rentang waktu periode. TANPA syarat lock: penerimaan tidak pernah dikunci
--     (lihat catatan di sp_WorkflowLock_Manage.sql), jadi di sini rentang waktulah yang
--     menentukan periode. Harga = harga step BARIS ITU, yaitu step PENGIRIM.
--
-- log_type: hanya 'NORMAL'. Beda dari sp_Report_Produksi.sql yang menyertakan ADJUSTMENT
-- apa adanya, dan itu DISENGAJA -- baris ADJUSTMENT selalu target_division_id NULL, jadi
-- (a) tidak pernah masuk cakupan tab OUT sehingga tidak pernah bisa di-lock (mode OUTPUT
-- tidak akan pernah melihatnya), dan (b) tidak pernah punya received_at (mode TERIMA juga
-- tidak). Filter ini menegaskan maksudnya, bukan mengubah angka.
--
-- Empat result set SELALU dikembalikan (bentuk hasil tidak berubah-ubah menurut mode),
-- tapi set 2 & 3 kosong/nol di mode TERIMA -- chip "belum lock" dan baris "Di luar PO"
-- memang hanya berlaku untuk mode OUTPUT.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_RekapProduksi
    @ResourceId      INT,
    @PayrollPeriodId INT,
    @Mode            VARCHAR(10) = 'OUTPUT'   -- 'OUTPUT' | 'TERIMA'
AS
BEGIN
    SET NOCOUNT ON;

    SET @Mode = UPPER(LTRIM(RTRIM(ISNULL(@Mode, 'OUTPUT'))));

    IF @Mode NOT IN ('OUTPUT', 'TERIMA')
    BEGIN
        RAISERROR('Mode rekap tidak dikenal.', 16, 1);
        RETURN;
    END

    IF @ResourceId IS NULL OR NOT EXISTS (
        SELECT 1 FROM resources WHERE resource_id = @ResourceId AND deleted_at IS NULL
    )
    BEGIN
        RAISERROR('Operator wajib dipilih.', 16, 1);
        RETURN;
    END

    DECLARE @PeriodStart DATETIME2, @PeriodEnd DATETIME2;
    SELECT @PeriodStart = period_start, @PeriodEnd = period_end
    FROM payroll_periods
    WHERE payroll_period_id = @PayrollPeriodId AND deleted_at IS NULL;

    IF @PeriodStart IS NULL
    BEGIN
        RAISERROR('Periode gajian tidak ditemukan.', 16, 1);
        RETURN;
    END

    -- ===== Result set 1: baris PO, format panjang (pivot per tanggal dilakukan client) =====
    IF @Mode = 'OUTPUT'
    BEGIN
        SELECT aw.article_workflow_id AS ArticleWorkflowId,
               a.article_id AS ArticleId,
               a.article_name AS ArticleName,
               a.style AS Style,
               a.color AS Color,
               aw.step_name AS StepName,
               p.project_name AS ProjectName,
               p.no_po AS NoPo,
               CAST(awl.created_at AS DATE) AS Tanggal,
               SUM(awl.qty_ok + awl.qty_reject_fabric) AS Qty,
               aw.unit_price AS UnitPrice
        FROM article_workflow_logs awl
        INNER JOIN workflow_locks wl ON wl.lock_id = awl.lock_id
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        WHERE awl.deleted_at IS NULL
          AND awl.log_type = 'NORMAL'
          AND awl.resource_id = @ResourceId
          AND awl.lock_id IS NOT NULL
          AND wl.payroll_period_id = @PayrollPeriodId
        GROUP BY aw.article_workflow_id, a.article_id, a.article_name, a.style, a.color,
                 aw.step_name, p.project_name, p.no_po, aw.unit_price, CAST(awl.created_at AS DATE)
        ORDER BY a.article_name ASC, aw.step_name ASC, CAST(awl.created_at AS DATE) ASC;
    END
    ELSE
    BEGIN
        SELECT aw.article_workflow_id AS ArticleWorkflowId,
               a.article_id AS ArticleId,
               a.article_name AS ArticleName,
               a.style AS Style,
               a.color AS Color,
               aw.step_name AS StepName,
               p.project_name AS ProjectName,
               p.no_po AS NoPo,
               CAST(awl.received_at AS DATE) AS Tanggal,
               SUM(awl.qty_ok + awl.qty_reject_fabric) AS Qty,
               aw.unit_price AS UnitPrice
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        WHERE awl.deleted_at IS NULL
          AND awl.log_type = 'NORMAL'
          AND awl.received_by_resource_id = @ResourceId
          AND awl.received_at >= @PeriodStart AND awl.received_at < @PeriodEnd
        GROUP BY aw.article_workflow_id, a.article_id, a.article_name, a.style, a.color,
                 aw.step_name, p.project_name, p.no_po, aw.unit_price, CAST(awl.received_at AS DATE)
        ORDER BY a.article_name ASC, aw.step_name ASC, CAST(awl.received_at AS DATE) ASC;
    END

    -- ===== Result set 2: chip "n baris belum lock, tidak dihitung" (mode OUTPUT saja) =====
    -- Cakupan baris SAMA dengan SIS_Station_UnlockedDates (chip di tab OUT) supaya angkanya
    -- tidak pernah menunjuk baris yang tidak bisa ditindaklanjuti operator dari tab OUT.
    -- TANPA filter periode: baris yang belum di-lock memang belum punya periode apa pun.
    SELECT CASE WHEN @Mode = 'OUTPUT' THEN (
               SELECT COUNT(*)
               FROM article_workflow_logs awl
               WHERE awl.deleted_at IS NULL
                 AND awl.lock_id IS NULL
                 AND awl.resource_id = @ResourceId
                 AND (
                       (awl.target_division_id IS NOT NULL AND awl.qty_ok > 0)
                       OR (awl.target_division_id IS NULL AND awl.log_type = 'NORMAL')
                     )
           ) ELSE 0 END AS UnlockedCount;

    -- ===== Result set 3: agregat non-PO per tanggal (mode OUTPUT saja) =====
    SELECT CAST(npo.output_at AS DATE) AS Tanggal,
           SUM(npo.qty) AS Qty,
           CAST(SUM(npo.qty * npo.unit_price) AS DECIMAL(19,4)) AS Nilai
    FROM non_po_outputs npo
    WHERE @Mode = 'OUTPUT'
      AND npo.deleted_at IS NULL
      AND npo.resource_id = @ResourceId
      AND npo.payroll_period_id = @PayrollPeriodId
    GROUP BY CAST(npo.output_at AS DATE)
    ORDER BY CAST(npo.output_at AS DATE) ASC;

    -- ===== Result set 4: info periode + identitas, untuk header kolom tanggal & Excel =====
    SELECT pp.payroll_period_id AS PayrollPeriodId,
           pp.period_code AS PeriodCode,
           pp.period_start AS PeriodStart,
           pp.period_end AS PeriodEnd,
           CAST(CASE WHEN pp.finalized_at IS NULL THEN 0 ELSE 1 END AS BIT) AS IsFinalized,
           r.resource_id AS ResourceId,
           r.resource_name AS ResourceName,
           d.division_name AS DivisionName,
           @Mode AS Mode
    FROM payroll_periods pp
    CROSS JOIN resources r
    INNER JOIN divisions d ON d.division_id = r.division_id
    WHERE pp.payroll_period_id = @PayrollPeriodId
      AND r.resource_id = @ResourceId;
END;
GO
