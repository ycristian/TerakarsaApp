-- Prompt 48: perakitan isi cetakan thermal (ESC/POS) pindah dari C# (EscPosBuilder) ke SQL --
-- SP menghasilkan TEKS BER-TOKEN (bukan byte printer), diterjemahkan oleh
-- TerakarsaApp.PrintService/EscPosRenderer.cs saat job diklaim. Revisi layout struk cukup
-- CREATE OR ALTER PROCEDURE di sini, tanpa build/publish ulang service. Kamus token lengkap
-- ada di claude prompt/prompt_48_thermal_token_render.md bagian 2 -- SP di file ini WAJIB
-- patuh persis ke kamus itu (renderer tidak mengenal token di luar kamus, lihat aturan
-- "token tidak dikenal diabaikan").
--
-- Label bundle TSC TTP-244 Pro (TsplBuilder.cs, job_type BUNDLE_LABEL/PACK_LABEL/REJECT_NOTE)
-- TIDAK disentuh sama sekali oleh prompt ini -- jalur RAW_TSPL tetap dirakit C# seperti sekarang.

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Potong teks dengan "..." (ASCII, sama pola dengan TsplBuilder.Truncate/EscPosBuilder lama --
-- printer ESC/POS di sini pakai ASCII, bukan unicode ellipsis) bila melebihi @Len. Dipakai SP
-- render kalau perlu memangkas manual di luar mekanisme kolom {2COL}/{ROW} (renderer C#
-- menangani sendiri pemangkasan isi kolom).
CREATE OR ALTER FUNCTION SIS_fn_Trunc(@Text NVARCHAR(MAX), @Len INT)
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @Text IS NULL RETURN NULL;
    IF LEN(@Text) <= @Len RETURN @Text;
    IF @Len <= 3 RETURN LEFT(@Text, @Len);
    RETURN LEFT(@Text, @Len - 3) + N'...';
END;
GO

-- Kamus token pakai kurung kurawal sebagai penanda -- teks dinamis (nama project/artikel/
-- catatan bebas, dst, berasal dari input pengguna) WAJIB di-escape dulu sebelum digabung ke
-- baris token: "{" literal jadi "{{" (lihat kamus token poin 2), dan CR/LF dilucuti supaya satu
-- nilai data tidak diam-diam menjadi beberapa "baris cetak" (kamus: "Satu baris teks = satu
-- baris cetak"). Dipakai semua SP render token, bukan cuma kupon borongan.
CREATE OR ALTER FUNCTION SIS_fn_TokenEscape(@Text NVARCHAR(MAX))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    IF @Text IS NULL RETURN NULL;
    RETURN REPLACE(REPLACE(REPLACE(@Text, N'{', N'{{'), CHAR(13), N' '), CHAR(10), N' ');
END;
GO

-- Ad hoc (2026-08-27): padding lebar-tetap utk tabel manual (kolom NO/OK/R1..LS/WF di
-- SIS_Print_RekapProduksi) -- dipakai LANGSUNG sbg teks polos, BUKAN lewat {ROW:...} (yang cuma
-- menjamin kolom TERAKHIR rata kanan, sisanya rata kiri -- di sini semua kolom angka perlu rata
-- kanan sekaligus, jadi di-padding manual sebelum digabung, "1 spasi 1 karakter", dipotong kalau
-- kepanjangan supaya alignment tabel tidak berantakan).
CREATE OR ALTER FUNCTION SIS_fn_PadRight(@Text NVARCHAR(50), @Width INT)
RETURNS NVARCHAR(50)
AS
BEGIN
    SET @Text = ISNULL(@Text, N'');
    IF LEN(@Text) > @Width SET @Text = LEFT(@Text, @Width);
    RETURN @Text + REPLICATE(N' ', @Width - LEN(@Text));
END;
GO

CREATE OR ALTER FUNCTION SIS_fn_PadLeft(@Text NVARCHAR(50), @Width INT)
RETURNS NVARCHAR(50)
AS
BEGIN
    SET @Text = ISNULL(@Text, N'');
    IF LEN(@Text) > @Width SET @Text = LEFT(@Text, @Width);
    RETURN REPLICATE(N' ', @Width - LEN(@Text)) + @Text;
END;
GO

-- Muara semua render thermal (job_type -> SP render sesuai routing). Dipanggil API lewat
-- GET api/print/render/{printJobId} SAAT job diklaim (bukan saat dibuat) -- cetak ulang
-- otomatis mengikuti layout & data terkini. Kembalikan satu kolom TokenText NVARCHAR(MAX).
--
-- @DryRun: kalau 1, @PrintJobId dibaca dari print_jobs_dryrun (lihat
-- sql/alter_print_jobs_dryrun.sql), BUKAN print_jobs -- supaya rendering hasil testing tidak
-- pernah bergantung/menyentuh baris live. Routing (print_job_routes/print_devices) TETAP
-- sama untuk keduanya.
CREATE OR ALTER PROCEDURE SIS_Print_Dispatch
    @PrintJobId INT,
    @DryRun     BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @JobType VARCHAR(30), @RefId INT, @Payload NVARCHAR(MAX), @PrintDeviceId INT;

    IF @DryRun = 1
        SELECT @JobType = job_type, @RefId = ref_id, @Payload = payload, @PrintDeviceId = print_device_id
        FROM print_jobs_dryrun WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;
    ELSE
        SELECT @JobType = job_type, @RefId = ref_id, @Payload = payload, @PrintDeviceId = print_device_id
        FROM print_jobs WHERE print_job_id = @PrintJobId AND deleted_at IS NULL;

    IF @JobType IS NULL
    BEGIN
        RAISERROR('Print job %d tidak ditemukan.', 16, 1, @PrintJobId);
        RETURN;
    END

    -- Penjagaan salah-pasang printer: route salah pasang tidak menghasilkan error yang
    -- kelihatan di printer (bukan mode TOKEN = printer akan memuntahkan teks perintah mentah
    -- sebagai kertas) -- gagal jelas di sini jauh lebih baik daripada diam-diam salah.
    DECLARE @RenderMode VARCHAR(20), @PrinterName VARCHAR(255);
    SELECT @RenderMode = render_mode, @PrinterName = printer_name
    FROM print_devices WHERE print_device_id = @PrintDeviceId AND deleted_at IS NULL;

    IF @RenderMode IS NULL OR @RenderMode <> 'TOKEN'
    BEGIN
        -- RAISERROR hanya menerima variabel/literal sebagai argumen substitusi, bukan
        -- ekspresi -- ISNULL() harus ditampung ke variabel dulu.
        DECLARE @PrinterNameSafe VARCHAR(255) = ISNULL(@PrinterName, '(tidak diketahui)');
        RAISERROR('Job %d diarahkan ke printer %s yang bukan mode TOKEN.', 16, 1, @PrintJobId, @PrinterNameSafe);
        RETURN;
    END

    IF @JobType = 'KUPON_BORONGAN'
    BEGIN
        EXEC SIS_Print_KuponBorongan @RefId = @RefId, @Payload = @Payload;
    END
    ELSE IF @JobType = 'REKAP_PRODUKSI'
    BEGIN
        EXEC SIS_Print_RekapProduksi @RefId = @RefId, @Payload = @Payload;
    END
    ELSE IF @JobType = 'REKAP_WIP'
    BEGIN
        EXEC SIS_Print_RekapWip @RefId = @RefId, @Payload = @Payload;
    END
    ELSE
    BEGIN
        RAISERROR('Job type %s belum punya SP render.', 16, 1, @JobType);
        RETURN;
    END
END;
GO

-- Kupon borongan (job_type KUPON_BORONGAN, @RefId = article_workflow_logs.workflow_log_id).
-- Layout SAMA PERSIS dengan cetakan lama (TerakarsaApp.PrintService/EscPosBuilder.
-- BuildKuponBorongan, sebelum prompt ini) -- diterjemahkan elemen per elemen ke token, TIDAK
-- didesain ulang. Data diambil LANGSUNG dari tabel (bukan dari @Payload -- payload lama hanya
-- dipertahankan sebagai parameter untuk kompatibilitas signature, tidak dipakai) supaya cetak
-- ulang mengikuti data terkini. Join sengaja meniru PERSIS @KuponPayload_Create di
-- sql/sp_WorkflowLog_Manage.sql (tanpa filter deleted_at pada tabel yang di-JOIN, konsisten
-- dengan pola pembuatan payload aslinya).
CREATE OR ALTER PROCEDURE SIS_Print_KuponBorongan
    @RefId   INT,
    @Payload NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @WorkflowLogId INT, @Serial VARCHAR(20), @BundleNo INT, @BundleLetter VARCHAR(1),
        @ProjectName NVARCHAR(200), @ArticleName NVARCHAR(200), @BundleRemarks NVARCHAR(500),
        @Style NVARCHAR(100), @Color NVARCHAR(100), @SizeName NVARCHAR(50),
        @QtyOk INT, @QtyRejectPrint INT, @QtyRejectFabric INT, @QtyRejectSewing INT,
        @QtyRejectRework INT, @QtyLost INT, @TailorName NVARCHAR(200), @DivisionName NVARCHAR(150),
        @LineResourceName NVARCHAR(150), @ReceivedAt DATETIME2, @CreatedAt DATETIME2, @UpdatedAt DATETIME2;

    SELECT
        @WorkflowLogId = awl.workflow_log_id,
        @Serial = b.serial,
        @BundleNo = b.bundle_no,
        @BundleLetter = pr.bundle_letter,
        @ProjectName = pr.project_name,
        @ArticleName = a.article_name,
        @BundleRemarks = b.remarks,
        @Style = a.style,
        @Color = a.color,
        @SizeName = spd.size_name,
        @QtyOk = awl.qty_ok,
        @QtyRejectPrint = awl.qty_reject_print,
        @QtyRejectFabric = awl.qty_reject_fabric,
        @QtyRejectSewing = awl.qty_reject_sewing,
        @QtyRejectRework = awl.qty_reject_rework,
        @QtyLost = awl.qty_lost,
        @TailorName = ISNULL(ben.employee_name, ISNULL(brn.resource_name, ISNULL(arn.resource_name, N'-'))),
        @DivisionName = dv.division_name,
        @LineResourceName = lrn.resource_name,
        @ReceivedAt = awl.received_at,
        @CreatedAt = awl.created_at,
        @UpdatedAt = awl.updated_at
    FROM article_workflow_logs awl
    INNER JOIN article_workflows aw ON aw.article_workflow_id = awl.article_workflow_id
    INNER JOIN articles a ON a.article_id = aw.article_id
    INNER JOIN projects pr ON pr.project_id = a.project_id
    LEFT JOIN divisions dv ON dv.division_id = awl.division_id
    LEFT JOIN bundles b ON b.bundle_id = awl.bundle_id
    LEFT JOIN article_sizes asz ON asz.article_size_id = b.article_size_id
    LEFT JOIN size_pack_details spd ON spd.size_pack_detail_id = asz.size_pack_detail_id
    LEFT JOIN resources brn ON brn.resource_id = b.resource_id
    LEFT JOIN resources arn ON arn.resource_id = awl.resource_id
    LEFT JOIN employees ben ON ben.employee_id = b.employee_id AND ben.deleted_at IS NULL
    LEFT JOIN resources lrn ON lrn.resource_id = ben.resource_id
    WHERE awl.workflow_log_id = @RefId;

    IF @WorkflowLogId IS NULL
    BEGIN
        RAISERROR('Log workflow %d tidak ditemukan untuk kupon borongan.', 16, 1, @RefId);
        RETURN;
    END

    DECLARE @NL CHAR(1) = CHAR(10);
    DECLARE @T NVARCHAR(MAX) = N'';

    -- Header: "Coupon {id} - {divisi}" (bold) + separator.
    SET @T += N'{B}Coupon ' + CAST(@WorkflowLogId AS NVARCHAR(20)) + N' - ' + dbo.SIS_fn_TokenEscape(ISNULL(@DivisionName, N'-')) + @NL;
    SET @T += N'{HR}' + @NL;

    -- Serial (bundle no) kiri, size kanan (bold); lalu project/artikel/style-color polos.
    DECLARE @BundleNoText NVARCHAR(30) = CASE WHEN @BundleLetter IS NULL THEN CAST(@BundleNo AS NVARCHAR(20)) ELSE @BundleLetter + N'-' + CAST(@BundleNo AS NVARCHAR(20)) END;
    SET @T += N'{B}{2COL}' + dbo.SIS_fn_TokenEscape(ISNULL(@Serial, N'-')) + N' (' + @BundleNoText + N')|' + dbo.SIS_fn_TokenEscape(ISNULL(@SizeName, N'')) + @NL;
    SET @T += dbo.SIS_fn_TokenEscape(@ProjectName) + @NL;
    SET @T += dbo.SIS_fn_TokenEscape(LTRIM(RTRIM(@ArticleName))) + @NL;

    DECLARE @StyleColor NVARCHAR(220) = LTRIM(RTRIM(ISNULL(@Style, N'') + N' ' + ISNULL(@Color, N'')));
    IF @StyleColor <> N''
        SET @T += dbo.SIS_fn_TokenEscape(@StyleColor) + @NL;
    SET @T += N'{HR}' + @NL;

    -- Line + penjahit (bold).
    DECLARE @LineTailor NVARCHAR(400) = CASE WHEN @LineResourceName IS NULL OR LTRIM(RTRIM(@LineResourceName)) = N''
        THEN ISNULL(@TailorName, N'-') ELSE @LineResourceName + N' - ' + ISNULL(@TailorName, N'-') END;
    SET @T += N'{B}' + dbo.SIS_fn_TokenEscape(@LineTailor) + @NL;

    SET @T += N'{B}Qty OK : ' + CAST(@QtyOk AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectPrint > 0 SET @T += N'Reject Print : ' + CAST(@QtyRejectPrint AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectFabric > 0 SET @T += N'Reject Bahan : ' + CAST(@QtyRejectFabric AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectSewing > 0 SET @T += N'Reject Jahit : ' + CAST(@QtyRejectSewing AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyRejectRework > 0 SET @T += N'Rework : ' + CAST(@QtyRejectRework AS NVARCHAR(10)) + N' pcs' + @NL;
    IF @QtyLost > 0 SET @T += N'Hilang : ' + CAST(@QtyLost AS NVARCHAR(10)) + N' pcs' + @NL;

    -- Note bundle_remarks: satu baris logis, word-wrap otomatis ditangani renderer (tidak
    -- perlu dipecah manual di SP seperti EscPosBuilder.WrapLines lama).
    IF @BundleRemarks IS NOT NULL AND LTRIM(RTRIM(@BundleRemarks)) <> N''
        SET @T += N'Note : ' + dbo.SIS_fn_TokenEscape(@BundleRemarks) + @NL;

    SET @T += N'{HR}' + @NL;

    DECLARE @FooterAt DATETIME2 = ISNULL(@UpdatedAt, @CreatedAt);
    SET @T += FORMAT(@FooterAt, 'dd/MM/yyyy HH:mm');

    -- Tidak menulis {CUT} -- worker otomatis menambahkan {FEED:4}{CUT} di akhir dokumen
    -- (lihat aturan renderer di prompt), sama seperti SP render lain.
    SELECT @T AS TokenText;
END;
GO

-- Ad hoc (2026-08-27): render rekap produksi (job_type REKAP_PRODUKSI). BEDA dgn
-- SIS_Print_KuponBorongan di atas: data TIDAK di-requery ulang dari tabel -- @RefId di sini cuma
-- division_id (lihat INSERT print_jobs di SIS_Report_RekapStrukPrint, sql/sp_Report_RekapStruk.sql),
-- sendirian tidak cukup mengidentifikasi resource/employee/tanggal yang dipilih operator -- jadi
-- payload JSON yang SUDAH dihitung SIS_Report_RekapStrukPrint DIPAKAI LANGSUNG lewat OPENJSON.
-- Layout: master (divisi/resource/tanggal/total qty) -> rekap total per artikel (dicetak DULU,
-- "rekap total di paling atas") -> detail per baris log mentah, dikelompokkan visual per
-- "No PO - Artikel" (header grup dicetak sekali, lihat RnInGroup = 1). Baris non-bundle
-- (BundleNo NULL, mis. Cutting) dicetak "workflow_log_id - -" tanpa serial. Reject 5 kategori
-- (Print/Fabric/Sewing/Rework/Hilang) HANYA dicetak kalau qty > 0, di kedua bagian.
CREATE OR ALTER PROCEDURE SIS_Print_RekapProduksi
    @RefId   INT,
    @Payload NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Payload IS NULL OR LTRIM(RTRIM(@Payload)) = N''
    BEGIN
        RAISERROR('Payload rekap produksi kosong utk print job ini.', 16, 1);
        RETURN;
    END

    DECLARE @NL CHAR(1) = CHAR(10);
    DECLARE @DivisionName NVARCHAR(150), @ResourceName NVARCHAR(150), @EmployeeName NVARCHAR(150),
            @TanggalStr VARCHAR(20), @TotalQty INT;

    SELECT
        @DivisionName = JSON_VALUE(@Payload, '$.division_name'),
        @ResourceName = JSON_VALUE(@Payload, '$.resource_name'),
        @EmployeeName = JSON_VALUE(@Payload, '$.employee_name'),
        @TanggalStr   = JSON_VALUE(@Payload, '$.tanggal'),
        @TotalQty     = JSON_VALUE(@Payload, '$.total_qty');

    -- Detail per baris log mentah sbg TABEL (bukan blok multi-baris) -- dikelompokkan visual
    -- per "No PO - Artikel", header grup + header kolom tabel dicetak sekali (RnInGroup = 1).
    -- Header grup Ad hoc (2026-08-28): 2 baris -- "{No PO} - {Nama PO}" (bold) lalu Nama Artikel
    -- (polos) di baris berikutnya (sebelumnya 1 baris gabungan "{No PO} - {Artikel}").
    -- Kolom tabel: NO (bundle letter+no, kosong kalau non-bundle -- "No dihilangin" =
    -- dikosongkan, posisi kolom tetap ada demi alignment) lebar 5, OK/R1/R2/R3/RW (5 kategori
    -- qty_ok/reject Print/Fabric/Sewing/Rework) lebar 4 rata kanan (kosong kalau 0), LS (Hilang)
    -- lebar 4, WF (workflow_log_id, SELALU ada) lebar 6 rata kanan, Time (jam kejadian HH:mm)
    -- lebar 7 (1 spasi + isi rata kiri 6), Emp (pelaksana, kolom TERAKHIR, tanpa pipe penutup,
    -- dipotong 10 karakter -- total lebar baris pas 64 = chars_per_line_small, jangan ditambah
    -- tanpa hitung ulang supaya tidak word-wrap & merusak alignment). TIDAK ada kolom serial (SN).
    -- Baris terakhir tiap grup (RnInGroup = GroupCount) ditutup baris Total (bold, TANPA pipe --
    -- cuma spasi di posisi kolom yg sama, kolom NO/WF/Time/Emp selalu kosong, kolom lain kosong
    -- kalau totalnya 0, trailing blank di-RTRIM) + 1 baris kosong sbg pemisah sebelum grup
    -- artikel berikutnya. Urutan baris dalam grup: nama Emp (penjahit) dulu, baru EventTime (jam
    -- kejadian) -- sama pola dgn Rekap WIP (2026-08-28).
    -- Ad hoc (2026-08-27): "Rekap per Artikel" (ringkasan terpisah di atas detail) DIHAPUS --
    -- baris Total per grup di sini sudah menggantikan fungsinya.
    -- {FB} = font B (kecil/rapat) -- dipasang per-baris (header tabel, tiap baris data, baris
    -- Total) supaya bagian tabel tercetak lebih ringkas, terpisah dari baris master/HR di
    -- sekitarnya yang tetap font default.
    DECLARE @DetailText NVARCHAR(MAX);
    DECLARE @TableHeader NVARCHAR(80) = N'{FB}' +
        dbo.SIS_fn_PadRight(N'NO', 5) + N'|' + dbo.SIS_fn_PadLeft(N'OK', 4) + N'|'
        + dbo.SIS_fn_PadLeft(N'R1', 4) + N'|' + dbo.SIS_fn_PadLeft(N'R2', 4) + N'|'
        + dbo.SIS_fn_PadLeft(N'R3', 4) + N'|' + dbo.SIS_fn_PadLeft(N'RW', 4) + N'|'
        + dbo.SIS_fn_PadLeft(N'LS', 4) + N'|' + dbo.SIS_fn_PadLeft(N'WF', 6) + N'|'
        + N' ' + dbo.SIS_fn_PadRight(N'Time', 6) + N'|' + N' Emp';
    ;WITH DetailRows AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY NoPo, ArticleName ORDER BY PelaksanaName ASC, EventTime ASC) AS RnInGroup,
            COUNT(*) OVER (PARTITION BY NoPo, ArticleName) AS GroupCount,
            SUM(QtyOk) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyOk,
            SUM(QtyRejectPrint) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyRejectPrint,
            SUM(QtyRejectFabric) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyRejectFabric,
            SUM(QtyRejectSewing) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyRejectSewing,
            SUM(QtyRejectRework) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyRejectRework,
            SUM(QtyLost) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyLost
        FROM OPENJSON(@Payload, '$.detail_rows') WITH (
            NoPo             NVARCHAR(50)  '$.no_po',
            ProjectName      NVARCHAR(200) '$.project_name',
            ArticleName      NVARCHAR(200) '$.article_name',
            WorkflowLogId    INT           '$.workflow_log_id',
            BundleNo         INT           '$.bundle_no',
            BundleLetter     VARCHAR(1)    '$.bundle_letter',
            PelaksanaName    NVARCHAR(150) '$.pelaksana_name',
            EventTime        DATETIME2     '$.event_time',
            QtyOk            INT           '$.qty_ok',
            QtyRejectPrint   INT           '$.qty_reject_print',
            QtyRejectFabric  INT           '$.qty_reject_fabric',
            QtyRejectSewing  INT           '$.qty_reject_sewing',
            QtyRejectRework  INT           '$.qty_reject_rework',
            QtyLost          INT           '$.qty_lost'
        )
    )
    SELECT @DetailText = STRING_AGG(
        CAST(
            CASE WHEN RnInGroup = 1
                THEN N'{B}' + dbo.SIS_fn_TokenEscape(ISNULL(NoPo, N'-')) + N' - ' + dbo.SIS_fn_TokenEscape(ISNULL(ProjectName, N'-')) + @NL
                     + dbo.SIS_fn_TokenEscape(ArticleName) + @NL
                     + @TableHeader + @NL
                ELSE N''
            END
            + N'{FB}'
            + dbo.SIS_fn_PadRight(CASE WHEN BundleNo IS NULL THEN N'' ELSE ISNULL(BundleLetter, N'') + CAST(BundleNo AS NVARCHAR(10)) END, 5) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN QtyOk > 0 THEN CAST(QtyOk AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN QtyRejectPrint  > 0 THEN CAST(QtyRejectPrint  AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN QtyRejectFabric > 0 THEN CAST(QtyRejectFabric AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN QtyRejectSewing > 0 THEN CAST(QtyRejectSewing AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN QtyRejectRework > 0 THEN CAST(QtyRejectRework AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN QtyLost         > 0 THEN CAST(QtyLost         AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CAST(WorkflowLogId AS NVARCHAR(10)), 6) + N'|'
            + N' ' + dbo.SIS_fn_PadRight(ISNULL(FORMAT(EventTime, N'HH:mm'), N''), 6) + N'|'
            + N' ' + dbo.SIS_fn_TokenEscape(LEFT(ISNULL(PelaksanaName, N''), 10))
            + @NL
            + CASE WHEN RnInGroup = GroupCount
                THEN N'{B}{FB}' + RTRIM(
                        dbo.SIS_fn_PadRight(N'', 5) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupQtyOk > 0 THEN CAST(GroupQtyOk AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupQtyRejectPrint  > 0 THEN CAST(GroupQtyRejectPrint  AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupQtyRejectFabric > 0 THEN CAST(GroupQtyRejectFabric AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupQtyRejectSewing > 0 THEN CAST(GroupQtyRejectSewing AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupQtyRejectRework > 0 THEN CAST(GroupQtyRejectRework AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupQtyLost         > 0 THEN CAST(GroupQtyLost         AS NVARCHAR(10)) ELSE N'' END, 4)
                     ) + @NL + @NL
                ELSE N''
            END
        AS NVARCHAR(MAX)), N''
    ) WITHIN GROUP (ORDER BY NoPo ASC, ArticleName ASC, PelaksanaName ASC, EventTime ASC)
    FROM DetailRows;

    -- Ad hoc (2026-08-31): segmen Total Keseluruhan di paling bawah struk -- total semua kolom
    -- OK/R1/R2/R3/RW/LS dijumlah lintas semua artikel/grup (bukan per-grup lagi), 1 tabel ringkas
    -- di akhir sesudah seluruh Detail. Dihitung langsung dari payload (bukan window function).
    DECLARE @GrandQtyOk INT, @GrandR1 INT, @GrandR2 INT, @GrandR3 INT, @GrandRW INT, @GrandLS INT;
    SELECT
        @GrandQtyOk = SUM(QtyOk), @GrandR1 = SUM(QtyRejectPrint), @GrandR2 = SUM(QtyRejectFabric),
        @GrandR3 = SUM(QtyRejectSewing), @GrandRW = SUM(QtyRejectRework), @GrandLS = SUM(QtyLost)
    FROM OPENJSON(@Payload, '$.detail_rows') WITH (
        QtyOk            INT '$.qty_ok',
        QtyRejectPrint   INT '$.qty_reject_print',
        QtyRejectFabric  INT '$.qty_reject_fabric',
        QtyRejectSewing  INT '$.qty_reject_sewing',
        QtyRejectRework  INT '$.qty_reject_rework',
        QtyLost          INT '$.qty_lost'
    );
    DECLARE @GrandHeader NVARCHAR(60) = N'{FB}' +
        dbo.SIS_fn_PadLeft(N'OK', 4) + N'|' + dbo.SIS_fn_PadLeft(N'R1', 4) + N'|'
        + dbo.SIS_fn_PadLeft(N'R2', 4) + N'|' + dbo.SIS_fn_PadLeft(N'R3', 4) + N'|'
        + dbo.SIS_fn_PadLeft(N'RW', 4) + N'|' + dbo.SIS_fn_PadLeft(N'LS', 4);
    DECLARE @GrandTotalRow NVARCHAR(60) = N'{B}{FB}' + RTRIM(
        dbo.SIS_fn_PadLeft(CASE WHEN ISNULL(@GrandQtyOk,0) > 0 THEN CAST(@GrandQtyOk AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
        + dbo.SIS_fn_PadLeft(CASE WHEN ISNULL(@GrandR1,0) > 0 THEN CAST(@GrandR1 AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
        + dbo.SIS_fn_PadLeft(CASE WHEN ISNULL(@GrandR2,0) > 0 THEN CAST(@GrandR2 AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
        + dbo.SIS_fn_PadLeft(CASE WHEN ISNULL(@GrandR3,0) > 0 THEN CAST(@GrandR3 AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
        + dbo.SIS_fn_PadLeft(CASE WHEN ISNULL(@GrandRW,0) > 0 THEN CAST(@GrandRW AS NVARCHAR(10)) ELSE N'' END, 4) + N' '
        + dbo.SIS_fn_PadLeft(CASE WHEN ISNULL(@GrandLS,0) > 0 THEN CAST(@GrandLS AS NVARCHAR(10)) ELSE N'' END, 4)
    );

    DECLARE @T NVARCHAR(MAX) = N'';
    SET @T += N'{B}Rekap Produksi - ' + dbo.SIS_fn_TokenEscape(ISNULL(@DivisionName, N'-')) + @NL;
    IF @ResourceName IS NOT NULL SET @T += dbo.SIS_fn_TokenEscape(@ResourceName) + @NL;
    IF @EmployeeName IS NOT NULL SET @T += dbo.SIS_fn_TokenEscape(@EmployeeName) + @NL;
    SET @T += N'Tanggal : ' + FORMAT(CAST(@TanggalStr AS DATE), 'dd/MM/yyyy') + @NL;
    SET @T += N'{HR}' + @NL;
    SET @T += N'{B}Total Qty : ' + CAST(ISNULL(@TotalQty, 0) AS NVARCHAR(20)) + N' pcs' + @NL;
    SET @T += N'{HR}' + @NL;
    SET @T += ISNULL(@DetailText, N'(tidak ada data)' + @NL);
    SET @T += N'{HR}' + @NL;
    SET @T += N'{B}Total Keseluruhan' + @NL;
    SET @T += @GrandHeader + @NL;
    SET @T += @GrandTotalRow + @NL;
    SET @T += N'{HR}' + @NL;
    SET @T += FORMAT(SYSDATETIME(), 'dd/MM/yyyy HH:mm');

    -- Tidak menulis {CUT} -- worker otomatis menambahkan {FEED:4}{CUT} di akhir dokumen.
    SELECT @T AS TokenText;
END;
GO

-- Ad hoc (2026-08-28, diperbarui 2026-08-28): render "Rekap WIP" (job_type REKAP_WIP, SP data di
-- SIS_Report_WipPrint, sql/sp_Report_RekapStruk.sql). Sama pola dgn SIS_Print_RekapProduksi --
-- @RefId cuma division_id, tidak cukup identifikasi resource/tanggal, jadi payload JSON DIPAKAI
-- LANGSUNG lewat OPENJSON, bukan requery ulang.
-- Dikelompokkan per "No PO - Artikel" (2 baris header: "{No PO} - {Nama PO}" bold lalu Nama
-- Artikel polos, dicetak sekali per grup, RnInGroup = 1). Payload TIDAK dibatasi (semua bundle
-- WIP tercetak). Urutan baris DALAM grup: nama Emp (penjahit) dulu, baru tanggal/jam terima
-- (BUKAN cuma tanggal/jam spt sebelumnya).
-- Kolom tabel: SN (bundles.serial, mis. "B26-002824"), NO (bundle letter+no), Qty (sisa BELUM
-- dihasilkan), RW (subset Rework, kosong kalau 0), WF (workflow_log_id), Date (tanggal+jam
-- bundle DITERIMA divisi ini, format "dd/MM HH:mm" mis. "08/08 10:10"), Emp (penjahit bundle,
-- dipotong 10 karakter). Baris terakhir tiap grup (RnInGroup = GroupCount) ditutup baris Total
-- (bold, TANPA pipe, cuma Qty & Rework yg diisi -- SN/NO/WF/Date/Emp selalu kosong) + 1 baris
-- kosong pemisah, PERSIS pola Total per grup di SIS_Print_RekapProduksi. Master juga ditambah
-- "Total Qty WIP" (grand total semua grup) dan "Total Rework" (grand total, HANYA kalau > 0).
CREATE OR ALTER PROCEDURE SIS_Print_RekapWip
    @RefId   INT,
    @Payload NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Payload IS NULL OR LTRIM(RTRIM(@Payload)) = N''
    BEGIN
        RAISERROR('Payload rekap WIP kosong utk print job ini.', 16, 1);
        RETURN;
    END

    DECLARE @NL CHAR(1) = CHAR(10);
    DECLARE @DivisionName NVARCHAR(150), @ResourceName NVARCHAR(150), @EmployeeName NVARCHAR(150),
            @TanggalStr VARCHAR(20);

    SELECT
        @DivisionName  = JSON_VALUE(@Payload, '$.division_name'),
        @ResourceName  = JSON_VALUE(@Payload, '$.resource_name'),
        @EmployeeName  = JSON_VALUE(@Payload, '$.employee_name'),
        @TanggalStr    = JSON_VALUE(@Payload, '$.tanggal');

    DECLARE @GrandQtyWip INT, @GrandReworkQty INT;
    SELECT
        @GrandQtyWip    = ISNULL(SUM(QtyWip), 0),
        @GrandReworkQty = ISNULL(SUM(ReworkQty), 0)
    FROM OPENJSON(@Payload, '$.wip_rows') WITH (
        QtyWip    INT '$.qty_wip',
        ReworkQty INT '$.rework_qty'
    );

    DECLARE @WipTableHeader NVARCHAR(80) = N'{FB}' +
        dbo.SIS_fn_PadRight(N'SN', 10) + N'|' + dbo.SIS_fn_PadRight(N'NO', 5) + N'|' + dbo.SIS_fn_PadLeft(N'Qty', 4) + N'|'
        + dbo.SIS_fn_PadLeft(N'RW', 4) + N'|' + dbo.SIS_fn_PadLeft(N'WF', 6) + N'|'
        + N' ' + dbo.SIS_fn_PadRight(N'Date', 11) + N'|' + N' Emp';

    DECLARE @WipText NVARCHAR(MAX);
    ;WITH WipRows AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY NoPo, ArticleName ORDER BY PelaksanaName ASC, ReceivedAt ASC) AS RnInGroup,
            COUNT(*) OVER (PARTITION BY NoPo, ArticleName) AS GroupCount,
            SUM(QtyWip) OVER (PARTITION BY NoPo, ArticleName) AS GroupQtyWip,
            SUM(ReworkQty) OVER (PARTITION BY NoPo, ArticleName) AS GroupReworkQty
        FROM OPENJSON(@Payload, '$.wip_rows') WITH (
            NoPo             NVARCHAR(50)  '$.no_po',
            ProjectName      NVARCHAR(200) '$.project_name',
            ArticleName      NVARCHAR(200) '$.article_name',
            BundleNo         INT           '$.bundle_no',
            BundleLetter     VARCHAR(1)    '$.bundle_letter',
            Serial           VARCHAR(20)   '$.serial',
            QtyWip           INT           '$.qty_wip',
            ReworkQty        INT           '$.rework_qty',
            WorkflowLogId    INT           '$.workflow_log_id',
            ReceivedAt       DATETIME2     '$.received_at',
            PelaksanaName    NVARCHAR(150) '$.pelaksana_name'
        )
    )
    SELECT @WipText = STRING_AGG(
        CAST(
            CASE WHEN RnInGroup = 1
                THEN N'{B}' + dbo.SIS_fn_TokenEscape(ISNULL(NoPo, N'-')) + N' - ' + dbo.SIS_fn_TokenEscape(ISNULL(ProjectName, N'-')) + @NL
                     + dbo.SIS_fn_TokenEscape(ArticleName) + @NL
                     + @WipTableHeader + @NL
                ELSE N''
            END
            + N'{FB}'
            + dbo.SIS_fn_PadRight(ISNULL(Serial, N''), 10) + N'|'
            + dbo.SIS_fn_PadRight(ISNULL(BundleLetter, N'') + CAST(BundleNo AS NVARCHAR(10)), 5) + N'|'
            + dbo.SIS_fn_PadLeft(CAST(QtyWip AS NVARCHAR(10)), 4) + N'|'
            + dbo.SIS_fn_PadLeft(CASE WHEN ReworkQty > 0 THEN CAST(ReworkQty AS NVARCHAR(10)) ELSE N'' END, 4) + N'|'
            + dbo.SIS_fn_PadLeft(CAST(WorkflowLogId AS NVARCHAR(10)), 6) + N'|'
            + N' ' + dbo.SIS_fn_PadRight(ISNULL(FORMAT(ReceivedAt, N'dd/MM HH:mm'), N''), 11) + N'|'
            + N' ' + dbo.SIS_fn_TokenEscape(LEFT(ISNULL(PelaksanaName, N''), 10))
            + @NL
            + CASE WHEN RnInGroup = GroupCount
                THEN N'{B}{FB}' + RTRIM(
                        dbo.SIS_fn_PadRight(N'', 10) + N' '
                        + dbo.SIS_fn_PadRight(N'', 5) + N' '
                        + dbo.SIS_fn_PadLeft(CAST(GroupQtyWip AS NVARCHAR(10)), 4) + N' '
                        + dbo.SIS_fn_PadLeft(CASE WHEN GroupReworkQty > 0 THEN CAST(GroupReworkQty AS NVARCHAR(10)) ELSE N'' END, 4)
                     ) + @NL + @NL
                ELSE N''
            END
        AS NVARCHAR(MAX)), N''
    ) WITHIN GROUP (ORDER BY NoPo ASC, ArticleName ASC, PelaksanaName ASC, ReceivedAt ASC)
    FROM WipRows;

    DECLARE @T NVARCHAR(MAX) = N'';
    SET @T += N'{B}Rekap WIP - ' + dbo.SIS_fn_TokenEscape(ISNULL(@DivisionName, N'-')) + @NL;
    IF @ResourceName IS NOT NULL SET @T += dbo.SIS_fn_TokenEscape(@ResourceName) + @NL;
    IF @EmployeeName IS NOT NULL SET @T += dbo.SIS_fn_TokenEscape(@EmployeeName) + @NL;
    SET @T += N'Tanggal : ' + FORMAT(CAST(@TanggalStr AS DATE), 'dd/MM/yyyy') + @NL;
    SET @T += N'{HR}' + @NL;
    SET @T += N'{B}Total Qty WIP : ' + CAST(@GrandQtyWip AS NVARCHAR(20)) + N' pcs' + @NL;
    IF @GrandReworkQty > 0
        SET @T += N'{B}Total Rework : ' + CAST(@GrandReworkQty AS NVARCHAR(20)) + N' pcs' + @NL;
    SET @T += N'{HR}' + @NL;
    IF @WipText IS NOT NULL
    BEGIN
        SET @T += @WipText;
    END
    ELSE
    BEGIN
        SET @T += N'(tidak ada WIP)' + @NL;
    END
    SET @T += N'{HR}' + @NL;
    SET @T += FORMAT(SYSDATETIME(), 'dd/MM/yyyy HH:mm');

    -- Tidak menulis {CUT} -- worker otomatis menambahkan {FEED:4}{CUT} di akhir dokumen.
    SELECT @T AS TokenText;
END;
GO
