-- Prompt 45/46 -- Drill-down per line pada modal detail (dashboard target harian): Per
-- Penjahit, PO Berjalan, Selesai, Reject. READ-ONLY, tidak ada INSERT/UPDATE/DELETE.
-- Basis Qty Ok/Reject dan WIP WAJIB identik dengan SIS_Dashboard_TargetHarian
-- (sql/sp_Dashboard_TargetHarian.sql) supaya baris TOTAL di tab "Per Penjahit" sama dengan
-- angka baris line di dashboard -- lihat verifikasi di prompt. Tab Selesai/Reject (Prompt 46)
-- menyalin basis Qty (3 kategori reject) yang sama dari tab Per Penjahit.
--
-- Prompt 51: modal bisa dibuka di level DIVISI, bukan cuma line -- @ResourceId di KELIMA SP
-- Prompt 45/46 di bawah (+ 3 SP baru Prompt 51) sekarang OPSIONAL (default NULL). NULL berarti
-- agregasi SELURUH resource divisi tsb (mode divisi); diisi = perilaku PERSIS seperti semula
-- (mode line, tidak berubah). Tab "Tren"/"Per Jam" (Prompt 51) di sql/sp_Report_LineDetail.sql
-- bagian bawah file ini.
--
-- Prompt 52: tab "PO Berjalan" dipecah jadi "WIP" (SIS_Report_LineActiveBundles, dipersempit
-- hanya DIKERJAKAN, status TRANSIT lama dibuang dari sini) dan "Transit" (SP baru
-- SIS_Report_LineTransitBundles). Kepemilikan transit diselaraskan ke divisi/resource TUJUAN
-- (bukan pengirim seperti status TRANSIT lama) -- lihat komentar SIS_Report_LineTransitBundles.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Tab 1: Progres per penjahit pada satu line, tanggal tertentu.
-- Kolom: EmployeeId NULL = baris "Tanpa Penjahit" (bundle tanpa employee_id). Target/Progress/
-- Selisih/Sisa per orang TIDAK dihitung di sini -- client memakai TargetPerPerson &
-- ExpectedPercent yang SUDAH dikembalikan SIS_Dashboard_TargetHarian untuk line ybs (Prompt 45
-- revisi, sama untuk semua penjahit di satu line karena jadwalnya seragam).
CREATE OR ALTER PROCEDURE SIS_Report_LineEmployeeProgress
    @DivisionId INT,
    @ResourceId INT = NULL,
    @Tanggal    DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Jam efektif berjalan -- salinan resolusi jadwal (daily_resource_plans -> daily_division_plans
    -- -> work_schedule_defaults) dan pemakaian dbo.fn_EffectiveMinutes dari ResBase/ResCalc di
    -- SIS_Dashboard_TargetHarian (sql/sp_Dashboard_TargetHarian.sql). SP sumber tidak
    -- mengekspos resolusi ini sebagai fungsi terpisah -- kalau logika jadwal itu berubah,
    -- sinkronkan manual di sini juga.
    -- Prompt 51: @ResourceId NULL -> tab ini disembunyikan di UI mode divisi (tidak bermakna
    -- lintas line), tapi SP tetap dibuat toleran NULL (jadwal jatuh ke level divisi, tanpa
    -- resolusi drp) supaya konsisten dengan 6 SP lain di file ini.
    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @NowTime TIME(0) = CAST(@Now AS TIME(0));
    DECLARE @IsToday BIT = CASE WHEN @Tanggal = CAST(@Now AS DATE) THEN 1 ELSE 0 END;
    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @Tanggal) + @@DATEFIRST - 2) % 7) + 1;
    DECLARE @StartTime TIME(0), @EndTime TIME(0);

    IF @ResourceId IS NOT NULL
        SELECT
            @StartTime = COALESCE(drp.start_time, ddp.start_time, wsd.start_time),
            @EndTime = COALESCE(drp.end_time, ddp.end_time, wsd.end_time)
        FROM resources r
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = r.division_id AND ddp.plan_date = @Tanggal AND ddp.deleted_at IS NULL
        LEFT JOIN work_schedule_defaults wsd
            ON wsd.division_id = r.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
        LEFT JOIN daily_resource_plans drp
            ON drp.daily_division_plan_id = ddp.daily_division_plan_id AND drp.resource_id = r.resource_id AND drp.deleted_at IS NULL
        WHERE r.resource_id = @ResourceId AND r.division_id = @DivisionId AND r.deleted_at IS NULL;
    ELSE
        SELECT
            @StartTime = COALESCE(ddp.start_time, wsd.start_time),
            @EndTime = COALESCE(ddp.end_time, wsd.end_time)
        FROM divisions d
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = d.division_id AND ddp.plan_date = @Tanggal AND ddp.deleted_at IS NULL
        LEFT JOIN work_schedule_defaults wsd
            ON wsd.division_id = d.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
        WHERE d.division_id = @DivisionId AND d.deleted_at IS NULL;

    DECLARE @EffectiveMinutesElapsed INT =
        CASE
            WHEN @StartTime IS NULL OR @EndTime IS NULL THEN NULL
            WHEN @IsToday = 0 THEN dbo.fn_EffectiveMinutes(@StartTime, @EndTime, @Tanggal)
            WHEN @NowTime < @StartTime THEN 0
            ELSE dbo.fn_EffectiveMinutes(@StartTime, IIF(@NowTime < @EndTime, @NowTime, @EndTime), @Tanggal)
        END;

    -- Qty Ok/Reject per penjahit -- basis IDENTIK dengan #QtyAgg di SIS_Dashboard_TargetHarian
    -- (article_workflow_logs.division_id/resource_id = pelaksana, created_at = tanggal, 3
    -- kategori reject), difilter lewat bundles.employee_id (Prompt 45).
    ;WITH QtyRaw AS (
        SELECT b.employee_id AS EmployeeId,
               SUM(awl.qty_ok) AS QtyOk,
               SUM(awl.qty_reject_print + awl.qty_reject_fabric + awl.qty_reject_sewing) AS QtyReject
        FROM article_workflow_logs awl
        LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
        WHERE awl.deleted_at IS NULL
          AND awl.division_id = @DivisionId
          AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
          AND CAST(awl.created_at AS date) = @Tanggal
        GROUP BY b.employee_id
    ),
    -- WIP per penjahit -- pakai ulang fn_BundleLastLog (sql/sp_Report_DivisionWip.sql), SAMA
    -- PERSIS dengan definisi WIP dashboard (SIS_Report_DivisionWipTotals), hanya ditambah
    -- filter employee lewat bundle. TIDAK didefinisikan ulang. WipBundles + LastReceivedAt
    -- (Prompt 45 revisi): jumlah bundle (dashboard menampilkan "N bundle - M pcs") dan kapan
    -- terakhir penjahit ini menerima bundle di line ini.
    WipRaw AS (
        SELECT b.employee_id AS EmployeeId, SUM(ll.qty_ok) AS Wip, COUNT(*) AS WipBundles,
               MAX(ll.received_at) AS LastReceivedAt
        FROM fn_BundleLastLog(NULL) ll
        INNER JOIN bundles b ON b.bundle_id = ll.bundle_id
        WHERE ll.target_division_id = @DivisionId
          AND ll.received_at IS NOT NULL
          AND (@ResourceId IS NULL OR ll.received_by_resource_id = @ResourceId)
        GROUP BY b.employee_id
    ),
    EmployeeIds AS (
        SELECT employee_id FROM employees
        WHERE deleted_at IS NULL
          AND resource_id IN (
              SELECT resource_id FROM resources
              WHERE deleted_at IS NULL AND division_id = @DivisionId AND (@ResourceId IS NULL OR resource_id = @ResourceId)
          )
        UNION
        SELECT EmployeeId FROM QtyRaw WHERE EmployeeId IS NOT NULL
        UNION
        SELECT EmployeeId FROM WipRaw WHERE EmployeeId IS NOT NULL
    )
    SELECT
        e.employee_id AS EmployeeId,
        e.employee_name AS EmployeeName,
        ISNULL(q.QtyOk, 0) AS QtyOk,
        ISNULL(q.QtyReject, 0) AS QtyReject,
        ISNULL(w.Wip, 0) AS Wip,
        ISNULL(w.WipBundles, 0) AS WipBundles,
        w.LastReceivedAt AS LastReceivedAt,
        @EffectiveMinutesElapsed AS JamEfektifBerjalan
    FROM EmployeeIds ei
    INNER JOIN employees e ON e.employee_id = ei.employee_id
    LEFT JOIN QtyRaw q ON q.EmployeeId = ei.employee_id
    LEFT JOIN WipRaw w ON w.EmployeeId = ei.employee_id

    UNION ALL

    -- Baris "Tanpa Penjahit" -- bundle tanpa employee_id, hanya ditampilkan kalau memang ada.
    SELECT NULL, NULL,
        ISNULL((SELECT QtyOk FROM QtyRaw WHERE EmployeeId IS NULL), 0),
        ISNULL((SELECT QtyReject FROM QtyRaw WHERE EmployeeId IS NULL), 0),
        ISNULL((SELECT Wip FROM WipRaw WHERE EmployeeId IS NULL), 0),
        ISNULL((SELECT WipBundles FROM WipRaw WHERE EmployeeId IS NULL), 0),
        (SELECT LastReceivedAt FROM WipRaw WHERE EmployeeId IS NULL),
        @EffectiveMinutesElapsed
    WHERE EXISTS (SELECT 1 FROM QtyRaw WHERE EmployeeId IS NULL)
       OR EXISTS (SELECT 1 FROM WipRaw WHERE EmployeeId IS NULL);
END;
GO

-- Tab "WIP" (Prompt 45, dipersempit Prompt 52): bundle DIKERJAKAN di satu line, tanpa filter
-- tanggal (kondisi saat ini). Pengelompokan per project+artikel dan umur dihitung di client.
--
-- Definisi "line ini": bundle diterima line ini (received_by_resource_id = @ResourceId, atau
-- resource mana pun di divisi ini bila @ResourceId NULL) di divisi ini (target_division_id =
-- @DivisionId), received_at terisi.
--
-- Prompt 52: status TRANSIT (bundle yang sudah dikirim tapi belum diterima) TIDAK LAGI keluar
-- dari SP ini -- dipindah ke SIS_Report_LineTransitBundles di bawah, dengan kepemilikan
-- diselaraskan ke divisi/resource TUJUAN (bukan pengirim, lihat komentar SP tsb). Bundle SELESAI
-- (target_division_id NULL pada log terakhir) tidak pernah masuk sini, otomatis tidak tampil.
CREATE OR ALTER PROCEDURE SIS_Report_LineActiveBundles
    @DivisionId INT,
    @ResourceId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- "Log terakhir" per bundle -- salinan pola OUTER APPLY TOP 1 (sort_order DESC,
    -- created_at DESC) dari fn_BundleLastLog (sql/sp_Report_DivisionWip.sql). WAJIB tetap satu
    -- baris per bundle lewat TOP 1 ini -- JANGAN diganti DISTINCT bundle_id polos, baris
    -- ADJUSTMENT/susulan (Prompt 14b) bisa membuat itu salah pilih baris.
    ;WITH LastLog AS (
        SELECT
            b.bundle_id,
            ll.target_division_id,
            ll.received_at,
            ll.received_by_resource_id,
            ll.qty_ok
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        OUTER APPLY (
            SELECT TOP 1 awl.target_division_id, awl.received_at, awl.received_by_resource_id, awl.qty_ok
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
            ORDER BY aw.sort_order DESC, awl.created_at DESC
        ) ll
        WHERE b.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND ll.target_division_id = @DivisionId
          AND ll.received_at IS NOT NULL
          AND (@ResourceId IS NULL OR ll.received_by_resource_id = @ResourceId)
    )
    SELECT
        p.project_id AS ProjectId,
        p.project_name AS ProjectName,
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        b.bundle_id AS BundleId,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.serial AS Serial,
        spd.size_name AS SizeName,
        ll.qty_ok AS Qty,
        rr.resource_name AS TailorName,
        emp.employee_name AS EmployeeName,
        ll.received_at AS SejakAt
    FROM LastLog ll
    INNER JOIN bundles b ON b.bundle_id = ll.bundle_id
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources rr ON rr.resource_id = b.resource_id
    LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
    ORDER BY SejakAt ASC;
END;
GO

-- Tab "Transit" (Prompt 52, baru): bundle yang MENUNGGU DITERIMA oleh divisi/resource ini --
-- kepemilikan transit diselaraskan ke TUJUAN (bukan pengirim, beda dari status TRANSIT lama di
-- SIS_Report_LineActiveBundles sebelum Prompt 52). Satu arah saja: bundle yang sudah diserahkan
-- KELUAR oleh divisi/resource ini bukan urusan di sini -- itu muncul di tab Transit milik step
-- TUJUANnya.
--
-- "Menunggu diterima" -- WAJIB identik dengan definisi dipakai kartu divisi dashboard
-- (SIS_Report_DivisionTransitTotals & fn_BundleLastLog, sql/sp_Report_DivisionWip.sql): log
-- terakhir bundle (proyek berjalan, deleted_at IS NULL), target_division_id = @DivisionId,
-- received_at NULL. JANGAN diubah tanpa menyamakan juga ke SP sumber itu.
CREATE OR ALTER PROCEDURE SIS_Report_LineTransitBundles
    @DivisionId INT,
    @ResourceId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH LastLog AS (
        SELECT
            b.bundle_id,
            ll.division_id AS SenderDivisionId,
            ll.resource_id AS SenderResourceId,
            ll.target_division_id,
            ll.received_at,
            ll.qty_ok,
            ll.created_at
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        OUTER APPLY (
            SELECT TOP 1 awl.division_id, awl.resource_id, awl.target_division_id, awl.received_at, awl.qty_ok, awl.created_at
            FROM article_workflow_logs awl
            INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = b.bundle_id AND awl.deleted_at IS NULL
            ORDER BY aw.sort_order DESC, awl.created_at DESC
        ) ll
        WHERE b.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND ll.target_division_id = @DivisionId
          AND ll.received_at IS NULL
    ),
    -- Prediksi resource TUJUAN lewat resources.counterpart_resource_id milik resource PENGIRIM --
    -- baris log yang belum diterima TIDAK PERNAH menyimpan resource tujuan (kolom itu tidak ada
    -- di skema; hanya terisi pasti di received_by_resource_id saat benar-benar diterima). Pola
    -- resolusi counterpart ini SAMA dengan auto-terima di SIS_WorkflowLog_Manage (action
    -- CREATE/REVISE_HANDOVER/ADJUST, sql/sp_WorkflowLog_Manage.sql): counterpart valid = resource
    -- hidup, is_active = 1, division_id = divisi tujuan. NULL berarti tidak bisa diprediksi.
    Predicted AS (
        SELECT
            ll.*,
            cp.resource_id AS PredictedResourceId
        FROM LastLog ll
        LEFT JOIN resources sender ON sender.resource_id = ll.SenderResourceId
        LEFT JOIN resources cp
            ON cp.resource_id = sender.counterpart_resource_id
           AND cp.deleted_at IS NULL AND cp.is_active = 1 AND cp.division_id = @DivisionId
    )
    SELECT
        p.project_id AS ProjectId,
        p.project_name AS ProjectName,
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        b.bundle_id AS BundleId,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.serial AS Serial,
        spd.size_name AS SizeName,
        pr.qty_ok AS Qty,
        sd.division_name AS AsalDivisionName,
        sr.resource_name AS AsalResourceName,
        pr.created_at AS DiserahkanAt,
        CASE WHEN pr.PredictedResourceId IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS BelumDitentukanLine
    FROM Predicted pr
    INNER JOIN bundles b ON b.bundle_id = pr.bundle_id
    INNER JOIN articles a ON a.article_id = b.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN divisions sd ON sd.division_id = pr.SenderDivisionId
    LEFT JOIN resources sr ON sr.resource_id = pr.SenderResourceId
    WHERE
        -- Mode divisi: batas transit di batas divisi -- perpindahan bundle antar resource DI
        -- DALAM divisi yang sama (pengirim juga berdivisi @DivisionId) TIDAK dihitung transit
        -- divisi (Bagian 6 prompt 52), supaya tidak menggelembung dibanding kartu dashboard.
        (@ResourceId IS NULL AND pr.SenderDivisionId <> @DivisionId)
        -- Mode line: baris yang diprediksi menuju resource ini, DITAMBAH baris yang tidak bisa
        -- diprediksi sama sekali (PredictedResourceId NULL) -- supaya tidak hilang dari
        -- pencarian, tampil sbg grup penampung "Belum ditentukan line" di SETIAP line divisi
        -- ini (client, lihat LineDetailModal.razor). Di mode ini perpindahan antar resource
        -- dalam divisi yang sama TETAP dihitung (tidak ada filter SenderDivisionId).
        OR (@ResourceId IS NOT NULL AND (pr.PredictedResourceId = @ResourceId OR pr.PredictedResourceId IS NULL))
    ORDER BY DiserahkanAt ASC;
END;
GO

-- Tab 3 (Prompt 46): bundle SELESAI dikerjakan di satu line, dalam rentang periode
-- [@DariTanggal, @SampaiTanggal) -- batas atas eksklusif, dikonversi dari pilihan periode
-- (hari/7hari/gajian) di API (TerakarsaApp.API/Services/DashboardService.cs), bukan di sini.
--
-- "Selesai" = baris article_workflow_logs milik STEP line ini sendiri (division_id/resource_id
-- = @DivisionId/@ResourceId, created_at = SelesaiAt -- waktu diserahterimakan keluar dari line
-- ini), basis QtyOk/QtyReject IDENTIK dengan QtyRaw di SIS_Report_LineEmployeeProgress di atas
-- (3 kategori reject print/fabric/sewing) supaya total Rjk tab ini konsisten dengan tab Per
-- Penjahit & tab Reject (lihat verifikasi Prompt 46).
--
-- ReceivedAt = kapan line ini MENERIMA bundle tsb dari step sebelumnya -- dicari lewat baris
-- LAIN (bukan baris "Selesai" itu sendiri) yang received_by_resource_id/target_division_id =
-- line ini, dengan received_at terdekat SEBELUM SelesaiAt (OUTER APPLY TOP 1), pola sama dengan
-- DIKERJAKAN di SIS_Report_LineActiveBundles. NULL kalau bundle memang dibuat langsung di line
-- ini (tidak ada step sebelumnya, mis. Cutting/Bundling) -- client tampilkan "-" untuk Lama.
CREATE OR ALTER PROCEDURE SIS_Report_LineCompletedBundles
    @DivisionId    INT,
    @ResourceId    INT = NULL,
    @DariTanggal   DATETIME,
    @SampaiTanggal DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.project_id AS ProjectId,
        p.project_name AS ProjectName,
        a.article_id AS ArticleId,
        a.article_name AS ArticleName,
        a.style AS Style,
        a.color AS Color,
        b.bundle_id AS BundleId,
        b.bundle_no AS BundleNo,
        p.bundle_letter AS BundleLetter,
        b.serial AS Serial,
        spd.size_name AS SizeName,
        b.qty AS Qty,
        awl.qty_ok AS QtyOk,
        (awl.qty_reject_print + awl.qty_reject_fabric + awl.qty_reject_sewing) AS QtyReject,
        awl.qty_lost AS QtyLost,
        rr.resource_name AS TailorName,
        emp.employee_name AS EmployeeName,
        recv.ReceivedAt AS ReceivedAt,
        awl.created_at AS SelesaiAt
    FROM article_workflow_logs awl
    INNER JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
    INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
    INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
    INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id AND asz.deleted_at IS NULL
    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources rr ON rr.resource_id = b.resource_id
    LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
    OUTER APPLY (
        SELECT TOP 1 prev.received_at AS ReceivedAt
        FROM article_workflow_logs prev
        WHERE prev.bundle_id = awl.bundle_id
          AND prev.deleted_at IS NULL
          AND prev.target_division_id = @DivisionId
          AND (@ResourceId IS NULL OR prev.received_by_resource_id = @ResourceId)
          AND prev.received_at IS NOT NULL
          AND prev.received_at <= awl.created_at
        ORDER BY prev.received_at DESC
    ) recv
    WHERE awl.deleted_at IS NULL
      AND awl.division_id = @DivisionId
      AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
      AND awl.created_at >= @DariTanggal
      AND awl.created_at < @SampaiTanggal
    ORDER BY awl.created_at DESC;
END;
GO

-- Tab 4 (Prompt 46, revisi): bundle bermasalah (reject/hilang) di satu line pada periode yang
-- sama. Sumber baris & rentang tanggal IDENTIK dengan SIS_Report_LineCompletedBundles di atas
-- (baris "Selesai" milik step line ini). Kategori reject TIDAK digabung -- dikembalikan apa
-- adanya per kategori (Print/Fabric/Sewing/Rework) supaya client bisa menampilkan kolom
-- terpisah, tidak dijumlah jadi satu angka "Rjk" di sini. TotalOutputPo/TotalOutputLine tetap
-- pakai basis 3 kategori (print/fabric/sewing, TIDAK termasuk rework) + lost, IDENTIK dengan
-- basis Rjk di SIS_Report_LineEmployeeProgress/SIS_Report_LineCompletedBundles, supaya
-- perhitungan persen di client (dari 3 kategori itu) tetap konsisten dengan tab Selesai & Per
-- Penjahit -- lihat verifikasi Prompt 46. Rework ikut ditampilkan sebagai kolom informasi,
-- tapi TIDAK dihitung ke persen/ambang reject tsb.
--
-- TotalOutputPo/TotalOutputLine dihitung dari SELURUH baris "Selesai" line ini pada periode ini
-- (bukan cuma yang bermasalah), pakai window function SUM(...) OVER (PARTITION BY ArticleId) /
-- OVER () -- supaya angka "N dari M" (per PO) dan persen TOTAL (per line) di client benar
-- walau baris tanpa masalah tidak ikut tampil di hasil akhir.
--
-- TailorName TIDAK dikembalikan -- tab ini sudah discope ke satu line/resource (lihat judul
-- modal), jadi nama line di kolom Penjahit redundan. Remark = article_workflow_logs.remark
-- (catatan bebas pada baris log reject ybs, BUKAN bundles.remarks) ikut dikembalikan supaya
-- catatan si pelaksana/pencatat saat lapor reject kelihatan di tab ini.
CREATE OR ALTER PROCEDURE SIS_Report_LineRejectBundles
    @DivisionId    INT,
    @ResourceId    INT = NULL,
    @DariTanggal   DATETIME,
    @SampaiTanggal DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Rows AS (
        SELECT
            p.project_id AS ProjectId,
            p.project_name AS ProjectName,
            a.article_id AS ArticleId,
            a.article_name AS ArticleName,
            a.style AS Style,
            a.color AS Color,
            b.bundle_id AS BundleId,
            b.bundle_no AS BundleNo,
            p.bundle_letter AS BundleLetter,
            b.serial AS Serial,
            spd.size_name AS SizeName,
            awl.qty_reject_print AS QtyRejectPrint,
            awl.qty_reject_fabric AS QtyRejectFabric,
            awl.qty_reject_sewing AS QtyRejectSewing,
            awl.qty_reject_rework AS QtyRejectRework,
            awl.qty_lost AS QtyLost,
            (awl.qty_ok + awl.qty_reject_print + awl.qty_reject_fabric + awl.qty_reject_sewing + awl.qty_lost) AS TotalOutput,
            emp.employee_name AS EmployeeName,
            awl.remark AS Remark,
            awl.log_type AS LogType,
            awl.created_at AS WaktuAt
        FROM article_workflow_logs awl
        INNER JOIN bundles b ON b.bundle_id = awl.bundle_id AND b.deleted_at IS NULL
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id AND asz.deleted_at IS NULL
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
        WHERE awl.deleted_at IS NULL
          AND awl.division_id = @DivisionId
          AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
          AND awl.created_at >= @DariTanggal
          AND awl.created_at < @SampaiTanggal
    ),
    WithTotal AS (
        SELECT *,
            SUM(TotalOutput) OVER (PARTITION BY ArticleId) AS TotalOutputPo,
            SUM(TotalOutput) OVER () AS TotalOutputLine
        FROM Rows
    )
    SELECT
        ProjectId, ProjectName, ArticleId, ArticleName, Style, Color,
        BundleId, BundleNo, BundleLetter, Serial, SizeName,
        QtyRejectPrint, QtyRejectFabric, QtyRejectSewing, QtyRejectRework, QtyLost,
        EmployeeName, Remark, LogType, WaktuAt,
        TotalOutputPo, TotalOutputLine
    FROM WithTotal
    WHERE QtyRejectPrint <> 0 OR QtyRejectFabric <> 0 OR QtyRejectSewing <> 0
       OR QtyRejectRework <> 0 OR QtyLost <> 0
    ORDER BY (QtyRejectPrint + QtyRejectFabric + QtyRejectSewing) DESC, QtyLost DESC;
END;
GO

-- ===========================================================================================
-- Prompt 51: tab "Tren" (grafik harian + rekap mingguan) & "Per Jam" pada modal yang sama.
-- Ketiga SP di bawah menerima @ResourceId opsional sama seperti 4 SP di atas.
--
-- "Terima" (metrik BARU, tidak ada padanan di dashboard/tab lain di file ini) = qty yang
-- DITERIMA line/divisi ini dari step sebelumnya pada rentang waktu ybs -- basis received_at,
-- target_division_id = @DivisionId, received_by_resource_id = @ResourceId (atau seluruh
-- resource divisi bila NULL). Pola sama dengan status DIKERJAKAN di SIS_Report_LineActiveBundles
-- & BundleMasuk/SizeMasuk di sql/sp_Report_Produksi.sql, hanya di sini dihitung PER TANGGAL/JAM
-- (bukan snapshot kondisi saat ini). "Selisih = OK - Terima" (dihitung di client) negatif berarti
-- lebih banyak masuk daripada keluar -> menumpuk.
--
-- "Qty OK"/"Qty Reject" (3 kategori print+fabric+sewing) basis IDENTIK dengan #QtyAgg di
-- SIS_Dashboard_TargetHarian & QtyRaw di SIS_Report_LineEmployeeProgress di atas (division_id/
-- resource_id pelaksana, created_at).
-- ===========================================================================================

-- Tab "Tren", grafik harian: satu baris per tanggal dalam [@DariTanggal, @SampaiTanggal]
-- (INCLUSIVE kedua ujung -- beda dari SP lain di file ini yang pakai [Dari, Sampai) exclusive,
-- karena di sini rentangnya "N hari mundur dari tanggal aktif" bukan periode jam presisi).
-- Tally tanggal (bukan gantung ke data log) supaya hari tanpa aktivitas tetap tampil sbg 0.
CREATE OR ALTER PROCEDURE SIS_Report_LineTrendDaily
    @DivisionId    INT,
    @ResourceId    INT = NULL,
    @DariTanggal   DATE,
    @SampaiTanggal DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Tally AS (
        SELECT @DariTanggal AS Tanggal
        UNION ALL
        SELECT DATEADD(DAY, 1, Tanggal) FROM Tally WHERE Tanggal < @SampaiTanggal
    ),
    Terima AS (
        SELECT CAST(awl.received_at AS date) AS Tanggal, SUM(awl.qty_ok) AS QtyTerima
        FROM article_workflow_logs awl
        WHERE awl.deleted_at IS NULL
          AND awl.target_division_id = @DivisionId
          AND (@ResourceId IS NULL OR awl.received_by_resource_id = @ResourceId)
          AND awl.received_at IS NOT NULL
          AND CAST(awl.received_at AS date) BETWEEN @DariTanggal AND @SampaiTanggal
        GROUP BY CAST(awl.received_at AS date)
    ),
    Ok AS (
        SELECT CAST(awl.created_at AS date) AS Tanggal, SUM(awl.qty_ok) AS QtyOk
        FROM article_workflow_logs awl
        WHERE awl.deleted_at IS NULL
          AND awl.division_id = @DivisionId
          AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
          AND CAST(awl.created_at AS date) BETWEEN @DariTanggal AND @SampaiTanggal
        GROUP BY CAST(awl.created_at AS date)
    )
    SELECT
        t.Tanggal AS Tanggal,
        ISNULL(te.QtyTerima, 0) AS QtyTerima,
        ISNULL(ok.QtyOk, 0) AS QtyOk
    FROM Tally t
    LEFT JOIN Terima te ON te.Tanggal = t.Tanggal
    LEFT JOIN Ok ok ON ok.Tanggal = t.Tanggal
    ORDER BY t.Tanggal ASC
    OPTION (MAXRECURSION 31);
END;
GO

-- Tab "Tren", rekap mingguan: satu baris per periode gajian, @JumlahPeriode terakhir dihitung
-- mundur dari @SampaiTanggal. Anchor Sabtu 10:00 = SALINAN PERSIS rumus
-- ResolveLineDetailPeriode("gajian") di TerakarsaApp.API/Services/DashboardService.cs (yang
-- sendiri menyalin BuildPeriods() di ReportProduksi.razor, Prompt 30) -- JANGAN bikin definisi
-- periode baru di sini. @NetDow = hari dlm minggu gaya .NET DayOfWeek (Minggu=0..Sabtu=6),
-- diturunkan dari @Dow (1=Senin..7=Minggu, dipakai work_schedule_defaults) via modulo 7 supaya
-- independen dari @@DATEFIRST -- lihat fn_EffectiveMinutes di sql/sp_Dashboard_TargetHarian.sql
-- untuk pola @Dow yang sama.
CREATE OR ALTER PROCEDURE SIS_Report_LineTrendWeekly
    @DivisionId    INT,
    @ResourceId    INT = NULL,
    @SampaiTanggal DATE,
    @JumlahPeriode INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DashboardMode VARCHAR(20);
    SELECT @DashboardMode = dashboard_mode FROM divisions WHERE division_id = @DivisionId AND deleted_at IS NULL;

    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @SampaiTanggal) + @@DATEFIRST - 2) % 7) + 1;
    DECLARE @NetDow INT = @Dow % 7;
    DECLARE @DaysSinceSaturday INT = (@NetDow + 1) % 7;
    DECLARE @AnchorStart DATE = DATEADD(DAY, -@DaysSinceSaturday, @SampaiTanggal);

    ;WITH Periods AS (
        SELECT 0 AS Seq,
               CAST(DATEADD(HOUR, 10, CAST(@AnchorStart AS DATETIME2)) AS DATETIME2) AS PeriodeMulai
        UNION ALL
        SELECT Seq + 1, DATEADD(DAY, -7, PeriodeMulai)
        FROM Periods
        WHERE Seq + 1 < @JumlahPeriode
    ),
    PeriodRange AS (
        SELECT Seq, PeriodeMulai, DATEADD(DAY, 7, PeriodeMulai) AS PeriodeSelesai
        FROM Periods
    ),
    Terima AS (
        SELECT pr.Seq, SUM(awl.qty_ok) AS QtyTerima
        FROM PeriodRange pr
        INNER JOIN article_workflow_logs awl
            ON awl.deleted_at IS NULL
           AND awl.target_division_id = @DivisionId
           AND (@ResourceId IS NULL OR awl.received_by_resource_id = @ResourceId)
           AND awl.received_at >= pr.PeriodeMulai AND awl.received_at < pr.PeriodeSelesai
        GROUP BY pr.Seq
    ),
    Ok AS (
        SELECT pr.Seq,
               SUM(awl.qty_ok) AS QtyOk,
               SUM(awl.qty_reject_print + awl.qty_reject_fabric + awl.qty_reject_sewing) AS QtyReject
        FROM PeriodRange pr
        INNER JOIN article_workflow_logs awl
            ON awl.deleted_at IS NULL
           AND awl.division_id = @DivisionId
           AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
           AND awl.created_at >= pr.PeriodeMulai AND awl.created_at < pr.PeriodeSelesai
        GROUP BY pr.Seq
    ),
    -- JumlahOrang -- rata-rata headcount yg diinput PPIC per HARI KALENDER dlm periode (hari
    -- tanpa input tidak ikut dihitung; kalau TIDAK ADA satu hari pun yg diinput -> NULL, client
    -- tampilkan "-"). Desain (tidak eksplisit di prompt): 7 tanggal kalender
    -- [PeriodeMulai.Date .. +6] dipakai sbg representasi 1 minggu (sama seperti definisi rentang
    -- "7hari" di ResolveLineDetailPeriode), BUKAN 8 tanggal kalender yg technically tersentuh
    -- oleh window Sabtu 10:00 -> Sabtu 10:00 berikutnya.
    OrgHari AS (
        SELECT pr.Seq, d.CalDate,
               CASE WHEN @DashboardMode = 'DIVISION' THEN ddp.headcount ELSE rr.Headcount END AS Headcount,
               CASE WHEN ddp.daily_division_plan_id IS NULL THEN NULL
                    ELSE CAST(CASE WHEN ISNULL(ddp.is_holiday, 0) = 0 THEN 1 ELSE 0 END AS BIT)
               END AS PlannedWorking
        FROM PeriodRange pr
        CROSS APPLY (VALUES
            (CAST(pr.PeriodeMulai AS DATE)), (DATEADD(DAY, 1, CAST(pr.PeriodeMulai AS DATE))),
            (DATEADD(DAY, 2, CAST(pr.PeriodeMulai AS DATE))), (DATEADD(DAY, 3, CAST(pr.PeriodeMulai AS DATE))),
            (DATEADD(DAY, 4, CAST(pr.PeriodeMulai AS DATE))), (DATEADD(DAY, 5, CAST(pr.PeriodeMulai AS DATE))),
            (DATEADD(DAY, 6, CAST(pr.PeriodeMulai AS DATE)))
        ) d(CalDate)
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = @DivisionId AND ddp.plan_date = d.CalDate AND ddp.deleted_at IS NULL
        OUTER APPLY (
            SELECT SUM(drp.headcount) AS Headcount
            FROM daily_resource_plans drp
            WHERE drp.daily_division_plan_id = ddp.daily_division_plan_id AND drp.deleted_at IS NULL
              AND (@ResourceId IS NULL OR drp.resource_id = @ResourceId)
        ) rr
    ),
    OrgAgg AS (
        SELECT Seq,
               AVG(CAST(Headcount AS FLOAT)) AS AvgOrg,
               COUNT(Headcount) AS DaysWithInput
        FROM OrgHari
        GROUP BY Seq
    ),
    -- JumlahHariKerja -- hari libur diambil dari daily_division_plans.is_holiday bila ADA
    -- rencana hari itu; kalau TIDAK ada rencana, fallback ke default work_schedule_defaults
    -- divisi utk hari itu; kalau keduanya tidak ada, dianggap hari kerja (tidak ada info
    -- sebaliknya).
    HariKerja AS (
        SELECT oh.Seq,
               SUM(CASE
                     WHEN oh.PlannedWorking IS NOT NULL THEN CAST(oh.PlannedWorking AS INT)
                     WHEN wsd_default.is_working_day IS NOT NULL THEN CAST(wsd_default.is_working_day AS INT)
                     ELSE 1
                   END) AS JumlahHariKerja
        FROM OrgHari oh
        OUTER APPLY (
            SELECT TOP 1 wsd2.is_working_day
            FROM work_schedule_defaults wsd2
            WHERE wsd2.division_id = @DivisionId
              AND wsd2.day_of_week = ((DATEPART(WEEKDAY, oh.CalDate) + @@DATEFIRST - 2) % 7) + 1
              AND wsd2.deleted_at IS NULL
        ) wsd_default
        GROUP BY oh.Seq
    )
    SELECT
        pr.PeriodeMulai AS PeriodeMulai,
        pr.PeriodeSelesai AS PeriodeSelesai,
        'W' + RIGHT('0' + CAST(DATEPART(ISO_WEEK, pr.PeriodeMulai) AS VARCHAR(2)), 2) AS KodeMinggu,
        ISNULL(te.QtyTerima, 0) AS QtyTerima,
        ISNULL(ok.QtyOk, 0) AS QtyOk,
        ISNULL(ok.QtyReject, 0) AS QtyReject,
        CASE WHEN oa.DaysWithInput > 0 THEN CAST(ROUND(oa.AvgOrg, 0) AS INT) ELSE NULL END AS JumlahOrang,
        hk.JumlahHariKerja AS JumlahHariKerja
    FROM PeriodRange pr
    LEFT JOIN Terima te ON te.Seq = pr.Seq
    LEFT JOIN Ok ok ON ok.Seq = pr.Seq
    LEFT JOIN OrgAgg oa ON oa.Seq = pr.Seq
    LEFT JOIN HariKerja hk ON hk.Seq = pr.Seq
    ORDER BY pr.PeriodeMulai ASC
    OPTION (MAXRECURSION 100);
END;
GO

-- Tab "Per Jam": result set 1 = satu baris per jam dalam jam kerja (dari jam masuk sampai
-- target jam pulang, dipotong di jam berjalan bila @Tanggal = hari ini); result set 2 = meta
-- (jam masuk, jam pulang PENUH sesuai jadwal -- TIDAK dipotong jam berjalan, beda dari result
-- set 1 -- supaya client tahu target axis lengkap, target harian, target/jam).
CREATE OR ALTER PROCEDURE SIS_Report_LineHourly
    @DivisionId INT,
    @ResourceId INT = NULL,
    @Tanggal    DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @NowTime TIME(0) = CAST(@Now AS TIME(0));
    DECLARE @IsToday BIT = CASE WHEN @Tanggal = CAST(@Now AS DATE) THEN 1 ELSE 0 END;
    DECLARE @Dow TINYINT = ((DATEPART(WEEKDAY, @Tanggal) + @@DATEFIRST - 2) % 7) + 1;

    DECLARE @StartTime TIME(0), @EndTime TIME(0), @TargetHarian INT;

    IF @ResourceId IS NOT NULL
    BEGIN
        -- Jam kerja & target satu line -- pola sama dengan SIS_Report_LineEmployeeProgress di atas.
        SELECT
            @StartTime = COALESCE(drp.start_time, ddp.start_time, wsd.start_time),
            @EndTime = COALESCE(drp.end_time, ddp.end_time, wsd.end_time),
            @TargetHarian = CASE WHEN drp.headcount IS NOT NULL AND drp.target_per_person IS NOT NULL
                                  THEN drp.headcount * drp.target_per_person ELSE NULL END
        FROM resources r
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = r.division_id AND ddp.plan_date = @Tanggal AND ddp.deleted_at IS NULL
        LEFT JOIN work_schedule_defaults wsd
            ON wsd.division_id = r.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
        LEFT JOIN daily_resource_plans drp
            ON drp.daily_division_plan_id = ddp.daily_division_plan_id AND drp.resource_id = r.resource_id AND drp.deleted_at IS NULL
        WHERE r.resource_id = @ResourceId AND r.division_id = @DivisionId AND r.deleted_at IS NULL;
    END
    ELSE
    BEGIN
        -- Jam kerja & target agregat divisi -- pola sama dengan Base CTE di SIS_Dashboard_TargetHarian
        -- (sql/sp_Dashboard_TargetHarian.sql): DIVISION mode pakai ddp.headcount/target_per_person
        -- langsung, RESOURCE mode pakai SUM seluruh daily_resource_plans divisi tsb.
        DECLARE @DashboardMode VARCHAR(20);
        DECLARE @DdpId INT;
        SELECT
            @StartTime = COALESCE(ddp.start_time, wsd.start_time),
            @EndTime = COALESCE(ddp.end_time, wsd.end_time),
            @DashboardMode = d.dashboard_mode,
            @DdpId = ddp.daily_division_plan_id,
            @TargetHarian = CASE WHEN d.dashboard_mode = 'DIVISION' THEN ddp.target_per_person * ddp.headcount ELSE NULL END
        FROM divisions d
        LEFT JOIN daily_division_plans ddp
            ON ddp.division_id = d.division_id AND ddp.plan_date = @Tanggal AND ddp.deleted_at IS NULL
        LEFT JOIN work_schedule_defaults wsd
            ON wsd.division_id = d.division_id AND wsd.day_of_week = @Dow AND wsd.deleted_at IS NULL
        WHERE d.division_id = @DivisionId AND d.deleted_at IS NULL;

        IF @DashboardMode = 'RESOURCE'
            SELECT @TargetHarian = SUM(drp.headcount * drp.target_per_person)
            FROM daily_resource_plans drp
            WHERE drp.daily_division_plan_id = @DdpId AND drp.deleted_at IS NULL;
    END

    DECLARE @EffectiveMinutesTotal INT = dbo.fn_EffectiveMinutes(@StartTime, @EndTime, @Tanggal);
    DECLARE @TargetPerJam FLOAT = CASE WHEN @TargetHarian IS NULL OR @EffectiveMinutesTotal IS NULL OR @EffectiveMinutesTotal = 0
                                        THEN NULL ELSE @TargetHarian / (@EffectiveMinutesTotal / 60.0) END;

    DECLARE @StartHour INT, @EndHourExclusive INT;
    IF @StartTime IS NOT NULL AND @EndTime IS NOT NULL AND @EndTime > @StartTime
    BEGIN
        SET @StartHour = DATEPART(HOUR, @StartTime);
        SET @EndHourExclusive = DATEPART(HOUR, @EndTime)
            + CASE WHEN DATEPART(MINUTE, @EndTime) > 0 OR DATEPART(SECOND, @EndTime) > 0 THEN 1 ELSE 0 END;
        IF @IsToday = 1
        BEGIN
            DECLARE @NowHourExclusive INT = DATEPART(HOUR, @NowTime) + 1;
            IF @NowHourExclusive < @EndHourExclusive SET @EndHourExclusive = @NowHourExclusive;
        END
    END

    -- ===== Result set 1: per jam =====
    IF @StartHour IS NOT NULL AND @StartHour < @EndHourExclusive
    BEGIN
        ;WITH Hours AS (
            SELECT @StartHour AS Jam
            UNION ALL
            SELECT Jam + 1 FROM Hours WHERE Jam + 1 < @EndHourExclusive
        ),
        Terima AS (
            SELECT DATEPART(HOUR, awl.received_at) AS Jam, SUM(awl.qty_ok) AS QtyTerima
            FROM article_workflow_logs awl
            WHERE awl.deleted_at IS NULL
              AND awl.target_division_id = @DivisionId
              AND (@ResourceId IS NULL OR awl.received_by_resource_id = @ResourceId)
              AND awl.received_at IS NOT NULL
              AND CAST(awl.received_at AS date) = @Tanggal
            GROUP BY DATEPART(HOUR, awl.received_at)
        ),
        Ok AS (
            SELECT DATEPART(HOUR, awl.created_at) AS Jam, SUM(awl.qty_ok) AS QtyOk
            FROM article_workflow_logs awl
            WHERE awl.deleted_at IS NULL
              AND awl.division_id = @DivisionId
              AND (@ResourceId IS NULL OR awl.resource_id = @ResourceId)
              AND CAST(awl.created_at AS date) = @Tanggal
            GROUP BY DATEPART(HOUR, awl.created_at)
        ),
        -- Jam dianggap "istirahat" kalau bucket [Jam, Jam+1) beririsan dgn rentang work_break_defaults
        -- manapun yg berlaku hari itu (day_of_week NULL = semua hari) -- batas start/end dibulatkan
        -- ke integer jam (floor utk start, ceiling utk end) supaya istirahat separuh jam tetap
        -- menandai bucket jamnya.
        Istirahat AS (
            SELECT DISTINCT h.Jam
            FROM Hours h
            INNER JOIN work_break_defaults wbd
                ON wbd.deleted_at IS NULL AND (wbd.day_of_week IS NULL OR wbd.day_of_week = @Dow)
               AND h.Jam < DATEPART(HOUR, wbd.end_time) + CASE WHEN DATEPART(MINUTE, wbd.end_time) > 0 OR DATEPART(SECOND, wbd.end_time) > 0 THEN 1 ELSE 0 END
               AND h.Jam + 1 > DATEPART(HOUR, wbd.start_time)
        )
        SELECT
            h.Jam AS Jam,
            CAST(CASE WHEN ist.Jam IS NULL THEN 0 ELSE 1 END AS BIT) AS IsIstirahat,
            CASE WHEN ist.Jam IS NOT NULL THEN NULL ELSE ISNULL(te.QtyTerima, 0) END AS QtyTerima,
            CASE WHEN ist.Jam IS NOT NULL THEN NULL ELSE ISNULL(ok.QtyOk, 0) END AS QtyOk
        FROM Hours h
        LEFT JOIN Terima te ON te.Jam = h.Jam
        LEFT JOIN Ok ok ON ok.Jam = h.Jam
        LEFT JOIN Istirahat ist ON ist.Jam = h.Jam
        ORDER BY h.Jam ASC
        OPTION (MAXRECURSION 24);
    END
    ELSE
    BEGIN
        SELECT CAST(0 AS INT) AS Jam, CAST(0 AS BIT) AS IsIstirahat, CAST(NULL AS INT) AS QtyTerima, CAST(NULL AS INT) AS QtyOk
        WHERE 1 = 0;
    END

    -- ===== Result set 2: meta (jam masuk, jam pulang PENUH, target harian, target/jam) =====
    SELECT
        @StartTime AS JamMasuk,
        @EndTime AS TargetPulang,
        @TargetHarian AS TargetHarian,
        @TargetPerJam AS TargetPerJam;
END;
GO
