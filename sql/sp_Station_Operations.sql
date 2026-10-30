-- Query operasional untuk halaman stasiun (/station), semua berbasis @DivisionId
-- (divisi diambil dari token perangkat, lihat SIS_Station_GetByToken).
-- Lookup resource aktif per divisi pakai SP yang sudah ada: SIS_Resource_GetActiveByDivision.
--
-- Model log Prompt 12b (1 baris per serah-terima, tanpa kolom status):
--   SIS_Station_PendingReceives: sederhana sekali -- baris hidup mana pun (level artikel
--   maupun per-bundle) dengan target_division_id = @DivisionId dan received_at IS NULL.
--   Menerima baris ini artinya update received_at/received_by_resource_id (action RECEIVE
--   di SIS_WorkflowLog_Manage), memakai workflow_log_id, bukan lagi article_workflow_id.
--
--   SIS_Station_ActiveWork: step non-bundle (requires_bundle = 0) milik divisi ini -- tampil
--   untuk artikel yang project-nya masih aktif (manual_status bukan COMPLETED/CANCELLED,
--   sama seperti sp_Report_DivisionWip.sql) DAN sudah berstatus STARTED/ON_GOING/ON_HOLD
--   (derived_status bukan NOT_STARTED -- lihat sp_Project_Select.sql: manual_status terisi,
--   ATAU start_date sudah tiba/lewat, ATAU project sudah punya log workflow), bukan antrian
--   sekali-pakai (baris non-bundle bebas dicatat berulang kapan pun, lihat komentar di
--   sp_WorkflowLog_Manage.sql). Kartu "Buat Bundle" (is_bundling = 1, Prompt 24) di UNION
--   ALL kedua ikut gate yang sama -- project yang belum dimulai belum boleh mulai bundling.
--   Prompt 23: dihidupkan lagi sebagai sumber kartu permanen (artikel x step) di tab WIP --
--   sejak 12c sempat tak terpakai. Daftar ukuran (FOR JSON) kini menyertakan qty_order
--   (article_sizes.qty) + total qty_ok tercatat step ini per ukuran, supaya client bisa
--   menampilkan grid Kirim Hasil (kolom Order/Tercatat) tanpa round-trip tambahan.
--
--   SIS_Station_PendingHandover: kebalikan dari PendingReceives -- baris yang DIBUAT oleh
--   divisi ini sendiri (division_id = @DivisionId), sudah punya tujuan serah, tapi BELUM
--   diterima divisi tujuan (received_at IS NULL). Selama belum diterima, divisi pembuat
--   masih boleh merevisi datanya (action UPDATE di SIS_WorkflowLog_Manage) -- begitu
--   diterima (received_at terisi lewat RECEIVE), baris terkunci (tidak boleh direvisi lagi)
--   TAPI tidak langsung hilang dari daftar ini -- lihat Fix di bawah.
--   Fix: baris yang DIBUAT hari ini (awl.created_at) tetap tampil di tab OUT walau sudah
--   diterima, supaya operator tetap bisa melihat riwayat kiriman hari ini (client menandai
--   baris ini read-only, tanpa Revisi/Batal Serah -- lihat StationDevice.razor OutCards).
--   Baris LAWAS (dibuat sebelum hari ini) yang sudah diterima tetap hilang dari daftar --
--   hanya baris yang belum diterima sama sekali yang tetap tampil tanpa batas hari.
--   Prompt 23: SEKARANG juga menyertakan baris step TERAKHIR artikel milik divisi ini
--   (target_division_id NULL, tidak ada tujuan serah -- lihat SIS_Bundle_ScanInfo) selama
--   masih dalam jendela revisi H+1 (hari dibuat + 1 hari kalender), supaya operator bisa
--   menemukan & membetulkan baris itu dari tab OUT tanpa perlu scan ulang QR bundle.
--   IsLastStep membedakan kasus ini di hasil -- baris IsLastStep = 1 TIDAK punya tujuan
--   serah untuk direvisi (client harus sembunyikan field Divisi Tujuan/Penjahit & tombol
--   Batal Serah, pakai UPDATE biasa bukan REVISE_HANDOVER).
--
--   SIS_Station_RecentReceived (Prompt 15): 20 baris terakhir yang DITERIMA divisi ini
--   (target_division_id = @DivisionId, received_at NOT NULL) -- dasar tab "Baru Diterima"
--   dan tombol batal terima (action UNRECEIVE di SIS_WorkflowLog_Manage). CanUnreceive
--   mencerminkan pemeriksaan step-berikutnya yang sama dipakai UNRECEIVE, supaya tombol
--   bisa dinonaktifkan di UI tanpa round-trip tambahan.
--
-- Prompt 12e -- redesign kiosk /station jadi 3 status (Masuk/Dikerjakan/Dikirim):
--   SIS_Station_InProgress: bundle status "Dikerjakan" di divisi ini. TANPA TOP -- ini queue
--   kerja utama operator, bukan riwayat.
--   WorkflowLogId di sini = baris TERAKHIR yang DITERIMA divisi ini (dipakai utk Batal
--   Terima/UNRECEIVE) -- selalu baris yang membawa bundle MASUK ke divisi ini (target_division_id
--   = @DivisionId), bukan baris yang dibuat divisi ini sendiri.
--   NextArticleWorkflowId/NextStepName = step ber-bundle FRONTIER yang harus diselesaikan --
--   Fix (susulan): step frontier dihitung dengan logika kuota Prompt 14b yang sama dengan
--   SIS_Bundle_ScanInfo (@StepQuota: step ber-bundle PERTAMA yang sisa kuotanya, QtyMasuk -
--   QtySudah, masih > 0), BUKAN lagi "baris log TERAKHIR hidup bundle received_at IS NOT NULL
--   DAN target_division_id = @DivisionId". Sebelumnya begitu bundle di-"Kirim Hasil" separuh
--   (mis. 45 dari 50 pcs, baris susulan/QTY_SHORT), baris baru itu langsung jadi baris
--   TERAKHIR (sort_order lebih tinggi) dengan received_at masih NULL -- membuat bundle
--   LANGSUNG hilang dari tab Dikerjakan sebelum sisa 5 pcs sempat dikirim juga, walau baris
--   pertama itu sendiri belum tentu sudah diterima. Definisi baru: bundle tetap/kembali
--   tampil di Dikerjakan @DivisionId selama (a) step frontier-nya milik @DivisionId, (b)
--   step SEBELUM frontier sudah diterima ke @DivisionId (atau frontier = step ber-bundle
--   pertama, tidak ada step sebelumnya), DAN (c) TIDAK ada baris milik @DivisionId utk step
--   frontier itu yang masih menunggu diterima (received_at IS NULL) -- baris begitu hanya
--   boleh direvisi lewat tab Dikirim (SIS_Station_PendingHandover/EDIT), bukan ditambah baris
--   baru, sampai diterima. (dipakai sebagai @ArticleWorkflowId saat submit Serahkan lewat
--   endpoint complete existing, action CREATE di SIS_WorkflowLog_Manage -- TIDAK ada
--   endpoint/SP baru utk Serahkan itu sendiri). NextDivisionName = tujuan serah berikutnya
--   (murni informasi, dikunci ulang oleh server saat submit, sama seperti SIS_Bundle_ScanInfo).
--
--   SIS_Station_Counts: 3 angka (Masuk/Dikerjakan/Dikirim) utk strip kartu angka besar di
--   atas /station. Masuk & Dikirim pakai definisi yang sama dengan SIS_Station_PendingReceives
--   & SIS_Station_PendingHandover (level baris log, boleh bundle atau non-bundle); Dikerjakan
--   pakai definisi yang sama dengan SIS_Station_InProgress (level bundle).
--
--   Tab "Dikirim" (dulu "Diserahkan") memakai ULANG SIS_Station_PendingHandover -- sejak
--   Prompt 23 juga menampilkan baris step terakhir (H+1, lihat komentar di atas), bukan
--   lagi cuma baris yang ada tujuan serah. Tidak dibuat SP SIS_Station_Outbound terpisah
--   supaya tidak duplikasi logika.
--
--   Fix: SIS_Station_PendingHandover (+ SIS_Station_Counts) kini JUGA menampilkan baris
--   Bundling yang sudah received_at (auto-diterima Line tujuan saat dibuat, lihat
--   SIS_Bundle_Manage CREATE @ResourceId) selama bundle itu masih WIP murni (belum ada log
--   step berikutnya/is_bundling = 0) DAN masih dalam jendela 1 jam sejak dibuat -- client
--   menukar tombol Edit jadi Hapus untuk baris ini (ReceivedAt terisi), dipakai membatalkan
--   bundle yang salah tanpa menunggu revisi dari divisi tujuan. Lewat 1 jam, baris hilang
--   dari OUT dan SIS_Bundle_Manage DELETE ikut menolak (lihat catatan di file itu).
--
--   Prompt 23: SIS_Station_InProgress kini juga menyertakan style/color artikel (murni data
--   tambahan, tidak mengubah alur kartu bundle) supaya pencarian teks WAJIB di tab WIP bisa
--   menyaring kartu bundle dan kartu non-bundle dengan field yang sama. SIS_Station_Counts
--   DikerjakanCount kini menjumlahkan kartu bundle (definisi SIS_Station_InProgress) DENGAN
--   kartu non-bundle (definisi SIS_Station_ActiveWork), supaya angka WIP di strip atas
--   konsisten dengan isi tab gabungan.
--
-- Prompt 24: SIS_Station_ActiveWork sekarang UNION dua sumber kartu WIP -- step non-bundle
--   (IsBundling = 0, seperti sebelumnya) DAN step Bundling implisit (is_bundling = 1,
--   IsBundling = 1) milik @DivisionId, yaitu kartu "Buat Bundle" di station divisi Bundling.
--   Baris IsBundling = 1 TIDAK membawa SizesJson (detail per size diambil client lewat
--   SIS_Article_BundleSummary saat modal dibuka) -- sebagai gantinya bawa ringkasan
--   BundleCount/TotalBundleQty/TotalOrderQty untuk teks ringkas di kartu. SIS_Station_Counts
--   DikerjakanCount diperluas sejalan (requires_bundle = 0 OR is_bundling = 1).
--   SIS_Station_PendingHandover kini juga membawa ArticleId, IsBundling, dan data penjahit
--   bundle (BundleResourceId/BundleResourceName/BundleRemarks, DIBEDAKAN dari
--   ResourceName yang di baris Bundling berarti pelaksana BUNDLING, bukan penjahit) --
--   dipakai tombol Edit bundle di tab OUT (menggantikan Revisi/Batal Serah utk baris ini).
--
-- Fix: SIS_Station_InProgress kini juga membawa Remarks (bundles.remarks, Prompt 35) supaya
--   pencarian teks di tab WIP bisa menyaring lewat catatan bebas bundle, bukan cuma
--   project/artikel/step/serial. SIS_Station_ActiveWork (kedua cabang UNION) kini membawa
--   WorkStartedAt -- dipakai default urutan tab WIP (waktu diterima/dikerjakan paling baru di
--   atas, flat tanpa grouping project): waktu terakhir ADA aktivitas relevan kartu ini, yaitu
--   yang TERBARU antara (a) received_at baris log step SEBELUMNYA yang mengantarkan pekerjaan
--   ke step ini, dan (b) created_at baris log step ini sendiri (kalau sudah pernah dicicil).
--   NULL kalau step ini belum tersentuh sama sekali (step pertama artikel, belum ada input) --
--   client menaruhnya paling bawah.
--
-- Prompt 56 -- lock di tab OUT:
--   SIS_Station_PendingHandover membawa LockId/IsLocked/HasPendingUnlock/CanEdit/CanDelete.
--   CanEdit/CanDelete SEKARANG murni turunan lock (= lock_id IS NULL) -- SEMUA guard waktu
--   (jendela 1 jam bundle, H+1 step terakhir, "sudah diterima") DIHAPUS dari SP ini maupun
--   dari SIS_Station_Counts, sejalan dengan Prompt 55. Validasi saldo tetap di SP tulis.
--   Filter @Date diperlebar 7 -> 90 hari supaya chip "Belum lock" tetap bisa dituju.
--   SIS_Station_UnlockedDates (baru): tanggal kirim yang masih punya baris belum lock + jumlah
--   barisnya, dasar chip merah di atas daftar OUT.
--   SIS_Station_Counts menambah OutUnlockedCount (semua tanggal) untuk teks "n belum lock"
--   di bawah angka OUT. Cakupan baris UnlockedDates & OutUnlockedCount sengaja dibatasi ke
--   baris yang bisa MUNCUL di tab OUT -- lihat catatan di masing-masing.
--
-- Prompt 40: SIS_Station_PendingReceives kini membawa SuggestedReceiverResourceId/Name --
--   counterpart dari resource pengirim (awl.resource_id) yang valid terhadap @DivisionId
--   (hidup + aktif + division_id = @DivisionId), NULL bila tidak ada. Dipakai client sebagai
--   penerima default pada penerimaan manual (tab "Masuk"/IN) -- operator sesi tetap menang
--   kalau diganti manual, dan "Terima Borongan" memakai penerima default PER BARIS, bukan satu
--   operator untuk semua. SP baru SIS_Station_ReceiverOptions (di bawah) -- dropdown "Diterima
--   Oleh" wajib pada form Kirim Hasil ketika step tujuan auto_receive = 1 tapi counterpart
--   pengirim tidak valid (lihat SIS_Bundle_ScanInfo.ReceiverPickerRequired).

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Station_PendingReceives
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: default_resource_id stasiun (NULL = stasiun
                                -- tidak terkunci ke Line manapun, lihat SIS_Station_Counts)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT awl.workflow_log_id AS WorkflowLogId, awl.article_workflow_id AS ArticleWorkflowId,
           p.project_name AS ProjectName, p.no_po AS NoPo, buy.buyer_name AS BuyerName, a.article_name AS ArticleName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           awl.qty_ok AS QtyOk, awl.created_at AS SentAt,
           d.division_name AS FromDivisionName,
           awl.bundle_id AS BundleId, b.bundle_no AS BundleNo, p.bundle_letter AS BundleLetter, b.serial AS Serial,
           spd.size_name AS SizeName, spd.sort_order AS SizeSortOrder,
           awl.updated_at AS UpdatedAt,
           -- Prompt 28: badge "Penyesuaian" di tab Masuk untuk baris ADJUSTMENT (qty_ok > 0).
           CASE WHEN awl.log_type = 'ADJUSTMENT' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsAdjustment,
           -- Prompt 40: counterpart resource pengirim (awl.resource_id), valid terhadap
           -- @DivisionId (hidup + aktif + division_id = @DivisionId) -- dipakai penerima
           -- default saat "Terima" manual, NULL bila tidak ada.
           cprr.resource_id AS SuggestedReceiverResourceId, cprr.resource_name AS SuggestedReceiverResourceName
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN buyers buy ON buy.buyer_id = p.customer_id
    INNER JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN resources br ON br.resource_id = b.resource_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources sndr ON sndr.resource_id = awl.resource_id
    LEFT JOIN resources cprr ON cprr.resource_id = sndr.counterpart_resource_id
        AND cprr.deleted_at IS NULL AND cprr.is_active = 1 AND cprr.division_id = @DivisionId
    WHERE awl.target_division_id = @DivisionId
      AND awl.received_at IS NULL
      AND awl.deleted_at IS NULL
      -- Prompt 28: baris qty_ok = 0 (NORMAL maupun ADJUSTMENT) tidak pernah butuh diterima --
      -- tidak ada barang fisik yang benar-benar berpindah ke divisi ini.
      AND awl.qty_ok > 0
      -- Prompt 22b: stasiun terkunci ke satu Line (resource) hanya melihat bundle yang
      -- ditugaskan ke Line itu; item non-bundle atau bundle tanpa Line, dan stasiun yang
      -- tidak terkunci (@ResourceId NULL), tetap tampil seperti sebelumnya.
      -- Fix: Line hanya relevan kalau resource Line itu SATU DIVISI dengan stasiun ini
      -- (mis. Line A1/A2 sama-sama di Sew+Trim+QC) -- di situ splitting antar Line
      -- memang dimaksudkan. Kalau Line bundle beda divisi dari stasiun ini (mis. bundle
      -- ditugaskan ke Line A1 tapi sedang menuju stasiun DTF/Packing yang dikunci ke
      -- resource "Team"-nya sendiri, bukan Line), filter Line tidak relevan -- jangan
      -- disembunyikan, karena resource stasiun tujuan memang tidak akan pernah sama
      -- dengan Line pengirim.
      AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR br.division_id <> @DivisionId)
    ORDER BY awl.created_at ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_ActiveWork
    @DivisionId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT * FROM (
        SELECT aw.article_workflow_id AS ArticleWorkflowId,
               a.article_id AS ArticleId,
               p.project_name AS ProjectName, p.no_po AS NoPo, a.article_name AS ArticleName,
               -- Prompt 57 (susulan): buyer + PIC project -- dipakai pencarian teks tab WIP.
               buy.buyer_name AS BuyerName, pic.employee_name AS PicName,
               a.style AS Style, a.color AS Color,
               aw.step_name AS StepName,
               CAST(0 AS BIT) AS IsBundling,
               CASE WHEN aw.sort_order = (
                   SELECT MAX(aw3.sort_order) FROM article_workflows aw3
                   WHERE aw3.article_id = aw.article_id AND aw3.deleted_at IS NULL
               ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep,
               (
                   SELECT TOP 1 aw4.division_id
                   FROM article_workflows aw4
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.inactive_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionId,
               (
                   SELECT TOP 1 d4.division_name
                   FROM article_workflows aw4
                   INNER JOIN divisions d4 ON d4.division_id = aw4.division_id
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.inactive_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionName,
               (
                   SELECT asz.article_size_id AS Id, spd.size_name AS SizeName, asz.qty AS QtyOrder,
                          ISNULL((
                              SELECT SUM(awl.qty_ok)
                              FROM article_workflow_logs awl
                              WHERE awl.article_workflow_id = aw.article_workflow_id
                                AND awl.article_size_id = asz.article_size_id
                                AND awl.deleted_at IS NULL
                          ), 0) AS QtyRecorded
                   FROM article_sizes asz
                   INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                   WHERE asz.article_id = aw.article_id AND asz.deleted_at IS NULL
                   ORDER BY spd.sort_order
                   FOR JSON PATH
               ) AS SizesJson,
               CAST(NULL AS INT) AS BundleCount,
               CAST(NULL AS INT) AS TotalBundleQty,
               CAST(NULL AS INT) AS TotalOrderQty,
               CAST(NULL AS NVARCHAR(MAX)) AS StockCuttingJson,
               (
                   SELECT MAX(ts) FROM (
                       SELECT MAX(pr.received_at) AS ts
                       FROM article_workflow_logs pr
                       INNER JOIN article_workflows aw_prev ON aw_prev.article_workflow_id = pr.article_workflow_id
                       WHERE aw_prev.article_id = aw.article_id AND aw_prev.deleted_at IS NULL
                         AND aw_prev.sort_order = (
                             SELECT MAX(aw_p2.sort_order) FROM article_workflows aw_p2
                             WHERE aw_p2.article_id = aw.article_id AND aw_p2.deleted_at IS NULL AND aw_p2.sort_order < aw.sort_order
                         )
                         AND pr.received_at IS NOT NULL AND pr.deleted_at IS NULL
                       UNION ALL
                       SELECT MAX(self.created_at) AS ts
                       FROM article_workflow_logs self
                       WHERE self.article_workflow_id = aw.article_workflow_id AND self.deleted_at IS NULL
                   ) x
               ) AS WorkStartedAt,
               aw.sort_order AS SortOrder
        FROM article_workflows aw
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN buyers buy ON buy.buyer_id = p.customer_id
        LEFT JOIN employees pic ON pic.employee_id = p.project_pic
        WHERE aw.division_id = @DivisionId
          AND aw.deleted_at IS NULL
          AND aw.inactive_at IS NULL
          AND aw.requires_bundle = 0
          AND p.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND (
                p.manual_status IS NOT NULL
                OR (p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE))
                OR EXISTS (
                    SELECT 1 FROM article_workflow_logs awl2
                    INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
                    INNER JOIN articles a2 ON a2.article_id = aw2.article_id
                    WHERE a2.project_id = p.project_id
                      AND awl2.deleted_at IS NULL AND aw2.deleted_at IS NULL AND a2.deleted_at IS NULL
                )
              )

        UNION ALL

        -- Prompt 24: kartu "Buat Bundle" -- step Bundling implisit (is_bundling = 1) milik
        -- divisi ini. Tanpa SizesJson (detail per size lewat SIS_Article_BundleSummary saat
        -- modal dibuka) -- cukup ringkasan jumlah bundle vs order untuk teks kartu.
        SELECT aw.article_workflow_id AS ArticleWorkflowId,
               a.article_id AS ArticleId,
               p.project_name AS ProjectName, p.no_po AS NoPo, a.article_name AS ArticleName,
               buy.buyer_name AS BuyerName, pic.employee_name AS PicName,
               a.style AS Style, a.color AS Color,
               aw.step_name AS StepName,
               CAST(1 AS BIT) AS IsBundling,
               CASE WHEN aw.sort_order = (
                   SELECT MAX(aw3.sort_order) FROM article_workflows aw3
                   WHERE aw3.article_id = aw.article_id AND aw3.deleted_at IS NULL
               ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep,
               (
                   SELECT TOP 1 aw4.division_id
                   FROM article_workflows aw4
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.inactive_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionId,
               (
                   SELECT TOP 1 d4.division_name
                   FROM article_workflows aw4
                   INNER JOIN divisions d4 ON d4.division_id = aw4.division_id
                   WHERE aw4.article_id = aw.article_id AND aw4.deleted_at IS NULL AND aw4.inactive_at IS NULL AND aw4.sort_order > aw.sort_order
                   ORDER BY aw4.sort_order ASC
               ) AS NextDivisionName,
               CAST(NULL AS NVARCHAR(MAX)) AS SizesJson,
               (
                   SELECT COUNT(*) FROM bundles b
                   INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
                   WHERE asz.article_id = aw.article_id AND b.deleted_at IS NULL
               ) AS BundleCount,
               (
                   SELECT ISNULL(SUM(b.qty), 0) FROM bundles b
                   INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
                   WHERE asz.article_id = aw.article_id AND b.deleted_at IS NULL
               ) AS TotalBundleQty,
               (
                   SELECT ISNULL(SUM(asz.qty), 0) FROM article_sizes asz
                   WHERE asz.article_id = aw.article_id AND asz.deleted_at IS NULL
               ) AS TotalOrderQty,
               -- Fix: sisa hasil Cutting yang sudah diterima divisi Bundling tapi belum
               -- dijadikan bundle, PER SIZE (bukan lagi dijumlahkan jadi satu angka) --
               -- definisi tiap baris sama dengan StockCutting per size di
               -- SIS_Article_BundleSummary, dipakai teks ringkas kartu "Buat Bundle"
               -- (StationDevice.razor) supaya operator langsung tahu size mana yang sudah
               -- siap dibundle tanpa buka modal dulu. Size dengan stock 0 tidak disertakan.
               -- Fix (modul Cutting seri 78-81): yang dikurangi hanya bundle source <> 'CUTTING'
               -- -- sama persis dengan SIS_Article_BundleSummary (alasan lengkap ada di
               -- sql/sp_Bundle_Select.sql). Tanpa filter ini kartu WIP artikel yang bundlenya
               -- dari hamparan menampilkan stok cutting minus besar. Efek samping yang
               -- diinginkan: size yang hasilnya 0 kini tersaring oleh StockCutting <> 0, jadi
               -- artikel jalur hamparan tidak lagi memunculkan teks "stok cutting" palsu.
               (
                   SELECT spd6.size_name AS SizeName, x6.StockCutting AS StockCutting
                   FROM article_sizes asz6
                   INNER JOIN size_pack_details spd6 ON spd6.size_pack_detail_id = asz6.size_pack_detail_id
                   CROSS APPLY (
                       SELECT
                           ISNULL((
                               SELECT SUM(awl5.qty_ok)
                               FROM article_workflow_logs awl5
                               WHERE awl5.article_workflow_id = (
                                   SELECT TOP 1 aw5.article_workflow_id
                                   FROM article_workflows aw5
                                   WHERE aw5.article_id = aw.article_id AND aw5.deleted_at IS NULL AND aw5.inactive_at IS NULL AND aw5.requires_bundle = 0
                                   ORDER BY aw5.sort_order DESC
                               )
                               AND awl5.article_size_id = asz6.article_size_id
                               AND awl5.deleted_at IS NULL AND awl5.received_at IS NOT NULL
                           ), 0)
                           -
                           ISNULL((
                               SELECT SUM(CASE WHEN ISNULL(b.source, 'MANUAL') <> 'CUTTING' THEN b.qty ELSE 0 END) FROM bundles b
                               WHERE b.article_size_id = asz6.article_size_id AND b.deleted_at IS NULL
                           ), 0) AS StockCutting
                   ) x6
                   WHERE asz6.article_id = aw.article_id AND asz6.deleted_at IS NULL
                     AND x6.StockCutting <> 0
                   ORDER BY spd6.sort_order
                   FOR JSON PATH
               ) AS StockCuttingJson,
               (
                   SELECT MAX(ts) FROM (
                       SELECT MAX(pr.received_at) AS ts
                       FROM article_workflow_logs pr
                       INNER JOIN article_workflows aw_prev ON aw_prev.article_workflow_id = pr.article_workflow_id
                       WHERE aw_prev.article_id = aw.article_id AND aw_prev.deleted_at IS NULL
                         AND aw_prev.sort_order = (
                             SELECT MAX(aw_p2.sort_order) FROM article_workflows aw_p2
                             WHERE aw_p2.article_id = aw.article_id AND aw_p2.deleted_at IS NULL AND aw_p2.sort_order < aw.sort_order
                         )
                         AND pr.received_at IS NOT NULL AND pr.deleted_at IS NULL
                       UNION ALL
                       SELECT MAX(bun.created_at) AS ts
                       FROM bundles bun
                       INNER JOIN article_sizes asz7 ON asz7.article_size_id = bun.article_size_id
                       WHERE asz7.article_id = aw.article_id AND bun.deleted_at IS NULL
                   ) x
               ) AS WorkStartedAt,
               aw.sort_order AS SortOrder
        FROM article_workflows aw
        INNER JOIN articles a ON a.article_id = aw.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN buyers buy ON buy.buyer_id = p.customer_id
        LEFT JOIN employees pic ON pic.employee_id = p.project_pic
        WHERE aw.division_id = @DivisionId
          AND aw.deleted_at IS NULL
          AND aw.is_bundling = 1
          AND p.deleted_at IS NULL
          AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
          AND (
                p.manual_status IS NOT NULL
                OR (p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE))
                OR EXISTS (
                    SELECT 1 FROM article_workflow_logs awl2
                    INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
                    INNER JOIN articles a2 ON a2.article_id = aw2.article_id
                    WHERE a2.project_id = p.project_id
                      AND awl2.deleted_at IS NULL AND aw2.deleted_at IS NULL AND a2.deleted_at IS NULL
                )
              )
    ) x
    ORDER BY ProjectName ASC, ArticleName ASC, SortOrder ASC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_PendingHandover
    @DivisionId INT,
    @ResourceId INT = NULL,    -- Prompt 22b: default_resource_id stasiun -- baris ini DIBUAT
                                -- oleh divisi ini sendiri, jadi awl.resource_id = pelaksana
                                -- (dipaksa = resource stasiun saat stasiun terkunci, lihat
                                -- EffectiveResourceId), bukan bundles.resource_id seperti di
                                -- PendingReceives/InProgress (itu Line TUJUAN, ini Line PENGIRIM).
    -- Ad hoc (2026-09-28): filter tanggal tab OUT -- hanya membatasi RIWAYAT (baris yang sudah
    -- diterima / step terakhir). Baris yang masih menunggu diterima tetap tampil tanpa batas
    -- hari supaya pekerjaan yang belum tuntas tidak pernah hilang dari layar operator.
    -- Prompt 56: rentang diperlebar 7 -> 90 hari. Chip "Belum lock" (SIS_Station_UnlockedDates)
    -- bisa menunjuk tanggal jauh di belakang; kalau filter tetap 7 hari, chip itu jadi buntu
    -- dan baris lama tidak pernah bisa di-lock dari stasiun.
    @Date DATE = NULL          -- NULL = hari ini; maksimal 90 hari ke belakang.
AS
BEGIN
    SET NOCOUNT ON;

    IF @Date IS NULL SET @Date = CAST(SYSDATETIME() AS DATE);

    IF @Date > CAST(SYSDATETIME() AS DATE)
        OR @Date < DATEADD(DAY, -90, CAST(SYSDATETIME() AS DATE))
    BEGIN
        RAISERROR('Tanggal hanya boleh hari ini sampai 90 hari ke belakang.', 16, 1);
        RETURN;
    END

    SELECT awl.workflow_log_id AS WorkflowLogId, awl.article_workflow_id AS ArticleWorkflowId,
           a.article_id AS ArticleId,
           p.project_name AS ProjectName, p.no_po AS NoPo, buy.buyer_name AS BuyerName, a.article_name AS ArticleName,
           -- Prompt 57 (susulan): PIC project -- dipakai pencarian teks tab OUT di client.
           pic.employee_name AS PicName,
           a.style AS Style, a.color AS Color,
           aw.step_name AS StepName,
           -- Prompt 24: true kalau baris ini log step Bundling implisit (bundle dibuat lewat
           -- kartu "Buat Bundle") -- client memakai ini utk ganti Revisi/Batal Serah jadi Edit.
           aw.is_bundling AS IsBundling,
           awl.bundle_id AS BundleId, b.bundle_no AS BundleNo, p.bundle_letter AS BundleLetter, b.serial AS Serial,
           -- Fix: baris Bundling (awl.article_size_id SELALU NULL, lihat SIS_Bundle_Manage
           -- CREATE) -- ukuran diambil dari bundles.article_size_id lewat COALESCE supaya
           -- badge ukuran di kartu OUT & prefill modal Edit bundle tidak kosong.
           COALESCE(b.article_size_id, awl.article_size_id) AS ArticleSizeId, spd.size_name AS SizeName, spd.sort_order AS SizeSortOrder,
           awl.qty_ok AS QtyOk, awl.qty_reject_print AS QtyRejectPrint,
           awl.qty_reject_fabric AS QtyRejectFabric, awl.qty_reject_sewing AS QtyRejectSewing,
           -- Fix: dua kolom ini ada di StationPendingHandoverRow (C#) sejak Prompt 28 tapi
           -- kelupaan ditambah di SELECT ini -- bikin EF Core FromSql error "required column
           -- 'QtyLost' was not present" begitu tab Dikirim dibuka.
           awl.qty_reject_rework AS QtyRejectRework, awl.qty_lost AS QtyLost,
           awl.remark AS Remark,
           td.division_name AS TargetDivisionName,
           -- Prompt 23: baris step terakhir (target_division_id NULL, jendela H+1) -- lihat
           -- komentar besar di atas file.
           CASE WHEN awl.target_division_id IS NULL THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep,
           -- Prompt 49: id mentah pelaksana baris ini (selain nama di bawah) -- dipakai client
           -- sebagai default terpilih di picker "Pelaksana" pada modal Revisi/Edit.
           awl.resource_id AS ResourceId,
           r.resource_name AS ResourceName,
           awl.created_at AS CreatedAt,
           awl.updated_at AS UpdatedAt,
           -- Fix: dipakai client utk membedakan tombol Edit (belum diterima) vs Hapus (sudah
           -- diterima/WIP, lihat kondisi WHERE di bawah) pada baris Bundling.
           awl.received_at AS ReceivedAt,
           CASE WHEN awl.bundle_id IS NULL THEN (
               SELECT asz2.article_size_id AS Id, spd2.size_name AS SizeName
               FROM article_sizes asz2
               INNER JOIN size_pack_details spd2 ON spd2.size_pack_detail_id = asz2.size_pack_detail_id
               WHERE asz2.article_id = aw.article_id AND asz2.deleted_at IS NULL
               ORDER BY spd2.sort_order
               FOR JSON PATH
           ) ELSE NULL END AS SizesJson,
           -- Prompt 12e: opsi divisi tujuan utk form Revisi (REVISE_HANDOVER) -- daftar
           -- distinct divisi yang dipakai step manapun di workflow artikel ini.
           (
               SELECT DISTINCT aw3.division_id AS Id, d3.division_name AS DivisionName
               FROM article_workflows aw3
               INNER JOIN divisions d3 ON d3.division_id = aw3.division_id
               WHERE aw3.article_id = a.article_id AND aw3.deleted_at IS NULL AND aw3.inactive_at IS NULL
               FOR JSON PATH
           ) AS TargetDivisionOptionsJson,
           -- Prompt 24: data penjahit BUNDLE (bundles.resource_id/employee_id) --
           -- DIBEDAKAN dari ResourceName di atas yang untuk baris Bundling berarti pelaksana
           -- bundling (awl.resource_id), bukan penjahit. Dipakai prefill modal Edit bundle.
           -- Prompt 35: BundleRemarks (dulu BundleResourcePersonName/resource_person_name) --
           -- catatan bebas bundle, dikirim balik apa adanya saat submit Edit dari station
           -- (tidak ada input editor di station, hanya BundleManager.razor admin).
           b.resource_id AS BundleResourceId,
           bres.resource_name AS BundleResourceName,
           b.remarks AS BundleRemarks,
           b.employee_id AS BundleEmployeeId,
           bemp.employee_name AS BundleEmployeeName,
           -- Prompt 56: status lock baris ini. CanEdit/CanDelete SEKARANG murni turunan lock --
           -- jendela 1 jam / H+1 / "sudah diterima" tidak lagi menentukan apa pun (lihat
           -- Prompt 55). Validasi saldo tetap di SP tulis; UI tidak menghitungnya, cukup
           -- menampilkan pesan error dari SP.
           awl.lock_id AS LockId,
           CAST(CASE WHEN awl.lock_id IS NULL THEN 0 ELSE 1 END AS BIT) AS IsLocked,
           CAST(CASE WHEN EXISTS (
                    SELECT 1
                    FROM unlock_request_items uri
                    INNER JOIN unlock_requests ur ON ur.request_id = uri.request_id
                    WHERE uri.workflow_log_id = awl.workflow_log_id
                      AND ur.approved_at IS NULL AND ur.rejected_at IS NULL AND ur.deleted_at IS NULL
                ) THEN 1 ELSE 0 END AS BIT) AS HasPendingUnlock,
           CAST(CASE WHEN awl.lock_id IS NULL THEN 1 ELSE 0 END AS BIT) AS CanEdit,
           CAST(CASE WHEN awl.lock_id IS NULL THEN 1 ELSE 0 END AS BIT) AS CanDelete,
           -- Kode periode gajian lock yang sedang berlaku ('26-w40'), NULL bila belum
           -- di-lock. Ditampilkan di samping ikon gembok di tab OUT -- periode sebuah baris
           -- SELALU diturunkan dari lock_id, tidak pernah dari created_at (Prompt 55).
           lpp.period_code AS LockPeriodCode
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN buyers buy ON buy.buyer_id = p.customer_id
    LEFT JOIN employees pic ON pic.employee_id = p.project_pic
    LEFT JOIN divisions td ON td.division_id = awl.target_division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = COALESCE(b.article_size_id, awl.article_size_id)
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = awl.resource_id
    LEFT JOIN resources bres ON bres.resource_id = b.resource_id
    LEFT JOIN employees bemp ON bemp.employee_id = b.employee_id AND bemp.deleted_at IS NULL
    -- Prompt 57 (susulan): periode gajian lock aktif baris ini.
    LEFT JOIN workflow_locks lwl ON lwl.lock_id = awl.lock_id
    LEFT JOIN payroll_periods lpp ON lpp.payroll_period_id = lwl.payroll_period_id
    WHERE awl.division_id = @DivisionId
      AND awl.deleted_at IS NULL
      AND (
            -- Prompt 28: baris qty_ok = 0 tidak pernah butuh diterima -- jangan tampilkan
            -- sebagai "menunggu diterima" di tab Dikirim juga.
            -- Fix: baris yang DIKIRIM pada @Date tetap tampil walau sudah diterima (received_at
            -- terisi) -- supaya operator tetap bisa melihat riwayat kiriman tanggal itu di tab
            -- OUT, bukan cuma yang masih menunggu. Baris begitu jadi read-only di client
            -- (tanpa Revisi/Batal Serah, lihat StationDevice.razor) karena sudah terkunci.
            -- Baris LAWAS yang belum diterima tetap tampil tanpa batas hari (received_at IS
            -- NULL saja, tanpa syarat tanggal) -- perilaku lama dipertahankan.
            (awl.target_division_id IS NOT NULL AND awl.qty_ok > 0
             AND (awl.received_at IS NULL OR CAST(awl.created_at AS DATE) = @Date))
            -- Prompt 28: baris ADJUSTMENT dengan qty_ok = 0 SELALU target_division_id NULL
            -- (lihat SIS_WorkflowLog_Manage ADJUST) terlepas dari step ini step terakhir
            -- artikel atau bukan -- batasi cabang "step terakhir" ini ke baris NORMAL saja
            -- supaya baris ADJUSTMENT begitu tidak nyasar tampil di sini.
            -- Prompt 56: jendela H+1 DIHAPUS -- baris step terakhir tampil murni berdasarkan
            -- tanggal kirim. Baris lama yang belum di-lock ditemukan lewat chip "Belum lock"
            -- (SIS_Station_UnlockedDates) yang memindahkan filter tanggal ke sana.
            -- Prompt 82: baris 'Hilang'/'Ketemu' (catatan selisih) dan baris 'Creation'
            -- bundle ANAK hasil migrasi juga target_division_id NULL + log_type NORMAL --
            -- semuanya qty 0 dan tidak ada yang bisa direvisi/dibatalkan di tab OUT.
            -- Baris Bundling (JUGA log_kind 'Creation') tetap tampil lewat cabang PERTAMA
            -- di atas karena target_division_id-nya terisi dan qty_ok > 0.
            OR (awl.target_division_id IS NULL AND awl.log_type = 'NORMAL'
                AND awl.log_kind NOT IN ('Hilang', 'Ketemu', 'Creation')
                AND CAST(awl.created_at AS DATE) = @Date)
            -- Prompt 56: cabang khusus "bundle Bundling auto-diterima, jendela 1 jam" DIHAPUS.
            -- Tanpa batas waktunya, cabang itu sepenuhnya tertutup cabang pertama di atas
            -- (baris Bundling selalu punya target_division_id dan qty_ok > 0), jadi tidak ada
            -- baris yang hilang -- yang berubah cuma: bundle lama tetap bisa diedit/dihapus
            -- selama belum di-lock, bukan cuma 1 jam pertama.
          )
      AND (@ResourceId IS NULL OR awl.resource_id IS NULL OR awl.resource_id = @ResourceId)
    ORDER BY awl.created_at DESC;
END;
GO

CREATE OR ALTER PROCEDURE SIS_Station_RecentReceived
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: filter ke received_by_resource_id (siapa yang
                                -- menerima), dipaksa = resource stasiun saat terkunci --
                                -- konsisten dengan tombol Batal Terima yang cuma masuk akal
                                -- untuk baris yang diterima Line ini sendiri.
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 20
           awl.workflow_log_id AS WorkflowLogId,
           b.bundle_no AS BundleNo, p.bundle_letter AS BundleLetter, b.serial AS Serial,
           a.article_name AS ArticleName,
           spd.size_name AS SizeName,
           aw.step_name AS StepName,
           d.division_name AS DivisionAsalName,
           awl.qty_ok AS QtyOk,
           awl.received_at AS ReceivedAt,
           r.resource_name AS ReceivedByResourceName,
           CASE WHEN awl.bundle_id IS NOT NULL AND EXISTS (
               SELECT 1
               FROM article_workflow_logs awl2
               INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
               WHERE awl2.bundle_id = awl.bundle_id AND awl2.deleted_at IS NULL
                 AND aw2.article_id = aw.article_id AND aw2.sort_order > aw.sort_order
           ) THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS CanUnreceive
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects p ON p.project_id = a.project_id
    INNER JOIN divisions d ON d.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = awl.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources r ON r.resource_id = awl.received_by_resource_id
    WHERE awl.target_division_id = @DivisionId
      AND awl.received_at IS NOT NULL
      AND awl.deleted_at IS NULL
      AND (@ResourceId IS NULL OR awl.received_by_resource_id IS NULL OR awl.received_by_resource_id = @ResourceId)
    ORDER BY awl.received_at DESC;
END;
GO

-- Prompt 12e: tab "Dikerjakan" -- lihat komentar definisi besar di atas file (Fix susulan:
-- Base = semua bundle hidup, Frontier = step ber-bundle yang sisa kuotanya masih > 0).
CREATE OR ALTER PROCEDURE SIS_Station_InProgress
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: lihat komentar SIS_Station_PendingReceives
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Base AS (
        SELECT
            b.bundle_id, b.serial, b.bundle_no, p.bundle_letter, b.qty,
            a.article_id, a.article_name, a.style, a.color,
            p.project_name, p.no_po,
            buy.buyer_name,
            -- Prompt 57 (susulan): PIC project -- dipakai pencarian teks tab WIP di client.
            pic.employee_name AS pic_name,
            spd.size_name,
            rr.resource_name AS tailor_name,
            emp.employee_name AS employee_name,
            b.remarks AS remarks,
            b.resource_id AS bundle_resource_id,
            rr.division_id AS bundle_resource_division_id
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
        INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
        INNER JOIN buyers buy ON buy.buyer_id = p.customer_id
        LEFT JOIN employees pic ON pic.employee_id = p.project_pic
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources rr ON rr.resource_id = b.resource_id
        LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
        WHERE b.deleted_at IS NULL
    ),
    -- Prompt 82: step FRONTIER per bundle = step ber-bundle PERTAMA yang sort_order-nya
    -- di atas step terakhir yang sudah punya baris 'Creation'/'Kirim' untuk bundle ini.
    -- [MENGGANTIKAN definisi Prompt 14b "step pertama yang sisa kuotanya masih > 0"]:
    -- di model pemecahan, satu baris Kirim MENGHABISKAN seluruh isi bundle (qty OK +
    -- anak + selisih = qty masuk), jadi tidak ada lagi "sisa kuota"/baris susulan yang
    -- perlu dikejar. Rumus kuota lama juga tidak bisa dipakai lagi: reject sekarang hidup
    -- sebagai bundle ANAK, bukan di kolom qty_reject_*, sehingga QtySudah selalu terlihat
    -- kurang dan bundle tidak pernah lepas dari step yang sudah dikirim.
    -- Bonus: bundle anak -- yang rantai lognya dimulai dari baris 'Creation' di tengah
    -- workflow -- otomatis ber-frontier di step tujuannya, bukan di step pertama artikel.
    Frontier AS (
        SELECT bs.bundle_id, f.ArticleWorkflowId, f.StepName, f.SortOrder, f.DivisionId, f.PrevArticleWorkflowId
        FROM Base bs
        CROSS APPLY (
            SELECT TOP 1 q.ArticleWorkflowId, q.StepName, q.SortOrder, q.DivisionId, q.PrevArticleWorkflowId
            FROM (
                SELECT aw.article_workflow_id AS ArticleWorkflowId, aw.step_name AS StepName,
                       aw.sort_order AS SortOrder, aw.division_id AS DivisionId,
                       LAG(aw.article_workflow_id) OVER (ORDER BY aw.sort_order) AS PrevArticleWorkflowId
                FROM article_workflows aw
                WHERE aw.article_id = bs.article_id AND aw.deleted_at IS NULL AND aw.inactive_at IS NULL AND aw.requires_bundle = 1
            ) q
            WHERE q.SortOrder > ISNULL((
                SELECT MAX(aw9.sort_order)
                FROM article_workflow_logs awl9
                INNER JOIN article_workflows aw9 ON aw9.article_workflow_id = awl9.article_workflow_id
                WHERE awl9.bundle_id = bs.bundle_id AND awl9.deleted_at IS NULL
                  AND awl9.log_kind IN ('Creation', 'Kirim')
            ), -1)
            ORDER BY q.SortOrder ASC
        ) f
    )
    SELECT
        lr.workflow_log_id AS WorkflowLogId,
        bs.bundle_id AS BundleId,
        bs.serial AS Serial,
        bs.bundle_no AS BundleNo,
        bs.bundle_letter AS BundleLetter,
        bs.article_id AS ArticleId,
        bs.project_name AS ProjectName,
        bs.no_po AS NoPo,
        bs.buyer_name AS BuyerName,
        bs.pic_name AS PicName,
        bs.article_name AS ArticleName,
        bs.style AS Style, bs.color AS Color,
        bs.size_name AS SizeName,
        bs.qty AS Qty,
        bs.tailor_name AS TailorName,
        bs.employee_name AS EmployeeName,
        bs.remarks AS Remarks,
        lr.received_at AS ReceivedAt,
        fr.ArticleWorkflowId AS NextArticleWorkflowId,
        fr.StepName AS NextStepName,
        nd.division_name AS NextDivisionName,
        CASE WHEN fr.SortOrder = (
            SELECT MAX(sort_order) FROM article_workflows WHERE article_id = bs.article_id AND deleted_at IS NULL
        ) THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsLastStep
    FROM Base bs
    INNER JOIN Frontier fr ON fr.bundle_id = bs.bundle_id
    -- Baris TERAKHIR yang membawa bundle ini MASUK ke @DivisionId (baris manapun yang
    -- target_division_id = @DivisionId & sudah diterima) -- dipakai utk WorkflowLogId/
    -- ReceivedAt/Batal Terima, bukan lagi harus baris log paling akhir secara keseluruhan.
    OUTER APPLY (
        SELECT TOP 1 awl.workflow_log_id, awl.received_at
        FROM article_workflow_logs awl
        WHERE awl.bundle_id = bs.bundle_id AND awl.deleted_at IS NULL
          AND awl.target_division_id = @DivisionId AND awl.received_at IS NOT NULL
        ORDER BY awl.created_at DESC
    ) lr
    OUTER APPLY (
        SELECT TOP 1 aw2.division_id
        FROM article_workflows aw2
        WHERE aw2.article_id = bs.article_id AND aw2.deleted_at IS NULL AND aw2.inactive_at IS NULL AND aw2.sort_order > fr.SortOrder
        ORDER BY aw2.sort_order ASC
    ) nd2
    LEFT JOIN divisions nd ON nd.division_id = nd2.division_id
    WHERE fr.DivisionId = @DivisionId
      AND lr.workflow_log_id IS NOT NULL
      -- Bundle harus sudah "sampai" di @DivisionId utk step frontier ini: step frontier
      -- adalah step ber-bundle pertama (tidak ada step sebelumnya), ATAU step SEBELUM
      -- frontier sudah diterima ke @DivisionId (sama dengan pengecekan COMPLETE di
      -- SIS_Bundle_ScanInfo).
      AND (
            fr.PrevArticleWorkflowId IS NULL
            OR EXISTS (
                SELECT 1 FROM article_workflow_logs pr
                WHERE pr.article_workflow_id = fr.PrevArticleWorkflowId AND pr.bundle_id = bs.bundle_id
                  AND pr.deleted_at IS NULL AND pr.received_at IS NOT NULL AND pr.target_division_id = @DivisionId
            )
          )
      -- Selama masih ada baris susulan milik @DivisionId utk step frontier yang BELUM
      -- diterima divisi tujuan, jangan tampilkan lagi di Dikerjakan (biar operator revisi
      -- lewat tab Dikirim dulu, bukan malah menambah baris baru di atas baris yang pending).
      AND NOT EXISTS (
            SELECT 1 FROM article_workflow_logs pend
            WHERE pend.article_workflow_id = fr.ArticleWorkflowId AND pend.bundle_id = bs.bundle_id
              AND pend.deleted_at IS NULL AND pend.division_id = @DivisionId
              AND pend.target_division_id IS NOT NULL AND pend.received_at IS NULL
          )
      -- Fix: lihat komentar Line vs divisi di SIS_Station_PendingReceives.
      AND (@ResourceId IS NULL OR bs.bundle_resource_id IS NULL OR bs.bundle_resource_id = @ResourceId OR bs.bundle_resource_division_id <> @DivisionId)
    ORDER BY bs.project_name ASC, bs.article_name ASC, bs.bundle_no ASC;
END;
GO

-- Prompt 12e: strip 3 angka (Masuk/Dikerjakan/Dikirim) di atas /station. Masuk & Dikirim
-- pakai definisi baris yang sama dengan SIS_Station_PendingReceives/PendingHandover;
-- Dikerjakan pakai definisi bundle yang sama dengan SIS_Station_InProgress di atas.
CREATE OR ALTER PROCEDURE SIS_Station_Counts
    @DivisionId INT,
    @ResourceId INT = NULL     -- Prompt 22b: lihat komentar SIS_Station_PendingReceives
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (
            SELECT COUNT(*)
            FROM article_workflow_logs awl
            LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
            LEFT JOIN resources br ON br.resource_id = b.resource_id
            WHERE awl.target_division_id = @DivisionId AND awl.received_at IS NULL AND awl.deleted_at IS NULL
              -- Prompt 28: baris qty_ok = 0 tidak pernah butuh diterima -- lihat SIS_Station_PendingReceives.
              AND awl.qty_ok > 0
              -- Fix: lihat komentar Line vs divisi di SIS_Station_PendingReceives.
              AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR br.division_id <> @DivisionId)
        ) AS MasukCount,
        (
            -- Fix (susulan): samakan definisi bundle "Dikerjakan" dengan Base/Frontier di
            -- SIS_Station_InProgress -- lihat komentar besar di atas SP itu. articles/projects
            -- WAJIB belum dihapus, article_sizes/size_pack_details WAJIB ada, supaya bundle
            -- yang artikel/project-nya sudah soft-delete tidak ikut kehitung.
            SELECT COUNT(*) FROM (
                SELECT b.bundle_id
                FROM bundles b
                INNER JOIN articles a ON a.article_id = b.article_id AND a.deleted_at IS NULL
                INNER JOIN projects p ON p.project_id = a.project_id AND p.deleted_at IS NULL
                INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
                INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                LEFT JOIN resources br ON br.resource_id = b.resource_id
                CROSS APPLY (
                    SELECT TOP 1 q.ArticleWorkflowId, q.PrevArticleWorkflowId, q.DivisionId
                    FROM (
                        SELECT aw.article_workflow_id AS ArticleWorkflowId, aw.sort_order AS SortOrder,
                               aw.division_id AS DivisionId,
                               LAG(aw.article_workflow_id) OVER (ORDER BY aw.sort_order) AS PrevArticleWorkflowId
                        FROM article_workflows aw
                        WHERE aw.article_id = a.article_id AND aw.deleted_at IS NULL AND aw.inactive_at IS NULL AND aw.requires_bundle = 1
                    ) q
                    -- Prompt 82: definisi frontier WAJIB sama dengan SIS_Station_InProgress
                    -- -- lihat komentar panjang di sana.
                    WHERE q.SortOrder > ISNULL((
                        SELECT MAX(aw9.sort_order)
                        FROM article_workflow_logs awl9
                        INNER JOIN article_workflows aw9 ON aw9.article_workflow_id = awl9.article_workflow_id
                        WHERE awl9.bundle_id = b.bundle_id AND awl9.deleted_at IS NULL
                          AND awl9.log_kind IN ('Creation', 'Kirim')
                    ), -1)
                    ORDER BY q.SortOrder ASC
                ) fr
                WHERE b.deleted_at IS NULL
                  AND fr.DivisionId = @DivisionId
                  AND EXISTS (
                        SELECT 1 FROM article_workflow_logs lr
                        WHERE lr.bundle_id = b.bundle_id AND lr.deleted_at IS NULL
                          AND lr.target_division_id = @DivisionId AND lr.received_at IS NOT NULL
                      )
                  AND (
                        fr.PrevArticleWorkflowId IS NULL
                        OR EXISTS (
                            SELECT 1 FROM article_workflow_logs pr
                            WHERE pr.article_workflow_id = fr.PrevArticleWorkflowId AND pr.bundle_id = b.bundle_id
                              AND pr.deleted_at IS NULL AND pr.received_at IS NOT NULL AND pr.target_division_id = @DivisionId
                        )
                      )
                  AND NOT EXISTS (
                        SELECT 1 FROM article_workflow_logs pend
                        WHERE pend.article_workflow_id = fr.ArticleWorkflowId AND pend.bundle_id = b.bundle_id
                          AND pend.deleted_at IS NULL AND pend.division_id = @DivisionId
                          AND pend.target_division_id IS NOT NULL AND pend.received_at IS NULL
                      )
                  AND (@ResourceId IS NULL OR b.resource_id IS NULL OR b.resource_id = @ResourceId OR br.division_id <> @DivisionId)
            ) x
        )
        +
        (
            -- Prompt 23: tambahkan kartu non-bundle (artikel x step), definisi sama dengan
            -- SIS_Station_ActiveWork -- tanpa filter Line (kartu non-bundle tidak terikat Line).
            -- Prompt 24: ikut hitung kartu "Buat Bundle" (is_bundling = 1), selaras dengan
            -- UNION baru di SIS_Station_ActiveWork.
            -- Fix: tambahkan gate "project sudah dimulai" yang sama dengan SIS_Station_ActiveWork
            -- -- tanpa ini, angka WIP bisa menghitung step milik project yang belum boleh mulai
            -- (manual_status kosong & start_date belum tiba & belum ada log), padahal kartunya
            -- memang sengaja tidak muncul di tab Dikerjakan.
            SELECT COUNT(*)
            FROM article_workflows aw
            INNER JOIN articles a ON a.article_id = aw.article_id
            INNER JOIN projects p ON p.project_id = a.project_id
            WHERE aw.division_id = @DivisionId AND aw.deleted_at IS NULL AND aw.inactive_at IS NULL
              AND (aw.requires_bundle = 0 OR aw.is_bundling = 1)
              AND p.deleted_at IS NULL AND ISNULL(p.manual_status, '') NOT IN ('COMPLETED', 'CANCELLED')
              AND (
                    p.manual_status IS NOT NULL
                    OR (p.[start_date] IS NOT NULL AND p.[start_date] <= CAST(GETDATE() AS DATE))
                    OR EXISTS (
                        SELECT 1 FROM article_workflow_logs awl2
                        INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl2.article_workflow_id
                        INNER JOIN articles a2 ON a2.article_id = aw2.article_id
                        WHERE a2.project_id = p.project_id
                          AND awl2.deleted_at IS NULL AND aw2.deleted_at IS NULL AND a2.deleted_at IS NULL
                    )
                  )
        ) AS DikerjakanCount,
        (
            -- Prompt 23: selaraskan dengan SIS_Station_PendingHandover supaya angka OUT cocok
            -- dengan isi tabnya (@Date = hari ini).
            -- Prompt 56: jendela H+1 dan cabang "Bundling auto-diterima 1 jam" ikut DIHAPUS
            -- di sini juga -- lihat catatan yang sama di SIS_Station_PendingHandover.
            SELECT COUNT(*)
            FROM article_workflow_logs awl3
            INNER JOIN article_workflows aw3 ON aw3.article_workflow_id = awl3.article_workflow_id
            WHERE awl3.division_id = @DivisionId AND awl3.deleted_at IS NULL
              AND (
                    (awl3.target_division_id IS NOT NULL AND awl3.qty_ok > 0
                     AND (awl3.received_at IS NULL OR CAST(awl3.created_at AS DATE) = CAST(SYSDATETIME() AS DATE)))
                    OR (awl3.target_division_id IS NULL AND awl3.log_type = 'NORMAL'
                        AND awl3.log_kind NOT IN ('Hilang', 'Ketemu', 'Creation')   -- Prompt 82
                        AND CAST(awl3.created_at AS DATE) = CAST(SYSDATETIME() AS DATE))
                  )
              AND (@ResourceId IS NULL OR awl3.resource_id IS NULL OR awl3.resource_id = @ResourceId)
        ) AS DikirimCount,
        (
            -- Prompt 56: teks kecil merah "n belum lock" di bawah angka OUT. SEMUA tanggal
            -- (bukan cuma hari ini) -- ini pengingat tunggakan, bukan angka tab.
            -- Cakupan barisnya WAJIB sama dengan yang bisa MUNCUL di tab OUT (dua cabang di
            -- SIS_Station_PendingHandover, tanpa syarat tanggal) -- kalau tidak, baris yang
            -- tidak pernah tampil (mis. ADJUSTMENT qty_ok = 0) ikut terhitung dan angka ini
            -- tidak akan pernah bisa dinolkan operator.
            SELECT COUNT(*)
            FROM article_workflow_logs awl5
            WHERE awl5.division_id = @DivisionId AND awl5.deleted_at IS NULL
              AND awl5.lock_id IS NULL
              AND (
                    (awl5.target_division_id IS NOT NULL AND awl5.qty_ok > 0)
                    OR (awl5.target_division_id IS NULL AND awl5.log_type = 'NORMAL'
                        AND awl5.log_kind NOT IN ('Hilang', 'Ketemu', 'Creation'))   -- Prompt 82
                  )
              AND (@ResourceId IS NULL OR awl5.resource_id IS NULL OR awl5.resource_id = @ResourceId)
        ) AS OutUnlockedCount;
END;
GO

-- Prompt 56: chip pengingat "Belum lock" di atas daftar tab OUT -- tanggal (basis yang sama
-- dengan filter "Tanggal Kirim", yaitu CAST(created_at AS DATE)) yang masih punya baris hidup
-- divisi ini dengan lock_id IS NULL, plus jumlah barisnya. Urut tanggal naik (yang terlama
-- dulu -- itu yang paling mendesak dibereskan).
-- @ResourceId ikut disediakan (tidak diminta eksplisit di prompt) supaya angka chip memakai
-- filter Line yang SAMA dengan daftar OUT di layar -- tanpa itu, stasiun yang terkunci ke satu
-- resource bisa melihat chip "3 belum lock" tapi daftarnya kosong.
CREATE OR ALTER PROCEDURE SIS_Station_UnlockedDates
    @DivisionId INT,
    @ResourceId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT CAST(awl.created_at AS DATE) AS [Date],
           COUNT(*) AS [Count]
    FROM article_workflow_logs awl
    WHERE awl.division_id = @DivisionId AND awl.deleted_at IS NULL
      AND awl.lock_id IS NULL
      -- Cakupan baris SAMA dengan yang bisa muncul di tab OUT (lihat catatan yang sama di
      -- OutUnlockedCount) -- chip harus selalu bisa ditindaklanjuti operator.
      AND (
            (awl.target_division_id IS NOT NULL AND awl.qty_ok > 0)
            OR (awl.target_division_id IS NULL AND awl.log_type = 'NORMAL'
                AND awl.log_kind NOT IN ('Hilang', 'Ketemu', 'Creation'))   -- Prompt 82
          )
      AND (@ResourceId IS NULL OR awl.resource_id IS NULL OR awl.resource_id = @ResourceId)
    GROUP BY CAST(awl.created_at AS DATE)
    ORDER BY [Date] ASC;
END;
GO

-- Prompt 40: dropdown "Diterima Oleh ({divisi tujuan})" wajib di form Kirim Hasil ketika step
-- tujuan auto_receive = 1 tapi counterpart pengirim tidak valid (lihat
-- SIS_Bundle_ScanInfo.ReceiverPickerRequired) -- resource hidup + aktif milik divisi tujuan
-- step BERIKUTNYA dari @ArticleWorkflowId (step yang sedang dikerjakan/dikirim hasilnya).
-- @BundleId diterima murni supaya bentuk pemanggilan client konsisten dengan endpoint lain
-- (quota-info, scan) -- divisi tujuan sama untuk semua bundle artikel yang sama, jadi tidak
-- dipakai di query.
CREATE OR ALTER PROCEDURE SIS_Station_ReceiverOptions
    @ArticleWorkflowId INT,
    @BundleId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ArticleId INT, @SortOrder INT;
    SELECT @ArticleId = article_id, @SortOrder = sort_order
    FROM article_workflows WHERE article_workflow_id = @ArticleWorkflowId AND deleted_at IS NULL;

    DECLARE @TargetDivisionId INT;
    SELECT TOP 1 @TargetDivisionId = division_id
    FROM article_workflows
    WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND sort_order > @SortOrder
    ORDER BY sort_order ASC;

    SELECT resource_id AS ResourceId, resource_name AS ResourceName
    FROM resources
    WHERE division_id = @TargetDivisionId AND is_active = 1 AND deleted_at IS NULL
    ORDER BY resource_name ASC;
END;
GO
