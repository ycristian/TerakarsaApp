-- Mutasi data bundles (CREATE/UPDATE/DELETE) + cetak ulang label (SIS_Bundle_ReprintLabel).
-- Pengambilan data ada di sp_Bundle_Select.sql.
-- Bundle dibuat manual per baris oleh supervisor (privilege PROJECT/ORDER_PROJECT).
-- Aturan:
--   1. article_size harus milik article yang sama dan hidup; qty > 0.
--   2. Serial digenerate di sini, format B{yy}-{nomor urut global 6 digit} (mis. B26-000153).
--      Nomor urut TIDAK reset per tahun (murni global), aman dari race condition lewat
--      sp_getapplock (exclusive, scoped ke transaksi) sebelum menghitung MAX nomor berjalan.
--   3. CREATE otomatis membuat baris print_jobs (job_type BUNDLE_LABEL, ref_id = bundle baru).
--      Payload berisi qr_content = @PublicBaseUrl + '/b/' + serial. @PublicBaseUrl dibaca dari
--      appsettings.json (App:PublicBaseUrl) di layer API dan dikirim sebagai parameter --
--      serial baru diketahui hanya di dalam transaksi ini (sp_getapplock), jadi qr_content
--      lengkap dirakit di sini, bukan di API.
--   4. [diganti Prompt 55: lock + saldo] UPDATE dulu ditolak bila bundle sudah punya log hidup
--      di step station (is_bundling = 0) ATAU log Bundling-nya sudah received_at terisi, dengan
--      kelonggaran jendela 1 jam. SEMUA itu dihapus -- lihat catatan #19 di bawah.
--   5. Serial tidak pernah berubah setelah dibuat.
--   6. bundle_no = nomor urut pendek per project (1, 2, 3, ...), naik terus lintas artikel
--      sampai project selesai, dihitung atas SEMUA bundle project ini (termasuk yang
--      soft-deleted) supaya nomor tidak pernah dipakai ulang. Digenerate di sini, di dalam
--      applock yang sama dengan serial (bundle_serial_seq) -- project tidak punya sequence
--      sendiri, jadi cukup satu lock global untuk keduanya.
--   7. Prompt 17: CREATE membuat juga baris article_workflow_logs untuk step Bunding implisit
--      artikel ini (bundle_id = bundle baru, qty_ok = qty bundle, received_at NULL) dan
--      auto-receive log non-bundle (mis. Cutting) yang masih pending -- lihat detail di
--      badan procedure. @BundlingResourceId (opsional) = pelaksana yang mengemas bundle ini;
--      UPDATE menyinkronkan qty_ok/resource_id log tsb, DELETE ikut soft-delete log tsb.
--      Prompt 23: auto-receive DIPERSEMPIT -- hanya baris dari step non-bundle dengan
--      sort_order TERBESAR di antara step requires_bundle = 0 hidup artikel ini (step non-
--      bundle sebelumnya, mis. DTF Print sebelum Cutting, diterima manual oleh divisi
--      berikutnya lewat tab IN stasiun, bukan lagi otomatis di sini).
--   8. Prompt 18: CREATE/UPDATE/DELETE ditolak kalau project artikel ini berstatus manual
--      (ON_HOLD/COMPLETED/CANCELLED) -- pesan RAISERROR menyertakan alasan bila ada.
--      SIS_Bundle_ReprintLabel TIDAK dikunci (cetak ulang label tetap boleh kapan pun).
--   9. Fix: @PrintCopies (default 1, dulu @SkipPrintJob BIT) -- jumlah label yang dicetak saat
--      bundle dibuat; 0 berarti CREATE melewati insert print_jobs sama sekali (dipakai station
--      saat input "Jumlah Label" diisi 0), >1 insert print_jobs berulang (pola sama dengan
--      SIS_Bundle_ReprintLabel @Copies). UPDATE guard
--      dipecah jadi 2 pesan terpisah supaya jelas: log step berikutnya (is_bundling = 0) vs
--      log Bundling sendiri sudah diterima (received_at terisi) -- keduanya tetap menolak
--      perubahan, hanya pesannya yang dibedakan.
--   10. Prompt 25: kalau bundle dibuat dengan @ResourceId (penjahit/Line) terisi, log
--      Bundling-nya LANGSUNG dibuat received_at/received_by_resource_id = @ResourceId (auto-
--      diterima oleh Line tujuan) -- Line sudah pasti sejak bundle dibuat, jadi tidak perlu
--      scan/Terima manual lagi di tab IN stasiun tujuan. Konsekuensi: berlaku juga aturan #4 --
--      begitu received_at terisi (langsung setelah CREATE), bundle TIDAK bisa lagi
--      diubah/dihapus lewat SIS_Bundle_Manage (harus direvisi dari sisi divisi tujuan).
--      Tanpa penjahit (@ResourceId NULL), tetap pending seperti semula (perilaku lama).
--      Fix: CREATE sekarang mewajibkan @ResourceId (RAISERROR bila NULL) -- cabang "tanpa
--      penjahit" di atas jadi tidak pernah kejadian lagi dari CREATE, tapi dibiarkan (bukan
--      dihapus) karena UPDATE tidak ikut diwajibkan (bundle lama boleh tetap tanpa penjahit).
--   11. [diganti Prompt 55: lock + saldo] Jendela 1 jam pada DELETE -- DIHAPUS, lihat #19.
--   12. [diganti Prompt 55: lock + saldo] Jendela 1 jam pada UPDATE -- DIHAPUS, lihat #19.
--   13. Fix: UPDATE bisa ikut mengubah ukuran (@ArticleSizeId, opsional -- NULL berarti tidak
--      diubah, dipakai admin /bundles yang belum mengirim field ini). Kalau ukuran berubah,
--      sort_order dihitung ulang relatif ke grup ukuran baru (pola sama dengan CREATE) supaya
--      urutan tampil tetap konsisten per ukuran.
--   14. Prompt 32: @EmployeeId (baru) -- penjahit dari master employees, menggantikan input
--      teks bebas. Validasi kecocokan Line HANYA ditegakkan kalau @EmployeeId diisi --
--      employee harus hidup dan resource_id-nya = @ResourceId. Khusus UPDATE, validasi ini
--      dilewati kalau @EmployeeId yang dikirim SAMA dengan employee_id yang sudah tersimpan
--      (supaya bundle lama yang employee-nya belakangan pindah Line tetap bisa disimpan
--      selama penjahitnya tidak diganti di form ini).
--   16. Prompt 35: kolom resource_person_name di-rename jadi remarks & direpurpose jadi
--      catatan bebas bundle (bukan lagi identitas penjahit) -- @Remarks (baru, menggantikan
--      @ResourcePersonName) diisi/diedit lewat BundleManager.razor, SELALU ditulis di CREATE
--      dan UPDATE (string kosong dinormalisasi jadi NULL). @EmployeeId sekarang juga boleh
--      NULL murni tanpa syarat apa pun -- karyawan yang belum terdaftar employee_code tetap
--      bisa dipilih (lihat sql/sp_Employee_Manage.sql).
--   15. Prompt 34: auto-terima per step penerima log Bundling (article_workflows.auto_receive
--      milik step station pertama). CREATE: kalau step itu ber-flag, log Bundling langsung
--      diterima dengan received_by_resource_id = @BundlingResourceId (boleh NULL), remark
--      'Otomatis: auto-terima' -- berdampingan dengan aturan #10 (kalau tidak ber-flag, jatuh
--      balik ke perilaku lama berdasar @ResourceId). UPDATE: kalau log Bundling bundle ini
--      masih pending (received_at NULL, mis. bundle lama) dan step penerimanya kini ber-flag,
--      langsung diterima juga di transaksi UPDATE yang sama -- tidak retroaktif ke bundle lain.
--   17. @DeleteReason (baru) -- DELETE sekarang mewajibkan alasan (RAISERROR bila NULL/kosong),
--      ditulis ke bundles.delete_reason. Pola sama dengan SIS_SuperAdmin_Manage BUNDLE_DELETE/
--      LOG_DELETE; sebelumnya delete_reason selalu NULL di jalur DELETE biasa (station/admin).
--   18. Fix: bug aturan #15 (Prompt 34) -- auto-terima log Bundling menulis received_by_resource_id
--      = @BundlingResourceId (resource divisi Bundling sendiri) alih-alih @ResourceId (Line/
--      penjahit divisi TUJUAN). Prompt 40 SS7 (sp_WorkflowLog_Manage, "penerima mengikat
--      pelaksana") lalu mengunci pelaksana step berikutnya harus persis sama dengan
--      received_by_resource_id itu -- karena resource Bundling tidak pernah ada di divisi
--      tujuan, bundle buntu permanen ("Bundle ini atas nama X. Batalkan penerimaan dulu...")
--      sampai di-UNRECEIVE manual. CREATE & UPDATE sekarang selalu pakai @ResourceId. Data lama
--      yang sudah kena lihat sql/adhoc_repair_bundle_autoreceive_received_by.sql.
--   19. Prompt 55 -- lock + saldo, MENGGANTIKAN #4, #11 dan #12 di atas:
--      - UPDATE & DELETE ditolak keras kalau baris log BUNDLING bundle ini sudah di-lock
--        (article_workflow_logs.lock_id terisi) -- pesan 'LOCKED|Data sudah di-lock. Ajukan
--        unlock untuk mengubah.' Lock dipasang SIS_WorkflowLock_Manage, dilepas hanya lewat
--        SIS_UnlockRequest_Manage APPROVE.
--      - Selama belum di-lock, tidak ada batas waktu sama sekali. Yang membatasi cuma saldo:
--        qty baru tidak boleh turun di bawah total step ber-bundle berikutnya
--        (dbo.SIS_fn_BundleNextStepTotal, sql/fn_55_workflow_saldo.sql), kecuali perubahan itu
--        tidak memperburuk saldo yang memang sudah minus. DELETE = qty 0, jadi ditolak kalau
--        step berikutnya sudah punya baris hidup.
--      - Tambahan UPDATE: begitu step berikutnya punya baris hidup, HANYA qty yang boleh
--        berubah -- ukuran dan line/penjahit ditolak ('Bundle sudah diproses step berikutnya,
--        hanya qty yang bisa diubah.') karena sudah melekat pada hasil kerja di step itu.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE SIS_Bundle_Manage
    @Action              VARCHAR(20),
    @Id                  INT = NULL,
    @ArticleId           INT = NULL,
    @ArticleSizeId       INT = NULL,
    @Qty                 INT = NULL,
    @ResourceId          INT = NULL,
    @Remarks             VARCHAR(500) = NULL,
    @EmployeeId          INT = NULL,
    @PublicBaseUrl       VARCHAR(255) = NULL,
    @BundlingResourceId  INT = NULL,
    @PrintCopies         INT = 1,
    @UserId              INT = NULL,
    @DeleteReason        VARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Action = 'CREATE'
    BEGIN
        -- Prompt 18: project terkunci (manual_status) menolak pembuatan bundle.
        DECLARE @LockStatus_Create VARCHAR(20), @LockReason_Create VARCHAR(255);
        SELECT @LockStatus_Create = p.manual_status, @LockReason_Create = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @ArticleId;

        IF @LockStatus_Create IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Create VARCHAR(30) = CASE @LockStatus_Create
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Create END;
            DECLARE @LockSuffix_Create VARCHAR(300) = CASE WHEN @LockReason_Create IS NOT NULL AND LTRIM(RTRIM(@LockReason_Create)) <> ''
                THEN ' (Alasan: ' + @LockReason_Create + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Create, @LockSuffix_Create);
            RETURN;
        END

        IF @Qty IS NULL OR @Qty <= 0
        BEGIN
            RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
            RETURN;
        END

        -- Fix: Penjahit (resource) wajib dipilih saat bundle dibuat -- sebelumnya @ResourceId
        -- NULL diperbolehkan (log Bundling tetap pending, lihat catatan #10), tapi sekarang
        -- UI (station & admin bundle) selalu mewajibkan pilihan penjahit, ditegakkan di sini juga.
        IF @ResourceId IS NULL
        BEGIN
            RAISERROR('Penjahit (resource) wajib dipilih.', 16, 1);
            RETURN;
        END

        -- Prompt 32: employee (penjahit dari master) harus hidup dan anggota Line yang sama.
        IF @EmployeeId IS NOT NULL
        BEGIN
            IF @ResourceId IS NULL
            BEGIN
                RAISERROR('Pilih line terlebih dahulu.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM employees
                WHERE employee_id = @EmployeeId AND resource_id = @ResourceId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Penjahit bukan anggota line ini.', 16, 1);
                RETURN;
            END
        END

        IF NOT EXISTS (
            SELECT 1 FROM article_sizes
            WHERE article_size_id = @ArticleSizeId AND article_id = @ArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Ukuran tidak ditemukan untuk artikel ini.', 16, 1);
            RETURN;
        END

        -- Prompt 17: step Bundling implisit artikel ini -- wajib ada (disisipkan otomatis
        -- oleh SIS_ArticleWorkflow_Manage APPLY/SAVE) sebelum bundle bisa dibuat.
        DECLARE @BundlingStepId INT, @BundlingDivisionId INT, @BundlingSortOrder INT;
        SELECT @BundlingStepId = article_workflow_id, @BundlingDivisionId = division_id, @BundlingSortOrder = sort_order
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND is_bundling = 1;

        IF @BundlingStepId IS NULL
        BEGIN
            RAISERROR('Workflow artikel belum memiliki step Bundling. Terapkan ulang/simpan workflow artikel terlebih dahulu.', 16, 1);
            RETURN;
        END

        IF @BundlingResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @BundlingResourceId AND division_id = @BundlingDivisionId AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana bundling tidak valid.', 16, 1);
            RETURN;
        END

        -- Prompt 34: step penerima log Bundling (step station pertama) bisa ber-auto_receive
        -- = 1 -- kalau ya, log Bundling langsung diterima saat dibuat (lihat INSERT di bawah),
        -- selain aturan Prompt 25 (bundle ditugaskan langsung ke penjahit/Line).
        DECLARE @BundlingTargetDivisionId INT, @BundlingTargetAutoReceive BIT;
        SELECT TOP 1 @BundlingTargetDivisionId = division_id, @BundlingTargetAutoReceive = auto_receive
        FROM article_workflows
        WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND sort_order > @BundlingSortOrder
        ORDER BY sort_order ASC;

        DECLARE @LockResource_Article VARCHAR(60) = 'article_workflow_restructure_' + CAST(@ArticleId AS VARCHAR(20));

        BEGIN TRAN;
        BEGIN TRY
            -- Prompt 50: applock per artikel -- SAMA PERSIS dengan resource yang dipakai
            -- SIS_ArticleWorkflow_Restructure dan SIS_WorkflowLog_Manage, supaya pembuatan
            -- bundle tidak bisa nyelip di tengah restrukturisasi artikel yang sama.
            DECLARE @LockResultArticle INT;
            EXEC @LockResultArticle = sp_getapplock
                @Resource = @LockResource_Article,
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResultArticle < 0
            BEGIN
                RAISERROR('Gagal mengunci artikel. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            DECLARE @LockResult INT;
            EXEC @LockResult = sp_getapplock
                @Resource = 'bundle_serial_seq',
                @LockMode = 'Exclusive',
                @LockOwner = 'Transaction',
                @LockTimeout = 10000;

            IF @LockResult < 0
            BEGIN
                RAISERROR('Gagal mengunci penomoran serial bundle. Coba lagi.', 16, 1);
                ROLLBACK TRAN;
                RETURN;
            END

            -- Prompt 82: WAJIB menyaring sequence_no = 0 (bundle INDUK saja). Serial anak
            -- berbentuk '{serial induk}-{seq}' (mis. B26-005742-1) -- RIGHT(serial, 6)
            -- atasnya jadi '5742-1' dan CAST ke INT melempar error konversi.
            DECLARE @NextNumber INT;
            SELECT @NextNumber = ISNULL(MAX(CAST(RIGHT(serial, 6) AS INT)), 0) + 1
            FROM bundles
            WHERE sequence_no = 0;

            DECLARE @Yy VARCHAR(2) = RIGHT(CAST(YEAR(SYSDATETIME()) AS VARCHAR(4)), 2);
            DECLARE @NewSerial VARCHAR(20) = 'B' + @Yy + '-' + RIGHT('000000' + CAST(@NextNumber AS VARCHAR(6)), 6);

            DECLARE @ProjectId INT;
            SELECT @ProjectId = project_id FROM articles WHERE article_id = @ArticleId;

            DECLARE @NewBundleNo INT;
            SELECT @NewBundleNo = ISNULL(MAX(b.bundle_no), 0) + 1
            FROM bundles b
            INNER JOIN articles a ON a.article_id = b.article_id
            WHERE a.project_id = @ProjectId;

            -- Prompt 27: huruf bundle project ini (NULL utk project lama sebelum Prompt 27) --
            -- dipakai payload label + dikembalikan ke client, TIDAK mengubah bundle_no itu sendiri.
            DECLARE @NewBundleLetter CHAR(1);
            SELECT @NewBundleLetter = bundle_letter FROM projects WHERE project_id = @ProjectId;

            DECLARE @NextSort INT;
            SELECT @NextSort = ISNULL(MAX(sort_order), 0) + 1
            FROM bundles
            WHERE article_size_id = @ArticleSizeId AND deleted_at IS NULL;

            -- Prompt 35: remarks (catatan bebas) diisi dari @Remarks, string kosong/whitespace
            -- dinormalisasi jadi NULL.
            INSERT INTO bundles (
                article_id, article_size_id, serial, bundle_no, qty, sort_order,
                resource_id, employee_id, remarks, created_at, created_by
            )
            VALUES (
                @ArticleId, @ArticleSizeId, @NewSerial, @NewBundleNo, @Qty, @NextSort,
                @ResourceId, @EmployeeId, NULLIF(LTRIM(RTRIM(@Remarks)), ''), SYSDATETIME(), @UserId
            );

            DECLARE @NewBundleId INT = CAST(SCOPE_IDENTITY() AS INT);

            -- Prompt 82: bundle baru selalu INDUK UTAMA -- root_bundle_id menunjuk dirinya
            -- sendiri. Diisi setelah INSERT karena identity-nya baru diketahui di sini
            -- (kolom sengaja tanpa FK, lihat sql/alter_84_bundle_anak.sql).
            UPDATE bundles SET root_bundle_id = @NewBundleId WHERE bundle_id = @NewBundleId;

            DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/b/' + @NewSerial;

            -- Fix: @PrintCopies < 1 (input "Jumlah Label" diisi 0 di station) -- lewati insert
            -- print_jobs, NewPrintJobId dikembalikan NULL. @PrintCopies >= 1 insert print_jobs
            -- sebanyak itu (payload sama untuk tiap lembar).
            DECLARE @NewPrintJobId INT = NULL;
            IF ISNULL(@PrintCopies, 0) >= 1
            BEGIN
                DECLARE @Payload NVARCHAR(MAX) = (
                    SELECT
                        @NewSerial AS serial,
                        @NewBundleNo AS bundle_no,
                        @NewBundleLetter AS bundle_letter,
                        @QrContent AS qr_content,
                        p.project_name AS project_name,
                        p.no_po AS no_po,
                        p.material_name AS material_name,
                        a.article_name AS article_name,
                        NULLIF(LTRIM(RTRIM(@Remarks)), '') AS bundle_remarks,
                        a.style AS style,
                        a.color AS color,
                        spk.size_pack_name AS size_pack_name,
                        spd.size_name AS size_name,
                        @Qty AS qty,
                        res.resource_name AS resource_name,
                        emp.employee_name AS employee_name,
                        (SELECT created_at FROM bundles WHERE bundle_id = @NewBundleId) AS started_at,
                        CAST(NULL AS VARCHAR(255)) AS remark
                    FROM articles a
                    INNER JOIN projects p ON p.project_id = a.project_id
                    INNER JOIN size_packs spk ON spk.size_pack_id = a.size_pack_id
                    INNER JOIN article_sizes asz ON asz.article_size_id = @ArticleSizeId
                    INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
                    LEFT JOIN resources res ON res.resource_id = @ResourceId
                    LEFT JOIN employees emp ON emp.employee_id = @EmployeeId AND emp.deleted_at IS NULL
                    WHERE a.article_id = @ArticleId
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                );

                DECLARE @PrintCopy INT = 0;
                WHILE @PrintCopy < @PrintCopies
                BEGIN
                    INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
                    VALUES ('BUNDLE_LABEL', @NewBundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

                    SET @NewPrintJobId = CAST(SCOPE_IDENTITY() AS INT);
                    SET @PrintCopy += 1;
                END
            END

            -- Prompt 23: hanya step non-bundle TERAKHIR (sort_order terbesar di antara
            -- requires_bundle = 0 hidup) yang di-auto-receive di sini.
            DECLARE @LastNonBundleStepId INT;
            SELECT TOP 1 @LastNonBundleStepId = article_workflow_id
            FROM article_workflows
            WHERE article_id = @ArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND requires_bundle = 0
            ORDER BY sort_order DESC;

            -- Prompt 17: catat kegiatan Bundling sebagai log workflow (menunggu diterima
            -- divisi berikutnya) + auto-receive log non-bundle (mis. Cutting) yang masih
            -- pending -- tanggung jawab akurasi qty tetap di divisi non-bundle, sistem
            -- tidak memblokir pembuatan bundle karena ini.
            -- Prompt 25: kalau bundle langsung ditugaskan ke penjahit/Line (@ResourceId terisi
            -- -- lihat "Penjahit" di modal Buat Bundle), log Bundling ini LANGSUNG dianggap
            -- diterima oleh Line tersebut (received_at/received_by_resource_id terisi saat
            -- INSERT) -- Line tujuan sudah pasti, jadi tidak perlu scan/Terima manual lagi di
            -- tab IN stasiun. Tanpa penjahit (@ResourceId NULL), tetap pending seperti semula.
            -- Prompt 82: baris Bundling ini SEKALIGUS baris 'Creation' rantai qty bundle
            -- (qty_delta = +qty awal, qty_after = qty awal). SENGAJA tidak dibuat baris
            -- Creation terpisah: pembuatan bundle memang satu kejadian, dan baris tambahan
            -- di step Bundling akan ikut terbaca semua laporan/tab OUT lama. Invarian
            -- Sigma qty_delta per bundle = bundles.qty tetap terpenuhi.
            INSERT INTO article_workflow_logs (
                article_workflow_id, bundle_id, article_size_id, division_id, resource_id, employee_id,
                qty_ok, qty_reject_print, qty_reject_fabric, qty_reject_sewing,
                qty_delta, qty_after, log_kind,
                remark, target_division_id, received_at, received_by_resource_id, received_remark,
                created_at, created_by
            )
            VALUES (
                @BundlingStepId, @NewBundleId, NULL, @BundlingDivisionId, @BundlingResourceId, NULL,
                @Qty, 0, 0, 0,
                @Qty, @Qty, 'Creation',
                NULL, @BundlingTargetDivisionId,
                CASE WHEN ISNULL(@BundlingTargetAutoReceive, 0) = 1 OR @ResourceId IS NOT NULL THEN SYSDATETIME() ELSE NULL END,
                -- Fix: received_by_resource_id HARUS resource divisi TUJUAN (Line/penjahit,
                -- @ResourceId -- sama dengan bundles.resource_id) walau step tujuan ber-
                -- auto_receive -- SEBELUMNYA jatuh ke @BundlingResourceId (resource divisi
                -- Bundling sendiri), membuat baris "diterima" oleh resource yang bukan milik
                -- target_division_id. Prompt 40 SS7 (sp_WorkflowLog_Manage) lalu mengunci
                -- pelaksana step berikutnya HARUS sama dengan received_by_resource_id ini --
                -- resource Bundling itu tidak pernah ada di divisi tujuan, jadi bundle buntu
                -- permanen sampai di-UNRECEIVE manual. @ResourceId sudah wajib diisi saat
                -- CREATE (lihat validasi di atas), jadi selalu tersedia di sini.
                @ResourceId,
                CASE WHEN ISNULL(@BundlingTargetAutoReceive, 0) = 1 THEN 'Otomatis: auto-terima'
                     WHEN @ResourceId IS NOT NULL THEN 'Otomatis: bundle langsung ditugaskan ke penjahit/Line'
                     ELSE NULL END,
                SYSDATETIME(), @UserId
            );

            UPDATE awl
            SET received_at = SYSDATETIME(),
                received_by_resource_id = @BundlingResourceId,
                received_remark = 'Otomatis: pembuatan bundle'
            FROM article_workflow_logs awl
            WHERE awl.article_workflow_id = @LastNonBundleStepId
              AND awl.deleted_at IS NULL
              AND awl.received_at IS NULL AND awl.target_division_id IS NOT NULL;

            COMMIT TRAN;

            SELECT @NewBundleId AS NewId, @NewPrintJobId AS NewPrintJobId, @NewBundleNo AS NewBundleNo, @NewSerial AS NewSerial, @NewBundleLetter AS NewBundleLetter;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0 ROLLBACK TRAN;
            THROW;
        END CATCH
    END

    ELSE IF @Action = 'UPDATE'
    BEGIN
        IF @Qty IS NULL OR @Qty <= 0
        BEGIN
            RAISERROR('Qty bundle harus lebih dari 0.', 16, 1);
            RETURN;
        END

        -- Prompt 17: perbaikan bug -- [status] sudah dihapus sejak Prompt 12b. Tolak bila
        -- bundle sudah punya log hidup di step station (sudah dikerjakan) atau log Bundling-
        -- nya sudah diserah-terimakan (received_at terisi).
        DECLARE @UpdArticleId INT, @UpdBundlingDivisionId INT, @UpdCreatedAt DATETIME2, @UpdCurrentSizeId INT, @UpdEmployeeId INT, @UpdBundlingSortOrder INT,
                @UpdBundlingStepId INT, @UpdCurrentQty INT, @UpdCurrentResourceId INT;
        SELECT @UpdArticleId = b.article_id, @UpdBundlingDivisionId = aw.division_id, @UpdCreatedAt = b.created_at, @UpdCurrentSizeId = b.article_size_id, @UpdEmployeeId = b.employee_id, @UpdBundlingSortOrder = aw.sort_order,
               @UpdBundlingStepId = aw.article_workflow_id, @UpdCurrentQty = b.qty, @UpdCurrentResourceId = b.resource_id
        FROM bundles b
        LEFT JOIN article_workflows aw ON aw.article_id = b.article_id AND aw.deleted_at IS NULL AND aw.is_bundling = 1
        WHERE b.bundle_id = @Id AND b.deleted_at IS NULL;

        -- Prompt 55: bundle mengikuti lock baris log BUNDLING-nya -- kalau baris itu sudah
        -- di-lock, induk bundle-nya ikut beku (qty bundle = qty_ok baris Bundling).
        IF EXISTS (
            SELECT 1 FROM article_workflow_logs awl
            INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw2.is_bundling = 1
              AND awl.lock_id IS NOT NULL
        )
        BEGIN
            RAISERROR('LOCKED|Data sudah di-lock. Ajukan unlock untuk mengubah.', 16, 1);
            RETURN;
        END

        -- Prompt 32: validasi kecocokan Line hanya kalau @EmployeeId diisi DAN berbeda dari
        -- employee_id yang sudah tersimpan (lihat catatan #14) -- bundle lama yang employee-nya
        -- sudah pindah Line tetap bisa disimpan selama penjahitnya tidak diganti di form ini.
        IF @EmployeeId IS NOT NULL AND (@UpdEmployeeId IS NULL OR @EmployeeId <> @UpdEmployeeId)
        BEGIN
            IF @ResourceId IS NULL
            BEGIN
                RAISERROR('Pilih line terlebih dahulu.', 16, 1);
                RETURN;
            END

            IF NOT EXISTS (
                SELECT 1 FROM employees
                WHERE employee_id = @EmployeeId AND resource_id = @ResourceId AND deleted_at IS NULL
            )
            BEGIN
                RAISERROR('Penjahit bukan anggota line ini.', 16, 1);
                RETURN;
            END
        END

        -- Prompt 18: project terkunci (manual_status) menolak perubahan bundle.
        DECLARE @LockStatus_Update VARCHAR(20), @LockReason_Update VARCHAR(255);
        SELECT @LockStatus_Update = p.manual_status, @LockReason_Update = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @UpdArticleId;

        IF @LockStatus_Update IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Update VARCHAR(30) = CASE @LockStatus_Update
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Update END;
            DECLARE @LockSuffix_Update VARCHAR(300) = CASE WHEN @LockReason_Update IS NOT NULL AND LTRIM(RTRIM(@LockReason_Update)) <> ''
                THEN ' (Alasan: ' + @LockReason_Update + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Update, @LockSuffix_Update);
            RETURN;
        END

        -- [diganti Prompt 55: lock + saldo] Guard "Bundle sudah diproses, tidak bisa diubah"
        -- (ada log hidup di step is_bundling = 0) dan jendela 1 jam sejak bundles.created_at
        -- untuk bundle yang log Bundling-nya sudah diterima -- DUA-DUANYA DIHAPUS. Gantinya
        -- lock (di atas) + dua aturan di bawah: qty tidak boleh turun di bawah pemakaian step
        -- berikutnya, dan begitu step berikutnya sudah punya baris hidup, hanya qty yang boleh
        -- berubah (ukuran & line/penjahit sudah terlanjur melekat pada hasil kerja di sana).
        DECLARE @UpdNextTotal INT = dbo.SIS_fn_BundleNextStepTotal(@UpdBundlingStepId, @Id);

        IF @UpdNextTotal > 0
        BEGIN
            DECLARE @UpdNewSizeCheck INT = ISNULL(@ArticleSizeId, @UpdCurrentSizeId);
            IF @UpdNewSizeCheck <> @UpdCurrentSizeId
                OR ISNULL(@ResourceId, -1) <> ISNULL(@UpdCurrentResourceId, -1)
                OR ISNULL(@EmployeeId, -1) <> ISNULL(@UpdEmployeeId, -1)
            BEGIN
                RAISERROR('Bundle sudah diproses step berikutnya, hanya qty yang bisa diubah.', 16, 1);
                RETURN;
            END
        END

        -- Guard saldo: qty baru < pemakaian step berikutnya ditolak, KECUALI kalau qty lama
        -- pun sudah di bawahnya dan perubahan ini tidak memperburuk (pola sama dengan
        -- SIS_WorkflowLog_Manage, lihat sql/fn_55_workflow_saldo.sql).
        IF @Qty - @UpdNextTotal < 0 AND @Qty < @UpdCurrentQty
        BEGIN
            RAISERROR('Perubahan membuat saldo minus (sisa %d, dipakai step berikutnya %d). Ubah step berikutnya terlebih dahulu.', 16, 1, @Qty, @UpdNextTotal);
            RETURN;
        END

        IF @BundlingResourceId IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM resources
            WHERE resource_id = @BundlingResourceId AND division_id = @UpdBundlingDivisionId AND is_active = 1 AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Pelaksana bundling tidak valid.', 16, 1);
            RETURN;
        END

        -- Fix: ukuran boleh diubah lewat Edit bundle di station -- lihat catatan #13.
        IF @ArticleSizeId IS NOT NULL AND @ArticleSizeId <> @UpdCurrentSizeId AND NOT EXISTS (
            SELECT 1 FROM article_sizes
            WHERE article_size_id = @ArticleSizeId AND article_id = @UpdArticleId AND deleted_at IS NULL
        )
        BEGIN
            RAISERROR('Ukuran tidak ditemukan untuk artikel ini.', 16, 1);
            RETURN;
        END

        DECLARE @UpdNewSizeId INT = ISNULL(@ArticleSizeId, @UpdCurrentSizeId);
        DECLARE @UpdSortOrder INT;
        IF @UpdNewSizeId <> @UpdCurrentSizeId
            SELECT @UpdSortOrder = ISNULL(MAX(sort_order), 0) + 1 FROM bundles WHERE article_size_id = @UpdNewSizeId AND deleted_at IS NULL;
        ELSE
            SELECT @UpdSortOrder = sort_order FROM bundles WHERE bundle_id = @Id;

        -- Prompt 35: remarks SELALU ditulis ulang dari @Remarks (string kosong/whitespace
        -- dinormalisasi jadi NULL) -- pemanggil yang tidak mau mengubah catatan (mis. station
        -- edit bundle) wajib mengirim balik nilai remarks terkini apa adanya.
        UPDATE bundles
        SET qty = @Qty,
            article_size_id = @UpdNewSizeId,
            sort_order = @UpdSortOrder,
            resource_id = @ResourceId,
            employee_id = @EmployeeId,
            remarks = NULLIF(LTRIM(RTRIM(@Remarks)), ''),
            updated_at = SYSDATETIME(),
            updated_by = @UserId
        WHERE bundle_id = @Id AND deleted_at IS NULL;

        -- Prompt 82: baris Bundling = baris 'Creation' rantai qty, jadi qty_delta/qty_after
        -- ikut disinkronkan supaya invarian Sigma qty_delta = bundles.qty tetap benar
        -- setelah qty bundle diubah dari form Buat/Edit Bundle.
        UPDATE awl
        SET awl.qty_ok = @Qty,
            awl.qty_delta = @Qty,
            awl.qty_after = @Qty,
            awl.log_kind = 'Creation',
            awl.resource_id = ISNULL(@BundlingResourceId, awl.resource_id),
            awl.updated_at = SYSDATETIME(),
            awl.updated_by = @UserId
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1;

        -- Prompt 34: log Bundling bundle ini masih pending (received_at IS NULL, mis. bundle
        -- lama sebelum @ResourceId diwajibkan) DAN step penerimanya kini ber-auto_receive = 1
        -- -- langsung diterima dalam transaksi UPDATE yang sama (tidak retroaktif ke bundle
        -- lain, hanya bundle yang sedang diedit ini).
        DECLARE @UpdNextAutoReceive BIT;
        SELECT TOP 1 @UpdNextAutoReceive = auto_receive
        FROM article_workflows
        WHERE article_id = @UpdArticleId AND deleted_at IS NULL AND inactive_at IS NULL AND sort_order > @UpdBundlingSortOrder
        ORDER BY sort_order ASC;

        -- Fix: sama dengan CREATE -- received_by_resource_id harus resource divisi TUJUAN
        -- (@ResourceId, Line/penjahit), BUKAN @BundlingResourceId (resource divisi Bundling).
        -- ISNULL ke received_by_resource_id lama (bukan awl.resource_id) supaya kalau
        -- @ResourceId tidak dikirim (bundle lama tanpa penjahit), nilai lama dipertahankan
        -- apa adanya alih-alih ikut tertimpa resource Bundling.
        UPDATE awl
        SET awl.received_at = SYSDATETIME(),
            awl.received_by_resource_id = ISNULL(@ResourceId, awl.received_by_resource_id),
            awl.received_remark = 'Otomatis: auto-terima'
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1
          AND awl.received_at IS NULL AND ISNULL(@UpdNextAutoReceive, 0) = 1;
    END

    ELSE IF @Action = 'DELETE'
    BEGIN
        IF @DeleteReason IS NULL OR LTRIM(RTRIM(@DeleteReason)) = ''
        BEGIN
            RAISERROR('Alasan hapus wajib diisi.', 16, 1);
            RETURN;
        END

        DECLARE @DelArticleId INT, @DelCreatedAt DATETIME2;
        SELECT @DelArticleId = article_id, @DelCreatedAt = created_at FROM bundles WHERE bundle_id = @Id AND deleted_at IS NULL;

        -- Prompt 55: bundle mengikuti lock baris log Bundling-nya (lihat catatan di UPDATE).
        IF EXISTS (
            SELECT 1 FROM article_workflow_logs awl
            INNER JOIN article_workflows aw2 ON aw2.article_workflow_id = awl.article_workflow_id
            WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw2.is_bundling = 1
              AND awl.lock_id IS NOT NULL
        )
        BEGIN
            RAISERROR('LOCKED|Data sudah di-lock. Ajukan unlock untuk mengubah.', 16, 1);
            RETURN;
        END

        -- Prompt 18: project terkunci (manual_status) menolak penghapusan bundle.
        DECLARE @LockStatus_Delete VARCHAR(20), @LockReason_Delete VARCHAR(255);
        SELECT @LockStatus_Delete = p.manual_status, @LockReason_Delete = p.status_reason
        FROM projects p
        INNER JOIN articles a ON a.project_id = p.project_id
        WHERE a.article_id = @DelArticleId;

        IF @LockStatus_Delete IS NOT NULL
        BEGIN
            DECLARE @LockLabel_Delete VARCHAR(30) = CASE @LockStatus_Delete
                WHEN 'ON_HOLD' THEN 'sedang ditahan'
                WHEN 'COMPLETED' THEN 'sudah ditandai selesai'
                WHEN 'CANCELLED' THEN 'sudah dibatalkan'
                ELSE @LockStatus_Delete END;
            DECLARE @LockSuffix_Delete VARCHAR(300) = CASE WHEN @LockReason_Delete IS NOT NULL AND LTRIM(RTRIM(@LockReason_Delete)) <> ''
                THEN ' (Alasan: ' + @LockReason_Delete + ')' ELSE '' END;
            RAISERROR('Project %s%s. Hubungi supervisor untuk melanjutkan.', 16, 1, @LockLabel_Delete, @LockSuffix_Delete);
            RETURN;
        END

        -- [diganti Prompt 55: lock + saldo] Guard "Bundle sudah diproses, tidak bisa dihapus"
        -- dan jendela 1 jam sejak bundles.created_at DIHAPUS. Hapus bundle = qty jadi 0, jadi
        -- cukup satu aturan: ditolak kalau step berikutnya sudah memakai bundle ini.
        DECLARE @DelBundlingStepId INT;
        SELECT @DelBundlingStepId = article_workflow_id
        FROM article_workflows
        WHERE article_id = @DelArticleId AND deleted_at IS NULL AND is_bundling = 1;

        DECLARE @DelNextTotal INT = dbo.SIS_fn_BundleNextStepTotal(@DelBundlingStepId, @Id);

        IF @DelNextTotal > 0
        BEGIN
            RAISERROR('Perubahan membuat saldo minus (sisa %d, dipakai step berikutnya %d). Ubah step berikutnya terlebih dahulu.', 16, 1, 0, @DelNextTotal);
            RETURN;
        END

        UPDATE bundles
        SET deleted_at = SYSDATETIME(),
            deleted_by = @UserId,
            delete_reason = @DeleteReason
        WHERE bundle_id = @Id AND deleted_at IS NULL;

        UPDATE awl
        SET awl.deleted_at = SYSDATETIME(),
            awl.deleted_by = @UserId,
            awl.delete_reason = 'Bundle dihapus'
        FROM article_workflow_logs awl
        INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
        WHERE awl.bundle_id = @Id AND awl.deleted_at IS NULL AND aw.is_bundling = 1;
    END
END;
GO

-- Cetak ulang label: insert baris print_jobs baru, payload dirakit ulang dari data terkini
-- (bukan dari job lama, supaya perubahan qty/penjahit ikut terbawa di label baru).
-- remark payload = article_workflow_logs.remark TERBARU milik bundle ini (dicetak bold di
-- bawah Size Pack, lihat TsplBuilder.BuildBundleLabel), kecuali @RemarkOverride diisi.
-- Prompt: dipakai juga untuk "Print Label Cacat" (BundleScanCard) -- @Copies = jumlah lembar
-- yang diminta user, @RemarkOverride = catatan Kirim Hasil + ringkasan qty cacat (dirakit di
-- BundleService.PrintDefectLabelAsync), supaya beda dari remark log yang sudah tersimpan.
-- bundle_remarks payload = bundles.remarks (catatan bebas Prompt 35) apa adanya, dicetak di
-- bawah nama artikel (kolom kiri) -- field TERPISAH dari remark di atas.
CREATE OR ALTER PROCEDURE SIS_Bundle_ReprintLabel
    @BundleId       INT,
    @PublicBaseUrl  VARCHAR(255) = NULL,
    @Copies         INT = 1,
    @RemarkOverride VARCHAR(255) = NULL,
    @UserId         INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM bundles WHERE bundle_id = @BundleId AND deleted_at IS NULL)
    BEGIN
        RAISERROR('Bundle tidak ditemukan.', 16, 1);
        RETURN;
    END

    IF @Copies IS NULL OR @Copies < 1
    BEGIN
        RAISERROR('Jumlah label harus minimal 1.', 16, 1);
        RETURN;
    END

    DECLARE @QrContent VARCHAR(300) = ISNULL(@PublicBaseUrl, '') + '/b/' + (SELECT serial FROM bundles WHERE bundle_id = @BundleId);

    DECLARE @Payload NVARCHAR(MAX) = (
        SELECT
            b.serial AS serial,
            b.bundle_no AS bundle_no,
            p.bundle_letter AS bundle_letter,
            @QrContent AS qr_content,
            p.project_name AS project_name,
            p.no_po AS no_po,
            p.material_name AS material_name,
            a.article_name AS article_name,
            b.remarks AS bundle_remarks,
            a.style AS style,
            a.color AS color,
            spk.size_pack_name AS size_pack_name,
            spd.size_name AS size_name,
            b.qty AS qty,
            res.resource_name AS resource_name,
            emp.employee_name AS employee_name,
            b.created_at AS started_at,
            ISNULL(@RemarkOverride, (
                SELECT TOP 1 remark FROM article_workflow_logs
                WHERE bundle_id = b.bundle_id AND deleted_at IS NULL
                  AND remark IS NOT NULL AND LTRIM(RTRIM(remark)) <> ''
                ORDER BY created_at DESC
            )) AS remark
        FROM bundles b
        INNER JOIN articles a ON a.article_id = b.article_id
        INNER JOIN projects p ON p.project_id = a.project_id
        INNER JOIN size_packs spk ON spk.size_pack_id = a.size_pack_id
        INNER JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
        INNER JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
        LEFT JOIN resources res ON res.resource_id = b.resource_id
        LEFT JOIN employees emp ON emp.employee_id = b.employee_id AND emp.deleted_at IS NULL
        WHERE b.bundle_id = @BundleId
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );

    DECLARE @Copy INT = 0;
    DECLARE @LastPrintJobId INT;
    WHILE @Copy < @Copies
    BEGIN
        INSERT INTO print_jobs (job_type, ref_id, payload, [status], created_at, created_by)
        VALUES ('BUNDLE_LABEL', @BundleId, @Payload, 'PENDING', SYSDATETIME(), @UserId);

        SET @LastPrintJobId = CAST(SCOPE_IDENTITY() AS INT);
        SET @Copy += 1;
    END

    SELECT @LastPrintJobId AS NewPrintJobId;
END;
GO
